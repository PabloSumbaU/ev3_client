import 'dart:math';
import 'package:logging/logging.dart';

String normalizeStringLen(double value, int length, [samePrecision = true]) {
  var intDigits = value.abs().truncate().toString().length + 1;
  
  if (value < 0) {
    return value.toStringAsFixed(length - intDigits - 1);
  }

  if (samePrecision) {
    return "${value.toStringAsFixed(length - intDigits - 1)}0";
  }

  return value.toStringAsFixed(length - intDigits);
}

double rad2deg(num radians) {
  return radians * 180 / pi;
}

double deg2rad(num degrees) {
  return degrees * pi / 180;
}

void initializeLogger([worker = "MAIN"]) {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    String color = "";
    const String reset = "\x1B[0m";
    const String workerColor = "\x1B[1;95m";
    const String nameColor = "\x1B[1;92m";
    
    switch (record.level) {
      case Level.FINEST:
        color = "\x1B[37m";
        break;

      case Level.FINER:
        color = "\x1B[36m";
        break;
      
      case Level.FINE:
        color = "\x1B[32m";
        break;
      
      case Level.SEVERE:
        color = "\x1B[31m";
        break;

      case Level.WARNING:
        color = "\x1B[33m";
        break;
      default:
        color = "";
    }

    //ignore: avoid_print
    print('$workerColor[WORKER/$worker]$nameColor[${record.loggerName}] $color${record.level.name}: ${record.time}: ${record.message}$reset');
  });
}