import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:logging/logging.dart';

final log = Logger("Gemini");

/// Acceso a Gemini (opcional). La clave y el modelo se pasan al compilar:
///
///   flutter run --dart-define=GOOGLE_API_KEY=tu_clave --dart-define=GEMINI_MODEL=gemini-3.5-flash-lite
///
/// Si no hay clave, la app usa solo el intérprete local (sin internet).
abstract class Gemini {
  static GenerativeModel? model;

  static const String apiKey = String.fromEnvironment("GOOGLE_API_KEY", defaultValue: '');

  /// gemini-2.5-flash ya no está disponible para claves nuevas; por eso el
  /// modelo es configurable. Ver https://ai.google.dev/gemini-api/docs/deprecations
  static const String modelName = String.fromEnvironment("GEMINI_MODEL", defaultValue: 'gemini-3.5-flash-lite');

  static const Duration timeout = Duration(seconds: 8);

  static bool get isConfigured => apiKey.isNotEmpty;

  static void initialize() {
    if (model != null) {
      return;
    }

    if (apiKey.isEmpty) {
      log.warning("GOOGLE_API_KEY no está definida: se usará solo el intérprete local");
      throw ArgumentError("API Key not set or empty!");
    }

    model = GenerativeModel(
      model: modelName,
      apiKey: apiKey,
      generationConfig: GenerationConfig(temperature: 0.1, maxOutputTokens: 200),
    );
  }

  static Future<String?> generate(String prompt) async {
    initialize();
    final response = await model!.generateContent([Content.text(prompt)]).timeout(timeout);
    return response.text;
  }
}
