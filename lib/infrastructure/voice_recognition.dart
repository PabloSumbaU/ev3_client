import 'package:ev3_client/infrastructure/gemini.dart';
import 'package:logging/logging.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';

Logger _log = Logger("Voice recognition");

class VoiceRecognition {
  static SpeechToText? _stt;
  static bool _speechEnabled = false;

  // Se define la configuración de escucha incluyendo el idioma
  static final options = SpeechListenOptions(
    partialResults: false,
    cancelOnError: true,
    listenMode: ListenMode.dictation,
    localeId: "es_ES",
  );

  VoiceRecognition._();

  static Future<VoiceRecognition?> getInstance(void Function() onError) async {
    var status = await Permission.microphone.status;

    if (!status.isGranted) {
      _log.fine("Requesting microphone permission...");
      status = await Permission.microphone.request();
    }

    if (status.isPermanentlyDenied) {
      _log.warning("Microphone permission is permanently denied");
      onError();
      return null;
    }

    if (!status.isGranted) {
      _log.warning("Microphone permission not granted");
      onError();
      return null;
    }

    if (_stt == null || !_speechEnabled) {
      _log.fine("Initializing SpeechToText...");
      _stt = SpeechToText();
      _speechEnabled = await _stt!.initialize(
        onError: (errorNotification) => _log.severe("STT Error: $errorNotification"),
        onStatus: (status) => _log.fine("STT Status: $status"),
      );
    }

    if (_speechEnabled) {
      _log.fine("STT available, returning instance");
      return VoiceRecognition._();
    }

    _log.warning("STT unavailable");
    onError();
    return null;
  }

  String lastWords = "";

  Future<void> listen(Function(String) resultHandler) async {
    _log.fine("Listening started...");

    if (_stt!.isListening) {
      await _stt!.stop();
    }

    await _stt!.listen(
      onResult: (result) {
        _log.finest("Recognized: ${result.recognizedWords}");
        if (result.finalResult || result.recognizedWords.isNotEmpty) {
          resultHandler(result.recognizedWords);
        }
      },
      listenOptions: options,
    );
  }

  bool isListening() {
    return _stt?.isListening ?? false;
  }

  Future<void> stop() async {
    if (_stt != null && _stt!.isListening) {
      await _stt!.stop();
      _log.fine("Listening stopped");
    }
  }
}

List<String>? parseInput(String input) {
  final regex = RegExp(r'^([^:]+)(?::(\d+)?([a-zA-Z]+)?)?$');
  final match = regex.firstMatch(input);

  if (match != null) {
    String text = match.group(1)!;
    String? number = match.group(2);
    String? unit = match.group(3);

    final returnValue = [text];

    if (number != null) {
      returnValue.add(number);
    }

    if (unit != null) {
      returnValue.add(unit);
    }

    return returnValue;
  } else {
    return null;
  }
}

final instructionMap = {
  "adelante": "f",
  "atrás": "b",
  "atras": "b",
  "izquierda": "l",
  "derecha": "r",
  "agarrar": "p",
  "soltar": "d",
  "?": null,
};

String? _translateInstructions(String instructionString) {
  _log.finer("Instruction string: $instructionString");
  if (instructionString == '?') {
    return null;
  }

  final instructions = instructionString.split(";");

  final instructionList = instructions.map((e) {
    final instruction = parseInput(e.replaceAll(" ", "").toLowerCase());

    if (instruction == null) return null;

    return instruction.map((item) {
      if (instructionMap.containsKey(item)) {
        return instructionMap[item];
      }
      return item;
    }).join('-');
  }).whereType<String>().toList();

  _log.finer("Instruction set: $instructionList");

  return instructionList.isEmpty ? null : instructionList.join(';');
}

const basePrompt = 
    "Para la siguiente orden genera un conjunto de instrucciones. Las posibles son: "
    "adelante, atrás, izquierda, derecha, agarrar, soltar. Agrega la distancia o tiempo si es "
    "aplicable. (ejemplo de respuesta: adelante:3m; izquierda; atrás:20s). Procura "
    "que tu respuesta contenga únicamente el conjunto de instrucciones separadas por punto y coma, "
    "sin texto adicional ni explicaciones. Si la orden no tiene sentido, retorna únicamente '?'. Orden: ";

Future<String?> getInstructionSet(String voiceCommand) async {
  try {
    Gemini.initialize();
    _log.finer("Command: $voiceCommand");

    final response = await Gemini.generate(basePrompt + voiceCommand);
    final text = response.text?.trim() ?? '?';

    return _translateInstructions(text);
  } catch (e) {
    _log.severe("Error al comunicarse con Gemini o procesar: $e");
    return null;
  }
}