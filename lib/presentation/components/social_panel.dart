import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart';

import '../../infrastructure/socket_connection.dart';
import '../../infrastructure/voice_recognition.dart';
import '../robot_state.dart';
import 'conversation_panel.dart';

void _tap() async {
  if (await Vibration.hasVibrator()) Vibration.vibrate(duration: 30);
}

class _Action {
  const _Action(this.code, this.emoji, this.label, this.serverName);

  final String code;
  final String emoji;
  final String label;

  /// Nombre que reporta el robot mientras ejecuta la acción.
  final String serverName;
}

const _actions = [
  _Action("g", "👋", "Saludar", "saludar"),
  _Action("n", "💃", "Bailar", "bailar"),
  _Action("e", "🌬️", "Respirar", "respirar"),
  _Action("c", "🎉", "Celebrar", "celebrar"),
  _Action("j", "😂", "Chiste", "chiste"),
  _Action("x", "✊", "Piedra, papel\no tijera", "piedra papel o tijera"),
  _Action("z", "😴", "Dormir", "dormir"),
  _Action("w", "⏰", "Despertar", "despertar"),
];

const _emotions = [
  ("feliz", "😊", "Feliz"),
  ("triste", "😢", "Triste"),
  ("sorprendido", "😮", "Sorpresa"),
  ("amor", "😍", "Cariño"),
  ("pensando", "🤔", "Pensando"),
  ("calma", "😌", "Calma"),
];

const _phrases = [
  "¡Hola! ¿Cómo te llamas?",
  "¿Cómo te sientes hoy?",
  "¡Muy bien! Eres muy valiente.",
  "¿Quieres jugar conmigo?",
  "Estoy aquí contigo.",
  "¡Lo estás haciendo genial!",
  "¿Cuál es tu color favorito?",
  "¡Gracias por jugar conmigo!",
  "Ya casi terminamos.",
  "¡Hasta pronto!",
];

/// Panel derecho: acciones sociales, emociones y "hacer hablar" al robot.
class SocialPanel extends StatelessWidget {
  const SocialPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return const DefaultTabController(
      length: 3,
      child: Column(
        children: [
          TabBar(
            labelPadding: EdgeInsets.zero,
            tabs: [
              Tab(height: 36, text: "Acciones"),
              Tab(height: 36, text: "Hablar"),
              Tab(height: 36, text: "Conversar (IA)"),
            ],
          ),
          Expanded(
            child: TabBarView(children: [_ActionsTab(), _SpeakTab(), ConversationPanel()]),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Acciones
class _ActionsTab extends StatelessWidget {
  const _ActionsTab();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<RobotStatus>(
      valueListenable: RobotState.status,
      builder: (context, status, _) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: Column(
            children: [
              Expanded(
                child: LayoutBuilder(builder: (context, c) {
                  const cols = 4;
                  final rows = (_actions.length / cols).ceil();
                  final ratio = (c.maxWidth / cols) / (c.maxHeight / rows);
                  return GridView.count(
                    crossAxisCount: cols,
                    childAspectRatio: ratio,
                    mainAxisSpacing: 6,
                    crossAxisSpacing: 6,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      for (final a in _actions)
                        _ActionTile(action: a, running: status.action == a.serverName),
                    ],
                  );
                }),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 34,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final e in _emotions)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ActionChip(
                          visualDensity: VisualDensity.compact,
                          avatar: Text(e.$2),
                          label: Text(e.$3),
                          onPressed: () {
                            _tap();
                            sendInstructions("m-${e.$1}");
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.action, required this.running});

  final _Action action;
  final bool running;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: running ? scheme.primary : scheme.primaryContainer,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          _tap();
          sendInstructions(action.code);
        },
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(action.emoji, style: const TextStyle(fontSize: 26)),
                Text(
                  action.label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    height: 1.1,
                    color: running ? scheme.onPrimary : scheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Hablar
class _SpeakTab extends StatefulWidget {
  const _SpeakTab();

  @override
  State<_SpeakTab> createState() => _SpeakTabState();
}

class _SpeakTabState extends State<_SpeakTab> {
  final _controller = TextEditingController();
  bool _listening = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _say(String text) {
    final t = text.trim();
    if (t.isEmpty) return;
    _tap();
    sendSpeech(t);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text("El robot dirá: \"$t\""), duration: const Duration(seconds: 2)));
  }

  Future<void> _dictate() async {
    final voice = VoiceService.instance;
    if (_listening) {
      await voice.stop();
      Timer(const Duration(seconds: 2), () {
        if (_listening) voice.forceFinish();
      });
      return;
    }
    // vigilante: nunca quedarse escuchando para siempre
    Timer(const Duration(seconds: 17), () {
      if (_listening) voice.forceFinish();
    });
    _tap();
    setState(() {
      _listening = true;
      _error = null;
    });
    await voice.listen(
      onPartial: (w) {
        if (mounted) _controller.text = w;
      },
      onFinal: (w) {
        if (!mounted) return;
        setState(() => _listening = false);
        _controller.text = w;
        _say(w); // repetir lo que dije
        _controller.clear();
      },
      onError: (msg) {
        if (mounted) {
          setState(() {
            _listening = false;
            _error = msg;
          });
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (t) {
                    _say(t);
                    _controller.clear();
                  },
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: _listening ? "Te escucho..." : "Escribe o dicta lo que dirá el robot",
                    errorText: _error,
                    border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filled(
                tooltip: "Dictar (el robot repite lo que dices)",
                style: IconButton.styleFrom(backgroundColor: _listening ? scheme.error : null),
                onPressed: _dictate,
                icon: Icon(_listening ? Icons.stop_rounded : Icons.mic_rounded),
              ),
              const SizedBox(width: 4),
              IconButton.filledTonal(
                tooltip: "Enviar",
                onPressed: () {
                  _say(_controller.text);
                  _controller.clear();
                },
                icon: const Icon(Icons.send_rounded),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text("Frases rápidas", style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          Expanded(
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final p in _phrases)
                    ActionChip(
                      visualDensity: VisualDensity.compact,
                      label: Text(p),
                      onPressed: () => _say(p),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
