import 'dart:ui' as ui;

import 'package:logging/logging.dart';
import 'package:image/image.dart' as img;

final _log = Logger("Image");

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
    pixel.a = pixels[i].alpha;
    pixel.r = pixels[i].red;
    pixel.g = pixels[i].green;
    pixel.b = pixels[i].blue;
    i++;
  }

  return image;
}

/// Creates an image from a matrix of double values. Each value in the matrix represents the transparency (or alpha)
/// of the corresponding pixel in the image. The `foreground` argument is used to paint each pixel of the image, with its
/// transparency adjusted accordingly.
/// If the optional `background` argument is provided, it will be used as the background color of the image and the 
/// `foreground` color will be blended with it.
/// The values of `matrix` should be clamped between 0.0 and 1.0.
img.Image fromDoubleMatrix(List<List<double>> matrix, ui.Color foreground, [ui.Color? background]) {
  final width = matrix[0].length;
  final height = matrix.length;
  final pixels = <ui.Color>[];

  for (var i = 0; i < matrix.length; i++) {
    for (var j = 0; j < matrix[i].length; j++) {
      final alpha = matrix[i][j];
      final foregroundPixel = ui.Color.fromARGB((alpha * 255).truncate(), foreground.red, foreground.green, foreground.blue);

      if (background != null) {
        pixels.add(ui.Color.alphaBlend(foregroundPixel, background));
      } else {
        pixels.add(foregroundPixel);
      }
    }
  }

  return makeImage(width, height, pixels);
}

/// Creates an image from a list of double values. Each value in the list represents the transparency (or alpha)
/// of the corresponding pixel in the image. The `foreground` argument is used to paint each pixel of the image, with its
/// transparency adjusted accordingly.
/// If the optional `background` argument is provided, it will be used as the background color of the image and the 
/// `foreground` color will be blended with it.
/// The values of `list` should be clamped between 0.0 and 1.0.
img.Image fromDoubleList(List<double> list, int width, int height, ui.Color foreground, [ui.Color? background]) {
  final pixels = <ui.Color>[];

  for (var i = 0; i < list.length; i++) {
    final alpha = list[i];

    final foregroundPixel = ui.Color.fromARGB((alpha * 255).truncate(), foreground.red, foreground.green, foreground.blue);

    if (background != null) {
      pixels.add(ui.Color.alphaBlend(foregroundPixel, background));
    } else {
      pixels.add(foregroundPixel);
    }
  }

  return makeImage(width, height, pixels);
}
