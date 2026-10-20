import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:logging/logging.dart';

final log = Logger("Gemini");

/// Acceso a Gemini (opcional). La clave y el modelo se pasan al compilar:
///
///   flutter run --dart-define=GOOGLE_API_KEY=tu_clave --dart-define=GEMINI_MODEL=gemini-3.5-flash-lite
///
/// Si no hay clave, la app usa solo el intérprete local (sin internet) y el
/// modo "Conversar" no está disponible.
abstract class Gemini {
  static const String apiKey = String.fromEnvironment("GOOGLE_API_KEY", defaultValue: '');

  /// gemini-2.5-flash ya no está disponible para claves nuevas; por eso el
  /// modelo es configurable. Ver https://ai.google.dev/gemini-api/docs/deprecations
  static const String modelName = String.fromEnvironment("GEMINI_MODEL", defaultValue: 'gemini-3.5-flash-lite');

  /// Si el modelo elegido no existe para esta clave, se prueban estos en orden.
  static final List<String> candidateModels = [
    modelName,
    'gemini-3.5-flash-lite',
    'gemini-3.6-flash',
    'gemini-3.8-flash',
    'gemini-2.5-flash',
  ].toSet().toList();

  static const Duration timeout = Duration(seconds: 10);

  static bool get isConfigured => apiKey.isNotEmpty;

  /// Modelo que respondió bien la última vez (se reutiliza).
  static String? workingModel;

  static String get currentModel => workingModel ?? modelName;

  static bool _isModelMissing(Object e) {
    final msg = e.toString().toLowerCase();
    return msg.contains('not found') || msg.contains('404') || msg.contains('is not supported') ||
        msg.contains('no longer available');
  }

  /// Ejecuta [action] con el primer modelo disponible.
  static Future<T> withModel<T>(Future<T> Function(String model) action) async {
    if (!isConfigured) throw StateError("GOOGLE_API_KEY no configurada");
    final order = workingModel != null ? [workingModel!, ...candidateModels.where((m) => m != workingModel)] : candidateModels;
    Object? lastError;
    for (final model in order) {
      try {
        final result = await action(model);
        if (workingModel != model) log.info("Usando modelo $model");
        workingModel = model;
        return result;
      } catch (e) {
        lastError = e;
        if (!_isModelMissing(e)) rethrow;
        log.warning("Modelo $model no disponible, probando otro: $e");
      }
    }
    throw lastError ?? StateError("Ningún modelo disponible");
  }

  /// Una petición simple (se usa para interpretar órdenes).
  static Future<String?> generate(String prompt) {
    return withModel((model) async {
      final m = GenerativeModel(
        model: model,
        apiKey: apiKey,
        generationConfig: GenerationConfig(temperature: 0.1, maxOutputTokens: 200),
      );
      final response = await m.generateContent([Content.text(prompt)]).timeout(timeout);
      return response.text;
    });
  }
}
