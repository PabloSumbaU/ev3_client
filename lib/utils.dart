import 'dart:math';

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