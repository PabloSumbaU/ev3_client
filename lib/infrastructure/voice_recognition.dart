import 'package:ev3_client/infrastructure/gemini.dart';
import 'package:logging/logging.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';

Logger log = Logger("Voice recognition");

class VoiceRecognition {
  static SpeechToText? _stt;
  static bool _speechEnabled = false;
  static final options = SpeechListenOptions(partialResults: false);

  VoiceRecognition._();

  static Future<VoiceRecognition?> getInstance(void Function() onError) async {
    if (! await Permission.microphone.isGranted) {
      if (await Permission.microphone.isPermanentlyDenied) {
        log.warning("Microphone permission is permanently denied");
      } else {
        log.fine("Requesting microphone permission...");
        await Permission.microphone.request();
      }
    }

    if (_stt == null) {
      log.fine("Instance requested");
      _stt = SpeechToText();
      _speechEnabled = await _stt!.initialize();
      log.fine("STT initialized");
    }

    if (_speechEnabled) {
      log.fine("STT available, returning instance");
      return VoiceRecognition._();
    }

    log.warning("STT unavailable");
    onError();
    return null;
  }

  String lastWords = "";

  Future<void> listen(Function(String) resultHandler) async {
    log.fine("Listening started...");

    await _stt!.listen(onResult: (result) {
      log.finest("Recognized: ${result.recognizedWords}");
      resultHandler(result.recognizedWords);
    }, listenOptions: options);
  }

  bool isListening() {
    return _stt!.isListening;
  }

  Future<void> stop() async {
    await _stt!.stop();
    log.fine("Listening stopped");
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
  "adelante": "f",  //forward
  "atrás": "b",     //backward
  "izquierda": "l", //left
  "derecha": "r",   //right
  "agarrar": "p",   //pick up
  "soltar": "d"  ,  //drop
  "?": null,        //invalid
};

String? _translateInstructions(String instructionString) {
  log.finer("Instruction string: $instructionString");
  if (instructionString == '?') {
    return null;
  }

  final instructions = instructionString.split(";");

  final instructionList = instructions.map((e) {
    final instruction = parseInput(e.replaceAll(" ", ""));

    return instruction!.map((e) { 
      if (instructionMap.containsKey(e)) {
        return instructionMap[e];
      }

      return e;
    }).join('-');
  }).toList();

  log.finer("Instruction set: $instructionList");

  return instructionList.join(';');
}

const basePrompt = 
"Para la siguiente orden genera un conjunto de instrucciones. Las posibles son: "
"adelante, atrás, izquierda, derecha, agarrar, soltar. Agrega la distancia si es "
"aplicable. (ejemplo de respuesta: adelante:3m; izquierda; atrás:20s). Procura "
"que tu respuesta contenga únicamente el conjunto de instrucciones y no asumas"
"nada más allá de lo ordenado. Si la orden no tiene sentido, retorna '?'. Orden: ";

Future<String?> getInstructionSet(String voiceCommand) async {
  Gemini.initialize();
  log.finer("Command: $voiceCommand");
  return _translateInstructions((await Gemini.generate(basePrompt + voiceCommand)).text!.trim());
}