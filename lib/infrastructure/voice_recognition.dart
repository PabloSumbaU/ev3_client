import 'dart:async';

import 'package:ev3_client/infrastructure/command_parser.dart';
import 'package:ev3_client/infrastructure/gemini.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';

final Logger _log = Logger("Voice recognition");

/// Reconocimiento de voz del teléfono (modo "tocar para hablar").
///
/// - Muestra el texto mientras la persona habla (resultados parciales).
/// - Se detiene solo cuando la persona deja de hablar (pauseFor).
/// - Elige automáticamente un idioma español disponible en el teléfono.
class VoiceService {
  VoiceService._();

  static final VoiceService instance = VoiceService._();

  final SpeechToText _stt = SpeechToText();
  bool _ready = false;
  String? _localeId;

  /// Nivel de sonido del micrófono (para animar el botón).
  final ValueNotifier<double> soundLevel = ValueNotifier(0);

  // Manejadores de la sesión de escucha actual
  void Function(String)? _onPartial;
  void Function(String)? _onFinal;
  void Function(String)? _onError;
  String _lastWords = "";
  bool _finished = true;

  bool get isListening => _stt.isListening || !_finished;

  /// Pide permiso de micrófono e inicializa el reconocimiento. Devuelve un
  /// mensaje de error o null si todo está bien.
  Future<String?> ensureReady() async {
    if (_ready) return null;

    var status = await Permission.microphone.status;
    if (!status.isGranted) {
      status = await Permission.microphone.request();
    }
    if (!status.isGranted) {
      return status.isPermanentlyDenied
          ? "Permiso de micrófono denegado. Actívalo en Ajustes > Apps."
          : "Se necesita permiso de micrófono.";
    }

    try {
      _ready = await _stt.initialize(onError: (e) => _handleError(e.errorMsg), onStatus: _handleStatus);
    } catch (e) {
      _log.severe("Error inicializando STT: $e");
      _ready = false;
    }
    if (!_ready) {
      return "El reconocimiento de voz no está disponible en este teléfono.";
    }

    _localeId = await _pickSpanishLocale();
    _log.info("Idioma de reconocimiento: $_localeId");
    return null;
  }

  /// Idioma forzado al compilar (opcional): --dart-define=STT_LOCALE=es_EC
  static const String _forcedLocale = String.fromEnvironment("STT_LOCALE", defaultValue: '');

  Future<String> _pickSpanishLocale() async {
    if (_forcedLocale.isNotEmpty) return _forcedLocale;
    // es_ES primero: es el que funcionaba en la versión original. Antes se
    // tomaba el idioma del sistema y en algunos teléfonos el reconocedor
    // terminaba escuchando en inglés ("address in centimeter").
    try {
      final locales = await _stt.locales();
      final ids = locales.map((l) => l.localeId).toList();
      _log.info("Idiomas de voz disponibles: ${ids.where((i) => i.toLowerCase().startsWith('es')).join(', ')}");
      const preferred = ['es_ES', 'es-ES', 'es_US', 'es-US', 'es_419', 'es-419', 'es_MX', 'es-MX', 'es_EC', 'es-EC'];
      for (final p in preferred) {
        if (ids.contains(p)) return p;
      }
      final anySpanish = ids.where((i) => i.toLowerCase().startsWith('es'));
      if (anySpanish.isNotEmpty) return anySpanish.first;
    } catch (e) {
      _log.warning("No se pudo obtener la lista de idiomas: $e");
    }
    return 'es_ES';
  }

  /// Empieza a escuchar. Se detiene solo tras ~2.5 s de silencio.
  Future<void> listen({
    required void Function(String words) onPartial,
    required void Function(String words) onFinal,
    required void Function(String message) onError,
  }) async {
    final error = await ensureReady();
    if (error != null) {
      onError(error);
      return;
    }
    if (_stt.isListening) {
      await _stt.cancel();
    }

    _onPartial = onPartial;
    _onFinal = onFinal;
    _onError = onError;
    _lastWords = "";
    _finished = false;

    try {
      await _listenInternal();
    } catch (e) {
      _log.severe("Error al iniciar la escucha: $e");
      _finished = true;
      onError("No se pudo iniciar el micrófono. Intenta de nuevo.");
    }
  }

  Future<void> _listenInternal() async {
    await _stt.listen(
      onResult: (result) {
        _lastWords = result.recognizedWords;
        if (result.finalResult) {
          _finish();
        } else {
          _onPartial?.call(_lastWords);
        }
      },
      onSoundLevelChange: (level) => soundLevel.value = level,
      listenOptions: SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
        listenMode: ListenMode.confirmation,
        localeId: _localeId,
        pauseFor: const Duration(milliseconds: 2500),
        listenFor: const Duration(seconds: 15),
      ),
    );
  }

  /// Termina de escuchar y procesa lo que se haya dicho hasta ahora.
  Future<void> stop() async {
    await _stt.stop();
    // Algunos teléfonos no envían el resultado final tras stop(): lo forzamos.
    Future.delayed(const Duration(milliseconds: 600), _finish);
  }

  /// Cierra la escucha a la fuerza (si el teléfono nunca avisa que terminó).
  Future<void> forceFinish() async {
    try {
      await _stt.stop();
    } catch (_) {}
    _finish();
  }

  Future<void> cancel() async {
    _finished = true;
    _onFinal = _onPartial = _onError = null;
    await _stt.cancel();
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    soundLevel.value = 0;
    final words = _lastWords.trim();
    if (words.isEmpty) {
      _onError?.call("No te escuché. Toca el micrófono e intenta de nuevo.");
    } else {
      _onFinal?.call(words);
    }
  }

  void _handleStatus(String status) {
    _log.fine("STT status: $status");
    if (status == SpeechToText.doneStatus || status == SpeechToText.notListeningStatus) {
      // dar un momento a que llegue el resultado final
      Future.delayed(const Duration(milliseconds: 400), _finish);
    }
  }

  void _handleError(String error) {
    _log.warning("STT error: $error");
    if (_finished) return;
    if (error == 'error_no_match' || error == 'error_speech_timeout') {
      if (_lastWords.trim().isNotEmpty) {
        _finish();
        return;
      }
      _finished = true;
      soundLevel.value = 0;
      _onError?.call(error == 'error_no_match'
          ? "No entendí lo que dijiste. Intenta de nuevo."
          : "No escuché nada. Toca el micrófono y habla.");
      return;
    }
    _finished = true;
    soundLevel.value = 0;
    final msg = switch (error) {
      'error_network' || 'error_network_timeout' => "Sin conexión para reconocer la voz.",
      'error_audio' => "Problema con el micrófono.",
      'error_busy' => "El reconocimiento de voz está ocupado, intenta de nuevo.",
      'error_permission' || 'error_insufficient_permissions' => "Falta el permiso de micrófono.",
      _ => "Error de reconocimiento ($error).",
    };
    _onError?.call(msg);
  }
}

// ---------------------------------------------------------------------------
// Interpretación de órdenes

class InterpretResult {
  const InterpretResult(this.command, this.source, {this.note});

  final ParsedCommand command;

  /// "IA" (Gemini) o "Local" (intérprete sin internet).
  final String source;

  /// Aviso opcional para mostrar (p. ej. "Gemini no respondió").
  final String? note;
}

const basePrompt = """
Eres el intérprete de órdenes de Lumi, un robot social con orugas y una garra que juega con niños.
Reescribe la orden del usuario como una lista de acciones separadas por coma, usando SOLO estas formas:
adelante N cm | adelante N metros | adelante N segundos | atrás N cm | atrás N metros | atrás N segundos |
izquierda N grados | derecha N grados | da la vuelta | media vuelta | agarra | suelta | para |
saluda | baila | respira | celebra | chiste | piedra papel tijera | duerme | despierta |
ponte feliz | ponte triste | ponte sorprendido | ponte enamorado | ponte pensando | ponte tranquilo |
di <texto corto y amable>
Reglas: si no se indica cantidad usa adelante 20 cm o izquierda/derecha 90 grados. "di" va siempre al final.
Si el usuario hace una pregunta o conversa, responde con "di" y una frase corta y amable para un niño.
Si la orden no tiene sentido, responde solo "?". No expliques nada.
Ejemplos:
"camina un poquito y luego gira a la izquierda" -> adelante 10 cm, izquierda 90 grados
"ve hacia atrás dos segundos y saluda" -> atrás 2 segundos, saluda
"estoy triste" -> ponte triste, di No te preocupes, aquí estoy contigo
Orden: """;

/// Convierte lo que dijo la persona en instrucciones para el robot.
///
/// Con [useAI] = true intenta primero con Gemini (más flexible); si falla o no
/// hay clave, usa el intérprete local. Con [useAI] = false usa solo el local.
Future<InterpretResult> interpretCommand(String spoken, {required bool useAI}) async {
  _log.fine("Orden: $spoken");

  // 1) Intérprete local: instantáneo y sin internet.
  final local = parseSpanishCommand(spoken);
  if (!local.isEmpty || !useAI || !Gemini.isConfigured) {
    return InterpretResult(local, "Local");
  }

  // 2) Si no entendió nada y la IA está activa, se le pide a Gemini que
  //    reescriba la orden con frases simples y se vuelve a interpretar.
  try {
    final text = (await Gemini.generate(basePrompt + spoken))?.trim() ?? '?';
    _log.fine("Gemini: $text");
    if (text != '?') {
      final parsed = parseSpanishCommand(text);
      if (!parsed.isEmpty) return InterpretResult(parsed, "IA");
    }
    return InterpretResult(local, "Local");
  } on TimeoutException {
    return InterpretResult(local, "Local", note: "La IA tardó demasiado");
  } catch (e) {
    _log.severe("Error con Gemini: $e");
    return InterpretResult(local, "Local", note: "La IA no respondió");
  }
}
