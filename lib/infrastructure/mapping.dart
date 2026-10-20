import 'dart:collection';
import 'dart:math';
import 'dart:async';
import 'dart:ui';
import 'package:ev3_client/infrastructure/storage/serializable.dart';
import 'package:ev3_client/infrastructure/storage/utils.dart';
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

enum Commands { render, clear }

Completer<void> mapReady = Completer.sync();

class TerrainMap {
  TerrainMap({required this.getSensorValue, required this.getPosition})
      : _map = HashMap(),
        currentQuadrant = const Point(0, 0) {
    () async {
      _log.info("Mapping engine starting...");
      await _ensureChunks(currentQuadrant);
      if (!mapReady.isCompleted) {
        mapReady.complete();
      }
    }();
  }

  final HashMap<Point<int>, _Chunk> _map;
  Point<int> currentQuadrant;
  int Function() getSensorValue;
  (double x, double y, double angle) Function() getPosition;
  static const renderDistance = 1;
  static const mapSize = _Chunk.chunkSize * (2 * renderDistance + 1);
  static const timeBetweenUpdates = 20; // ms
  static const timeBetweenSaves = 30000; // ms

  static Future<Worker<Commands, img.Image>> startConcurrent() async {
    var worker = await Worker.getInstance<Commands, img.Image>(
      runnable: (sendPort, receivePort, workerState, store) async {
        Completer<void> dataCollected = Completer.sync();
        int count = 1;

        Timer.periodic(const Duration(seconds: 1), (timer) {
          var value = store["sensorValue"];
          _log.finer("Value: $value");

          if (value != null) {
            if (!dataCollected.isCompleted) {
              dataCollected.complete();
            }
            timer.cancel();
            return;
          }

          _log.finer("Waiting for sensor data... x$count");
          count++;
        });

        await dataCollected.future;

        final map = TerrainMap(
          getSensorValue: () {
            String? rawData = store["sensorValue"];
            if (rawData == null) return -1;

            List<String> data = rawData.split(';');
            for (String string in data) {
              List<String> value = string.split(':');
              if (value.length >= 2 && value[0] == 'ir') {
                return int.tryParse(value[1]) ?? -1;
              }
            }
            return -1;
          },
          getPosition: () {
            String? rawPos = store["position"];
            if (rawPos == null) {
              _log.warning("Position is null, returning default");
              var prev = store['previous_pos'];
              if (prev is (double, double, double)) return prev;
              return (0.0, 0.0, 0.0);
            }

            try {
              List<String> data = rawPos.split(';');
              var values = data.map((e) => double.parse(e)).toList();

              if (values.length >= 3) {
                final posTuple = (values[0], values[1], values[2]);
                store['previous_pos'] = posTuple;
                return posTuple;
              }
            } catch (e) {
              _log.warning("Error parsing position in worker: $e");
            }

            var prev = store['previous_pos'];
            if (prev is (double, double, double)) return prev;
            return (0.0, 0.0, 0.0);
          },
        );

        await mapReady.future;
        store['map'] = map;

        Timer.periodic(const Duration(milliseconds: timeBetweenUpdates), (timer) {
          map.update();
          if (workerState() == WorkerState.terminated) {
            timer.cancel();
          }
        });

        Timer.periodic(const Duration(milliseconds: timeBetweenSaves), (timer) {
          map.save();
          map._unloadChunks();
          _log.finer("Map saved");

          if (workerState() == WorkerState.terminated) {
            timer.cancel();
          }
        });
      },
      workerListener: (Commands data, store) async {
        const foreground = Color.fromARGB(255, 177, 104, 231);
        const background = Color.fromARGB(0, 0, 0, 0);
        final map = store['map'] as TerrainMap?;

        if (map == null) {
          return imaging.clearImage(mapSize, mapSize);
        }

        switch (data) {
          case Commands.render:
            return imaging.fromDoubleList(map.getCurrentMapData(), mapSize, mapSize, foreground, background);
          case Commands.clear:
            return imaging.clearImage(mapSize, mapSize);
        }
      },
      workerName: "Map",
    );

    socket.addSensorCallback((message) {
      worker.store(key: "sensorValue", value: message);
    });

    socket.addPositionCallback((x, y, angle) {
      worker.store(key: "position", value: "$x;$y;$angle");
    });

    return worker;
  }

  Future<void> _ensureChunks(Point<int> quadrant) async {
    for (int x = -renderDistance; x <= renderDistance; x++) {
      for (int y = -renderDistance; y <= renderDistance; y++) {
        Point<int> newQuadrant = Point(quadrant.x + x, quadrant.y + y);
        await _loadChunkOrCreate(newQuadrant);
      }
    }
  }

  Future<_Chunk> _loadChunkOrCreate(Point<int> quadrant) async {
    _Chunk newChunk;

    if (await _Chunk.isSaved(quadrant)) {
      newChunk = await _Chunk.load(quadrant);
      _log.finest("Chunk at $quadrant loaded");
    } else {
      newChunk = _Chunk(quadrant);
      _log.finest("Chunk file not found, created new chunk at $quadrant");
    }

    _map[quadrant] = newChunk;
    return newChunk;
  }

  void _unloadChunks() {
    for (_Chunk chunk in _outOfRange(currentQuadrant)) {
      _map.remove(chunk.quadrant);
      _log.finest("Unloaded chunk at ${chunk.quadrant}");
    }
  }

  List<_Chunk> _outOfRange(Point<int> position) {
    List<_Chunk> chunks = [];
    Set<Point<int>> inRange = {};

    for (int x = -renderDistance; x <= renderDistance; x++) {
      for (int y = -renderDistance; y <= renderDistance; y++) {
        inRange.add(Point(position.x + x, position.y + y));
      }
    }

    for (_Chunk chunk in _map.values) {
      if (!inRange.contains(chunk.quadrant)) {
        chunks.add(chunk);
      }
    }

    return chunks;
  }

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

  Point<int> getQuadrant(Point<int> cell) {
    return Point<int>(
      (cell.x / _Chunk.chunkSize).floor(),
      (cell.y / _Chunk.chunkSize).floor(),
    );
  }

  void update() async {
    if (_calibrating) return;

    final (x, y, angle) = getPosition();

    Point<double> position = Point(x + 15, y + 15);
    double lookAngle = angle;
    int sensorValue = getSensorValue();

    if (sensorValue < 0) return; // Si el sensor no devuelve valor válido, omitir

    double distance = _sensorToCm(sensorValue);

    Point<int> cellDistance = Point<int>(
      (distance * cos(deg2rad(lookAngle)) / _Chunk.cellSize).ceil(),
      (distance * sin(deg2rad(lookAngle)) / _Chunk.cellSize).ceil(),
    );

    Point<int> cellPosition = Point(position.x.floor(), position.y.floor());
    Point<int> affectedCell = cellPosition + cellDistance;

    currentQuadrant = getQuadrant(cellPosition);

    double certainty = await _certainty(sensorValue);

    Point<int> quadrant = getQuadrant(affectedCell);
    _Chunk? affectedChunk = _map[quadrant];

    affectedChunk ??= await _loadChunkOrCreate(quadrant);
    affectedChunk.setCell(affectedCell, certainty);
  }

  void save() {
    for (var chunk in _map.values) {
      chunk.save();
    }
  }

  Future<List<int>> _getSensorValues([Duration dur = const Duration(seconds: 3)]) async {
    _log.finer("Collecting sensor values with duration $dur");
    List<int> sensorValues = [];
    
    final stopwatch = Stopwatch()..start();
    while (stopwatch.elapsed < dur) {
      int val = getSensorValue();
      if (val >= 0) sensorValues.add(val);
      await Future.delayed(const Duration(milliseconds: 100));
    }

    return sensorValues.isEmpty ? [50] : sensorValues;
  }

  double _sensorToCm(int sensorValue) {
    return sensorValue * 70 / 100;
  }

  double _baselineVal = -1;
  bool _calibrating = false;

  Future<double> _baseline([bool recalibrate = false]) async {
    if (_baselineVal != -1 && !recalibrate) {
      return _baselineVal;
    }

    _calibrating = true;
    _log.fine("Calibrating sensor baseline...");

    List<int> sensorValues = await _getSensorValues();

    _baselineVal = sensorValues.reduce((a, b) => a + b) / sensorValues.length;
    _baselineVal = _baselineVal.clamp(0.1, 100.0);

    _calibrating = false;
    _log.fine("Calibration done!");

    return _baselineVal;
  }

  Future<double> _certainty(int sensorValue) async {
    double baseline = await _baseline();
    double certainty = (baseline - sensorValue) / baseline;

    return certainty.clamp(0.0, 1.0);
  }
}

class _Chunk extends Serializable<_Chunk> {
  _Chunk(this.quadrant)
      : coordBound = Point<int>(quadrant.x * cellSize * chunkSize, quadrant.y * cellSize * chunkSize),
        cellBound = Point<int>(quadrant.x * chunkSize, quadrant.y * chunkSize),
        mapRegion = List<List<double>>.generate(
          chunkSize,
          (_) => List<double>.filled(chunkSize, 0.0, growable: false),
          growable: false,
        );

  _Chunk._fromJson(this.quadrant, this.mapRegion)
      : coordBound = Point<int>(quadrant.x * cellSize * chunkSize, quadrant.y * cellSize * chunkSize),
        cellBound = Point<int>(quadrant.x * chunkSize, quadrant.y * chunkSize);

  static const cellSize = 30; // 30 cm
  static const chunkSize = 30; // 30 celdas
  final List<List<double>> mapRegion;

  final Point<int> quadrant;
  final Point<int> coordBound;
  final Point<int> cellBound;

  Point<int> translateCell(Point<int> globalCell) {
    return Point<int>(globalCell.x - cellBound.x, globalCell.y - cellBound.y);
  }

  void setCell(Point<int> affectedCellGlobal, double certainty) {
    Point<int> localCell = translateCell(affectedCellGlobal);

    // CORREGIDO: Evita Index Out of Bounds usándod >= chunkSize
    if (localCell.x < 0 || localCell.x >= chunkSize || localCell.y < 0 || localCell.y >= chunkSize) {
      _log.warning("Cell $localCell is outside of chunk range");
      return;
    }

    mapRegion[localCell.y][localCell.x] = certainty;
  }

  @override
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      "quadrant_x": quadrant.x,
      "quadrant_y": quadrant.y,
      "map_region": mapRegion,
    };
  }

  static Future<_Chunk> load(Point<int> quadrant) async {
    final json = await Serializable.loadData(quadrantFilename(quadrant));

    return _Chunk._fromJson(
      Point<int>(json["quadrant_x"] as int, json["quadrant_y"] as int),
      castMatrix<double>(json["map_region"]),
    );
  }

  static String quadrantFilename(Point<int> quadrant) => "chunk_${quadrant.x}_${quadrant.y}.json";

  @override
  String filename() => quadrantFilename(quadrant);

  static Future<bool> isSaved(Point<int> quadrant) => Serializable.fileExists(quadrantFilename(quadrant));
}