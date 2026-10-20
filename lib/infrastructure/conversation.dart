import 'dart:convert';

import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:logging/logging.dart';

import 'gemini.dart';

final _log = Logger("Conversation");

/// Personalidad de Lumi para conversar con niños hospitalizados.
const systemPrompt = """
Eres Lumi, un pequeño robot social de LEGO, amigable y juguetón, que acompaña a niños y niñas
de 5 a 12 años que están en el hospital (muchos en tratamiento contra el cáncer).
Hablas español latinoamericano sencillo, cálido y alegre.

Reglas:
- Respuestas MUY cortas: máximo 2 frases y 25 palabras, porque las dice un parlante pequeño.
- Sé empático y paciente. Si el niño cuenta cómo se siente, valida su emoción con cariño.
- Nunca des consejos médicos, diagnósticos, dosis ni hables de pronósticos. Si pregunta por su
  enfermedad, medicinas o tratamientos, dile con cariño que eso lo puede preguntar a su doctor,
  enfermera o a sus papás.
- Si expresa miedo, dolor o tristeza fuerte, consuélalo y anímalo a contárselo a un adulto de confianza.
- No pidas datos personales (apellidos, dirección, teléfono, escuela).
- Puedes proponer juegos: chistes, adivinanzas, piedra papel o tijera, bailar o respirar juntos.
- No uses emojis, asteriscos ni símbolos: el robot leería todo en voz alta.
- Tú eres un robot: no comes ni duermes de verdad, pero puedes jugar a imaginar.

Responde SIEMPRE con un objeto JSON y nada más:
{"decir": "<lo que dirás>", "emocion": "<feliz|triste|sorprendido|amor|pensando|calma|neutral>",
 "accion": "<ninguna|saludar|bailar|respirar|celebrar|chiste|piedra_papel_tijera|dormir|despertar>"}
Usa "accion" solo cuando el niño lo pida o acepte (por ejemplo "¡sí, bailemos!").
Si eliges "chiste", en "decir" pon solo una introducción corta: el robot contará el chiste.
""";

/// Respuesta de Lumi ya interpretada.
class LumiReply {
  const LumiReply({required this.say, this.emotion = "feliz", this.action});

  final String say;
  final String emotion;

  /// Código del comportamiento para el robot (g, n, e, c, j, x, z, w) o null.
  final String? action;
}

const _actionCodes = {
  "saludar": "g",
  "bailar": "n",
  "respirar": "e",
  "celebrar": "c",
  "chiste": "j",
  "piedra_papel_tijera": "x",
  "piedra papel tijera": "x",
  "dormir": "z",
  "despertar": "w",
};

const _emotions = {"feliz", "triste", "sorprendido", "amor", "pensando", "calma", "neutral"};

/// Conversación con memoria (recuerda lo que se dijo antes en la sesión).
class RobotConversation {
  ChatSession? _chat;
  String? _chatModel;

  bool get available => Gemini.isConfigured;

  void reset() {
    _chat = null;
  }

  ChatSession _session(String model) {
    if (_chat == null || _chatModel != model) {
      final m = GenerativeModel(
        model: model,
        apiKey: Gemini.apiKey,
        systemInstruction: Content.system(systemPrompt),
        generationConfig: GenerationConfig(
          temperature: 0.8,
          maxOutputTokens: 300,
          responseMimeType: 'application/json',
        ),
      );
      _chat = m.startChat();
      _chatModel = model;
    }
    return _chat!;
  }

  Future<LumiReply> send(String childSays) async {
    final text = await Gemini.withModel((model) async {
      final response = await _session(model).sendMessage(Content.text(childSays)).timeout(Gemini.timeout);
      return response.text ?? "";
    });
    _log.fine("Gemini respondió: $text");
    return parseReply(text);
  }
}

/// Interpreta el JSON de Gemini. Si no viene JSON válido, usa el texto tal cual.
LumiReply parseReply(String raw) {
  var text = raw.trim();
  final start = text.indexOf('{');
  final end = text.lastIndexOf('}');
  if (start >= 0 && end > start) {
    try {
      final data = jsonDecode(text.substring(start, end + 1));
      if (data is Map) {
        final say = _clean("${data['decir'] ?? data['say'] ?? ''}");
        var emotion = "${data['emocion'] ?? 'feliz'}".toLowerCase().trim();
        if (!_emotions.contains(emotion)) emotion = "feliz";
        final actionName = "${data['accion'] ?? 'ninguna'}".toLowerCase().trim();
        return LumiReply(
          say: say.isEmpty ? "¡Qué interesante!" : say,
          emotion: emotion,
          action: _actionCodes[actionName],
        );
      }
    } catch (_) {}
  }
  return LumiReply(say: _clean(text).isEmpty ? "Perdón, no te entendí. ¿Me lo repites?" : _clean(text));
}

String _clean(String s) => s
    .replaceAll(RegExp(r'[*_#`|;]'), ' ')
    .replaceAll(RegExp(r'[\u{1F000}-\u{1FFFF}\u{2600}-\u{27BF}]', unicode: true), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();
