import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';

Future<Image> clearImage(int width, int height) {
  final c = Completer<Image>();
  decodeImageFromPixels(Uint8List(1), width, height, PixelFormat.rgba8888, c.complete);
  return c.future;
}

Future<Image> makeImage(int width, int height, Int32List pixels) {
  final c = Completer<Image>();

  decodeImageFromPixels(
    pixels.buffer.asUint8List(),
    width,
    height,
    PixelFormat.rgba8888,
    c.complete,
  );
  return c.future;
}

Int32List encode(List<Color> pixels) {
  final encodedPixels = Int32List(pixels.length);
  
  for (int i = 0; i < pixels.length; i++) {
    final red = pixels[i].red;
    final green = pixels[i].green;
    final blue = pixels[i].blue;
    final alpha = pixels[i].alpha;

    // Why. Just why. Why must you not offer ARGB8888 as a pixel format for image decodification when your Colors use it?
    encodedPixels[i] = (red << 24) | (green << 16) | (blue << 8) | alpha;
  }

  return encodedPixels;
}

/// Creates an image from a matrix of double values. Each value in the matrix represents the transparency (or alpha)
/// of the corresponding pixel in the image. The `foreground` argument is used to paint each pixel of the image, with its
/// transparency adjusted accordingly.
/// If the optional `background` argument is provided, it will be used as the background color of the image and the 
/// `foreground` color will be blended with it.
/// The values of `matrix` should be clamped between 0.0 and 1.0.
Future<Image> fromDoubleMatrix(List<List<double>> matrix, Color foreground, [Color? background]) {
  final width = matrix[0].length;
  final height = matrix.length;
  final pixels = <Color>[];

  for (var i = 0; i < matrix.length; i++) {
    for (var j = 0; j < matrix[i].length; j++) {
      final alpha = matrix[i][j];
      final foregroundPixel = Color.fromARGB((alpha * 255).truncate(), foreground.red, foreground.green, foreground.blue);

      if (background != null) {
        pixels.add(Color.alphaBlend(foregroundPixel, background));
      } else {
        pixels.add(foregroundPixel);
      }
    }
  }

  return makeImage(width, height, encode(pixels));
}

/// Creates an image from a list of double values. Each value in the list represents the transparency (or alpha)
/// of the corresponding pixel in the image. The `foreground` argument is used to paint each pixel of the image, with its
/// transparency adjusted accordingly.
/// If the optional `background` argument is provided, it will be used as the background color of the image and the 
/// `foreground` color will be blended with it.
/// The values of `list` should be clamped between 0.0 and 1.0.
Future<Image> fromDoubleList(List<double> list, int width, int height, Color foreground, [Color? background]) {
  final pixels = <Color>[];

  for (var i = 0; i < list.length; i++) {
    final alpha = list[i];
    final foregroundPixel = Color.fromARGB((alpha * 255).truncate(), foreground.red, foreground.green, foreground.blue);

    if (background != null) {
      pixels.add(Color.alphaBlend(foregroundPixel, background));
    } else {
      pixels.add(foregroundPixel);
    }
  }

  return makeImage(width, height, encode(pixels));
}
