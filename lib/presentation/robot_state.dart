import 'package:flutter/material.dart';

import '../infrastructure/command_parser.dart';
import '../infrastructure/gemini.dart';

/// Estado que el robot reporta por el socket de sensores:
/// "ir:<0-100>;st:<emoción>;ac:<acción actual>"
class RobotStatus {
  const RobotStatus({this.proximity, this.emotion = "neutral", this.action = ""});

  final int? proximity;
  final String emotion;
  final String action;

  static RobotStatus parse(String message) {
    int? proximity;
    var emotion = "neutral";
    var action = "";
    for (final part in message.split(";")) {
      final kv = part.split(":");
      if (kv.length < 2) continue;
      switch (kv[0]) {
        case "ir":
          proximity = int.tryParse(kv[1]);
        case "st":
          emotion = kv[1];
        case "ac":
          action = kv[1] == "-" ? "" : kv[1];
      }
    }
    return RobotStatus(proximity: proximity, emotion: emotion, action: action);
  }
}

/// Estado compartido de la pantalla de control.
class RobotState {
  static final ValueNotifier<RobotStatus> status = ValueNotifier(const RobotStatus());
  static final ValueNotifier<bool> clawClosed = ValueNotifier(false);

  /// Usar Gemini para interpretar la voz (si hay clave configurada).
  static final ValueNotifier<bool> useAI = ValueNotifier(Gemini.isConfigured);

  static void reset() {
    status.value = const RobotStatus();
    clawClosed.value = false;
  }
}

const emotionEmoji = {
  "neutral": "🙂", "feliz": "😊", "triste": "😢", "sorprendido": "😮",
  "carinoso": "😍", "pensando": "🤔", "dormido": "😴", "tranquilo": "😌",
  "alerta": "😟",
};

const actionLabels = {
  "saludar": "Saludando", "bailar": "Bailando", "respirar": "Respirando",
  "celebrar": "Celebrando", "chiste": "Contando un chiste",
  "piedra papel o tijera": "Jugando", "dormir": "Durmiendo", "despertar": "Despertando",
  "moverse": "Moviéndose", "hablar": "Hablando", "secuencia": "Ejecutando órdenes",
  "saludo automatico": "Saludando",
};

IconData iconForStep(RobotStep step) {
  final letter = step.code.split('-').first;
  switch (letter) {
    case 'f':
      return Icons.arrow_upward_rounded;
    case 'b':
      return Icons.arrow_downward_rounded;
    case 'l':
      return Icons.turn_left_rounded;
    case 'r':
      return Icons.turn_right_rounded;
    case 't':
      return Icons.rotate_right_rounded;
    case 'p':
      return Icons.back_hand_rounded;
    case 'd':
      return Icons.front_hand_outlined;
    case 's':
      return Icons.stop_circle_rounded;
    case 'm':
      return Icons.emoji_emotions_rounded;
    case 'h':
      return Icons.record_voice_over_rounded;
    default:
      return Icons.auto_awesome_rounded;
  }
}
