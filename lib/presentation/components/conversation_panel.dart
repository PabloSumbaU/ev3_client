import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart';

import '../../infrastructure/conversation.dart';
import '../../infrastructure/socket_connection.dart';
import '../../infrastructure/voice_recognition.dart';
import '../robot_state.dart';

class _Message {
  const _Message(this.fromChild, this.text, {this.emotion, this.action});

  final bool fromChild;
  final String text;
  final String? emotion;
  final String? action;
}

const _actionNames = {
  "g": "Saludar", "n": "Bailar", "e": "Respirar", "c": "Celebrar",
  "j": "Chiste", "x": "Piedra, papel o tijera", "z": "Dormir", "w": "Despertar",
};

const _emotionToStatus = {
  "feliz": "feliz", "triste": "triste", "sorprendido": "sorprendido", "amor": "carinoso",
  "pensando": "pensando", "calma": "tranquilo", "neutral": "neutral",
};

/// Conversación libre con el robot usando Gemini.
///
/// El niño habla (o se escribe) -> Gemini responde como "Lumi" -> el robot lo
/// dice en voz alta, pone la cara de la emoción y, si corresponde, hace una
/// acción (bailar, chiste...). La conversación tiene memoria.
class ConversationPanel extends StatefulWidget {
  const ConversationPanel({super.key});

  @override
  State<ConversationPanel> createState() => _ConversationPanelState();
}

class _ConversationPanelState extends State<ConversationPanel> with AutomaticKeepAliveClientMixin {
  static final RobotConversation _conversation = RobotConversation();
  static final List<_Message> _messages = [];

  final _controller = TextEditingController();
  final _scroll = ScrollController();
  bool _listening = false;
  bool _thinking = false;
  String _partial = "";
  String? _error;
  Timer? _watchdog;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _watchdog?.cancel();
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _vibrate() async {
    if (await Vibration.hasVibrator()) Vibration.vibrate(duration: 30);
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _toggleMic() async {
    final voice = VoiceService.instance;
    if (_thinking) return;
    _vibrate();
    if (_listening) {
      await voice.stop();
      Timer(const Duration(seconds: 2), () {
        if (_listening) voice.forceFinish();
      });
      return;
    }
    setState(() {
      _listening = true;
      _partial = "";
      _error = null;
    });
    _watchdog?.cancel();
    _watchdog = Timer(const Duration(seconds: 17), () {
      if (_listening) voice.forceFinish();
    });
    await voice.listen(
      onPartial: (w) {
        if (mounted) setState(() => _partial = w);
      },
      onFinal: (w) {
        if (!mounted) return;
        setState(() {
          _listening = false;
          _partial = "";
        });
        _send(w);
      },
      onError: (msg) {
        if (mounted) {
          setState(() {
            _listening = false;
            _partial = "";
            _error = msg;
          });
        }
      },
    );
  }

  Future<void> _send(String text) async {
    final t = text.trim();
    if (t.isEmpty || _thinking) return;
    setState(() {
      _messages.add(_Message(true, t));
      _thinking = true;
      _error = null;
    });
    _controller.clear();
    _scrollToEnd();
    sendInstructions("m-pensando"); // el robot "piensa" mientras espera

    try {
      final reply = await _conversation.send(t);
      if (!mounted) return;
      // 1) cara  2) voz  3) acción (el robot las encadena en orden)
      sendInstructions("m-${reply.emotion}");
      sendSpeech(reply.say);
      if (reply.action != null) {
        // pequeña pausa para que la acción empiece después de la frase
        Future.delayed(const Duration(milliseconds: 300), () => sendInstructions(reply.action!));
      }
      RobotState.status.value = RobotStatus(
        proximity: RobotState.status.value.proximity,
        emotion: _emotionToStatus[reply.emotion] ?? "feliz",
        action: RobotState.status.value.action,
      );
      setState(() {
        _messages.add(_Message(false, reply.say, emotion: reply.emotion, action: reply.action));
        _thinking = false;
      });
    } catch (e) {
      sendInstructions("m-neutral");
      if (!mounted) return;
      setState(() {
        _thinking = false;
        _error = "No pude conectarme con la IA. Revisa el internet del teléfono.";
      });
    }
    _scrollToEnd();
  }

  void _reset() {
    _conversation.reset();
    setState(() {
      _messages.clear();
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final scheme = Theme.of(context).colorScheme;

    if (!_conversation.available) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            "Para conversar con el robot se necesita la clave de Gemini.\n"
            "Agrégala en launch.json con --dart-define=GOOGLE_API_KEY=... (ver CAMBIOS.md).",
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      child: Column(
        children: [
          Expanded(
            child: _messages.isEmpty && !_thinking
                ? Center(
                    child: Text(
                      "Toca el micrófono y habla con Lumi.\nPrueba: \"Hola, ¿cómo te llamas?\"",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  )
                : ListView(
                    controller: _scroll,
                    children: [
                      for (final m in _messages) _Bubble(message: m),
                      if (_thinking)
                        const _Bubble(message: _Message(false, "Lumi está pensando...")),
                    ],
                  ),
          ),
          if (_listening || _error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                _listening ? (_partial.isEmpty ? "Te escucho..." : "“$_partial”") : _error!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: _listening ? scheme.primary : scheme.error, fontSize: 12),
              ),
            ),
          Row(
            children: [
              IconButton(
                tooltip: "Nueva conversación",
                visualDensity: VisualDensity.compact,
                onPressed: _thinking ? null : _reset,
                icon: const Icon(Icons.restart_alt_rounded),
              ),
              Expanded(
                child: TextField(
                  controller: _controller,
                  enabled: !_thinking,
                  textInputAction: TextInputAction.send,
                  onSubmitted: _send,
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: "Escribe o habla con Lumi",
                    border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filled(
                tooltip: "Hablar con Lumi",
                style: IconButton.styleFrom(backgroundColor: _listening ? scheme.error : null),
                onPressed: _thinking ? null : _toggleMic,
                icon: Icon(_listening ? Icons.stop_rounded : Icons.mic_rounded),
              ),
              const SizedBox(width: 4),
              IconButton.filledTonal(
                tooltip: "Enviar",
                onPressed: _thinking ? null : () => _send(_controller.text),
                icon: const Icon(Icons.send_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final _Message message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final child = message.fromChild;
    final emoji = child ? "🧒" : (emotionEmoji[_emotionToStatus[message.emotion] ?? "feliz"] ?? "🤖");
    return Align(
      alignment: child ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: child ? scheme.primaryContainer : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(14),
              topRight: const Radius.circular(14),
              bottomLeft: Radius.circular(child ? 14 : 3),
              bottomRight: Radius.circular(child ? 3 : 14),
            ),
          ),
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: "$emoji  "),
              TextSpan(text: message.text),
              if (message.action != null)
                TextSpan(
                  text: "   ▶ ${_actionNames[message.action] ?? ''}",
                  style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w600, fontSize: 12),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
