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