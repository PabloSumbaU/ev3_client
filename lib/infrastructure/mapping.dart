import 'dart:math';
import 'dart:async';
import 'package:ev3_client/utils.dart';
import 'socket_connection.dart';

bool _sensorListener = false;
bool _registerValues = false;
List<int> _sensorValues = [];

void _ensureListener() {
  if (_sensorListener) {
    return;
  }

  sensorListen((sensorData) {
    if (_registerValues) {
      List<String> data = sensorData.split(';');
      for (String string in data) {
        List<String> value = string.split(':');

        if (value[0] != 'ir') {
          continue;
        }

        _sensorValues.add(int.parse(value[1]));
      }
    }
  });

  _sensorListener = true;
}

Future<List<int>> _getSensorValues([Duration dur = const Duration(seconds: 3)]) async {
  _ensureListener();
  
  _registerValues = true;

  Timer(dur, () {
    _registerValues = false;
  });

  return Future.delayed(dur, () => _sensorValues);
}

double _sensorToCm(int sensorValue) {
  // Sensor max distance (100%) is equal to around 70 cm
  return sensorValue * 70 / 100;
}

double _baselineVal = -1;

Future<double> _baseline([recalibrate = false]) async {
  if (_baselineVal != -1 && !recalibrate) {
    return _baselineVal;
  }

  List<int> sensorValues = await _getSensorValues();

  _baselineVal = sensorValues.reduce((a, b) => a + b) / sensorValues.length;
  return _baselineVal.clamp(0.1, 100.0);
}

Future<double> _certainty(int sensorValue) async {
  double baseline = await _baseline();
  double certainty = (baseline - sensorValue) / baseline;

  return certainty.clamp(0.0, 1.0);
}

enum Direction {
  up, down, left, right
}

class Map {
  // Robot is around 30 cm in length (27 to be more precise)
  static const cellSize = 30;

  Map(): map = [[0.0]], origin = const Point(0, 0);

  List<List<double>> map;
  Point<int> origin;


  void expand(Direction direction) {
    switch (direction) {
      case Direction.up:
        map.insert(0, List<double>.filled(map[0].length, 0.0));
        origin = Point(origin.x, origin.y + 1);
        break;
      case Direction.down:
        map.add(List<double>.filled(map[0].length, 0.0));
        break;
      case Direction.left:
        for (int i = 0; i < map.length; i++) {
          map[i].insert(0, 0.0);
        }
        origin = Point(origin.x + 1, origin.y);
        break;
      case Direction.right:
        for (int i = 0; i < map.length; i++) {
          map[i].add(0.0);
        }
        break;
    }
  }

  void setCell(Point<int> position, double lookAngle, int sensorValue) async {
    double distance = _sensorToCm(sensorValue);
    
    double xDistanceInCells = distance * cos(deg2rad(lookAngle)) / cellSize;
    double yDistanceInCells = distance * sin(deg2rad(lookAngle)) / cellSize;

    int x = position.x + xDistanceInCells.ceil();
    int y = position.y + yDistanceInCells.ceil();

    int leftBound = -origin.x;
    int rightBound = leftBound + map[0].length;
    int topBound = -origin.y;
    int bottomBound = topBound + map.length;

    //Always account for one extra cell when expanding
    if (x < leftBound) {
      int delta = leftBound - x;

      for (int i = 0; i < delta + 1; i++) {
        expand(Direction.left);
      }
    } else if (x > rightBound) {
      int delta = x - rightBound;

      for (int i = 0; i < delta + 1; i++) {
        expand(Direction.right);
      }
    }

    if (y < topBound) {
      int delta = topBound - y;

      for (int i = 0; i < delta + 1; i++) {
        expand(Direction.up);
      }
    } else if (y > bottomBound) {
      int delta = y - bottomBound;

      for (int i = 0; i < delta + 1; i++) {
        expand(Direction.down);
      }
    }
    
    map[origin.y + y][origin.x + x] = await _certainty(sensorValue);
  }
}