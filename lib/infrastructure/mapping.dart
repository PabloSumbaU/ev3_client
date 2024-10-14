import 'dart:collection';
import 'dart:math';
import 'dart:async';
import 'dart:ui';
import 'package:ev3_client/utils.dart';
import 'package:logging/logging.dart';
import 'package:image/image.dart' as img;
import 'socket_connection.dart' as socket;
import 'concurrent.dart';
import 'image.dart' as imaging;

final _log = Logger("Mapping");

class ImageData {
  ImageData(this.pixels, this.width, this.height, this.foreground, this.background);

  final List<double>? pixels;
  final int width, height;
  final Color foreground;
  final Color? background;
}

enum Commands {
  render, clear
}

class Map {
  // Robot is around 30 cm in length (~27 to be more precise)
  Map({required this.getSensorValue, required this.getPosition}): _map = HashMap(), currentQuadrant = const Point(0, 0) {
    _createChunks(currentQuadrant);
  }

  final HashMap<Point<int>, _Chunk> _map;
  Point<int> currentQuadrant;
  int Function() getSensorValue;
  (double x, double y, double angle) Function() getPosition;
  static const renderDistance = 1;
  static const mapSize = _Chunk.chunkSize * (2 * renderDistance + 1);
  static const timeBetweenUpdates = 20;

  static Future<Worker<Commands, img.Image>> startConcurrent() async {
    var worker = await Worker.getInstance<Commands, img.Image>(
      runnable: (sendPort, receivePort, workerState, store) async {
        Completer<void> dataCollected = Completer.sync();
        int count = 1;
        
        Timer.periodic(const Duration(seconds: 1), (timer) {
          var value = store["sensorValue"];
          _log.finer("Value: $value");
          
          if (value != null) {
            dataCollected.complete();
            timer.cancel();
            return;
          }

          _log.finer("Waiting for sensor data... x$count");
          count++;
        });

        await dataCollected.future;

        final map = Map(
          getSensorValue: () {
            List<String> data = store["sensorValue"].split(';');
            for (String string in data) {
              List<String> value = string.split(':');

              if (value[0] != 'ir') {
                continue;
              }
              
              return int.parse(value[1]);
            }

            return -1;
          },

          getPosition: () {
            List<String> data = store["position"].split(';');
            var values = data.map((e) => double.parse(e)).toList();

            //Dealing with TCP shenanigans, return previous position if we don't have a new one (cause it's invalid)
            if (values.length == 3) {
              store['previous_pos'] = values;
              return (values[0], values[1], values[2]);
            } else {
              return store['previous_pos'];
            }
            
          },
        );

        store['map'] = map;

        Timer.periodic(const Duration(milliseconds: timeBetweenUpdates), 
        (timer) {
          map.update();

          if (workerState() == WorkerState.terminated) {
            timer.cancel();
          }
        });
      },
      workerListener: (Commands data, store) async {
        const foreground = Color.fromARGB(255, 177, 104, 231);
        const background = Color.fromARGB(255, 0, 0, 0);
        final map = store['map'] as Map?;

        if (map == null) {
          return imaging.clearImage(mapSize, mapSize);
        }
        
        switch (data) {
          case Commands.render:
            return imaging.fromDoubleList(map.getCurrentMapData(), mapSize, mapSize, foreground, null);

          case Commands.clear:
            return imaging.clearImage(mapSize, mapSize);
        }
      },
      workerName: "Map"
    );

    socket.addSensorCallback((message) {
      worker.store(key: "sensorValue", value: message);
    });

    socket.addPositionCallback((x, y, angle) {
      worker.store(key: "position", value: "$x;$y;$angle");
    });

    return worker;
  }

  ///This function ensures the required chunk and the ones surrounding it in a radius around the center point [quadrant]
  ///are created. The radius is the render distance of the map. The specific amount of chunks created is (`renderDistance` * 2 + 1)².
  _Chunk _createChunks(Point<int> quadrant) {
    _Chunk center = _map.putIfAbsent(quadrant, () => _Chunk(quadrant));

    for (int x = -renderDistance; x <= renderDistance; x++) {
      for (int y = -renderDistance; y <= renderDistance; y++) {
        Point<int> newQuadrant = Point(quadrant.x + x, quadrant.y + y);
        _map.putIfAbsent(newQuadrant, () => _Chunk(newQuadrant));
      }
    }

    return center;
  }

  ///Creates a list representing the data of the map at and around the center point [quadrant] with the radius being the render
  ///distance of the map.
  List<double> getMapData(Point<int> quadrant) {
    List<double> data = [];

    for (int x = -renderDistance; x <= renderDistance; x++) {
      for (int chunkRow = 0; chunkRow < _Chunk.chunkSize; chunkRow++) {
        for (int y = -renderDistance; y <= renderDistance; y++) {
          Point<int> newQuadrant = Point(quadrant.x + x, quadrant.y + y);
          _Chunk? chunk = _map[newQuadrant];

          if (chunk == null) {
            _log.severe("Failed to get chunk at $newQuadrant");
            throw StateError("Failed to get chunk at $newQuadrant");	
          }

          data.addAll(chunk.mapRegion[chunkRow]); 
        }
      }
    }

    return data;
  }

  List<double> getCurrentMapData() {
    return getMapData(currentQuadrant);
  } 

  ///This function returns the quadrant of the given cell.
  Point<int> getQuadrant(Point<int> cell) {
    return Point<int>((cell.x / _Chunk.chunkSize).floor(), (cell.y / _Chunk.chunkSize).floor());
  }

  void update() async {
    if (_calibrating) {
      return;
    }

    final (x, y, angle) = getPosition();
    //FIXME: App became unresponsive and robot got stuck.
    //_log.finest("Position: $x, $y, $angle");

    Point<double> position = Point(x, y);
    position = Point(position.x + 15, position.y + 15);

    double lookAngle = angle;

    int sensorValue = getSensorValue();

    double distance = _sensorToCm(sensorValue);
    
    Point<int> cellDistance = Point<int>(
      (distance * cos(deg2rad(lookAngle)) / _Chunk.cellSize).ceil(),
      (distance * sin(deg2rad(lookAngle)) / _Chunk.cellSize).ceil()
    );

    Point<int> cellPosition = Point(position.x.floor(), position.y.floor());
    Point<int> affectedCell = cellPosition + cellDistance;

    currentQuadrant = getQuadrant(cellPosition);

    double certainty = await _certainty(sensorValue);

    Point<int> quadrant = getQuadrant(affectedCell);
    _Chunk? affectedChunk = _map[quadrant];

    _log.finest("Quadrant: $quadrant, affected cell: $affectedCell, certainty: $certainty");

    if (affectedChunk == null) {
      affectedChunk = _Chunk(quadrant);
      _map[quadrant] = affectedChunk;
    }

    affectedChunk.setCell(affectedCell, certainty);
  }

  Future<List<int>> _getSensorValues([Duration dur = const Duration(seconds: 3)]) async {
    _log.fine("Collecting sensor values with duration $dur");
    Completer<List<int>> dataCollected = Completer.sync();
    List<int> sensorValues = [];
    bool stop = false;

    Timer(dur, () {
      stop = true;
      _log.fine("Time's up!");

      dataCollected.complete(sensorValues);
    });

    Timer.periodic(const Duration(milliseconds: 100), (timer) {
      sensorValues.add(getSensorValue());

      if (stop) {
        timer.cancel();
      }
    });

    return await dataCollected.future;
  }

  double _sensorToCm(int sensorValue) {
    // Sensor max distance (100%) is equal to around 70 cm
    return sensorValue * 70 / 100;
  }

  double _baselineVal = -1;
  bool _calibrating = false;

  Future<double> _baseline([recalibrate = false]) async {
    Completer<double> dataCollected = Completer.sync();
    
    if (_baselineVal != -1 && !recalibrate) {
      return _baselineVal;
    }

    _calibrating = true;

    _log.fine("Calibrating sensor baseline...");

    List<int> sensorValues = await _getSensorValues();

    _log.fine("Sensor data collected: $sensorValues");

    _baselineVal = sensorValues.reduce((a, b) => a + b) / sensorValues.length;

    () async {
      dataCollected.complete(_baselineVal.clamp(0.1, 100.0));
      _calibrating = false;
    }();

    return dataCollected.future;
  }

  Future<double> _certainty(int sensorValue) async {
    double baseline = await _baseline();
    double certainty = (baseline - sensorValue) / baseline;

    return certainty.clamp(0.0, 1.0);
  }
}

class _Chunk {
  _Chunk(this.quadrant): 
    coordBound = Point<int>(quadrant.x * cellSize * chunkSize, quadrant.y * cellSize * chunkSize),
    cellBound = Point<int>(quadrant.x * chunkSize, quadrant.y * chunkSize);

  static const cellSize = 30; //Cell size is 30 cm
  static const chunkSize = 30;  //Chunk size is 30 cells
  //Generate immutable matrix of chunkSize x chunkSize cells
  final List<List<double>> mapRegion = 
    List<List<double>>.generate(
      chunkSize, 
      (index) => 
        List<double>.generate(
          chunkSize, 
          (index) => 0.0, 
          growable: false
        ),
      growable: false
    );
  final Point<int> quadrant;  //Quadrant of the chunk
  final Point<int> coordBound;  //Global coordinate of the top left corner of the chunk
  final Point<int> cellBound; //Global cell of the top left corner of the chunk
  
  static Point<T> coordAbs<T extends num>(Point<T> coord) {
    return Point(coord.x.abs() as T, coord.y.abs() as T);
  }

  Point<double> translate(Point<double> globalCoords) {
    Point<int> temp = coordAbs(coordBound);
    Point<double> quadrantCoord = Point(temp.x.toDouble(), temp.y.toDouble());
    Point<double> global = coordAbs(globalCoords);

    return coordAbs(global - quadrantCoord);
  }

  Point<int> translateCell(Point<int> globalCell) {
    Point<int> quadrantCell = coordAbs(cellBound);
    Point<int> global = coordAbs(globalCell);

    return coordAbs(global - quadrantCell);
  }

  void setCell(Point<int> affectedCellGlobal, double certainty) {
    Point<int> localCell = translateCell(affectedCellGlobal);

    if (localCell.x < 0 || localCell.x > chunkSize || localCell.y < 0 || localCell.y > chunkSize) {
      _log.warning("Cell is outside of chunk");
      return;
    }

    mapRegion[localCell.y][localCell.x] = certainty;
  }
}