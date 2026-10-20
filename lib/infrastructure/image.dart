import 'dart:ui' as ui;
import 'package:image/image.dart' as img;

// Se eliminó '_log' no utilizado

img.Image clearImage(int width, int height) {
  final image = img.Image(width: width, height: height);

  for (var pixel in image) {
    pixel.a = 0;
    pixel.r = 0;
    pixel.g = 0;
    pixel.b = 0;
  }

  return image;
}

img.Image makeImage(int width, int height, List<ui.Color> pixels) {
  final image = img.Image(width: width, height: height, numChannels: 4);
  int i = 0;

  for (var pixel in image) {
    // Uso moderno de los canales multiplicados por 255
    pixel.a = (pixels[i].a * 255).round().clamp(0, 255);
    pixel.r = (pixels[i].r * 255).round().clamp(0, 255);
    pixel.g = (pixels[i].g * 255).round().clamp(0, 255);
    pixel.b = (pixels[i].b * 255).round().clamp(0, 255);
    i++;
  }

  return image;
}

/// Creates an image from a matrix of double values.
img.Image fromDoubleMatrix(List<List<double>> matrix, ui.Color foreground, [ui.Color? background]) {
  final width = matrix[0].length;
  final height = matrix.length;
  final pixels = <ui.Color>[];

  final fR = (foreground.r * 255).round().clamp(0, 255);
  final fG = (foreground.g * 255).round().clamp(0, 255);
  final fB = (foreground.b * 255).round().clamp(0, 255);

  for (var i = 0; i < matrix.length; i++) {
    for (var j = 0; j < matrix[i].length; j++) {
      final alpha = matrix[i][j];
      final foregroundPixel = ui.Color.fromARGB((alpha * 255).truncate(), fR, fG, fB);

      if (background != null) {
        pixels.add(ui.Color.alphaBlend(foregroundPixel, background));
      } else {
        pixels.add(foregroundPixel);
      }
    }
  }

  return makeImage(width, height, pixels);
}

/// Creates an image from a list of double values.
img.Image fromDoubleList(List<double> list, int width, int height, ui.Color foreground, [ui.Color? background]) {
  final pixels = <ui.Color>[];

  final fR = (foreground.r * 255).round().clamp(0, 255);
  final fG = (foreground.g * 255).round().clamp(0, 255);
  final fB = (foreground.b * 255).round().clamp(0, 255);

  for (var i = 0; i < list.length; i++) {
    final alpha = list[i];
    final foregroundPixel = ui.Color.fromARGB((alpha * 255).truncate(), fR, fG, fB);

    if (background != null && background.a > 0) {
      pixels.add(ui.Color.alphaBlend(foregroundPixel, background));
    } else {
      pixels.add(foregroundPixel);
    }
  }

  return makeImage(width, height, pixels);
}