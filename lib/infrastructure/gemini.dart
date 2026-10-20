import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:logging/logging.dart';

final log = Logger("Gemini");

abstract class Gemini {
  static GenerativeModel? model;

  static String _getAPIKey() {
    return const String.fromEnvironment("GOOGLE_API_KEY", defaultValue: '');
  }

  static void initialize() {
    if (model != null) {
      return;
    }

    final key = _getAPIKey();

    if (key.isEmpty) {
      log.severe("API Key env variable not set or empty!");
      throw ArgumentError("API Key not set or empty!");
    }

    model = GenerativeModel(model: "gemini-2.5-flash", apiKey: key);
  }

  static Future<GenerateContentResponse> generate(String prompt) async {
    if (model == null) {
      log.severe("Model has not been initialized");
      throw StateError("Model has not been initialized");
    } else {
      return model!.generateContent([Content.text(prompt)]);
    }
  }
}