import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart';

import '../../infrastructure/command_parser.dart';
import '../../infrastructure/socket_connection.dart';
import '../../infrastructure/voice_recognition.dart';
import '../robot_state.dart';

enum _Phase { idle, listening, thinking, done, error }

/// Control por voz: tocar para hablar (ya no hay que mantener apretado).
///
/// idle -> listening (anillo animado + texto en vivo) -> thinking -> done
/// (muestra los pasos que entendió y los envía al robot) -> idle.
class VoicePanel extends StatefulWidget {
  const VoicePanel({super.key});

  @override
  State<VoicePanel> createState() => _VoicePanelState();
}

class _VoicePanelState extends State<VoicePanel> with SingleTickerProviderStateMixin {
  final _voice = VoiceService.instance;
  late final AnimationController _pulse;
  _Phase _phase = _Phase.idle;
  String _words = "";
  String _message = "Toca el micrófono y da una orden";
  InterpretResult? _result;
  Timer? _resetTimer;
  Timer? _watchdog;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
  }

  @override
  void dispose() {
    _resetTimer?.cancel();
    _watchdog?.cancel();
    _pulse.dispose();
    _voice.cancel();
    super.dispose();
  }

  void _vibrate() async {
    if (await Vibration.hasVibrator()) Vibration.vibrate(duration: 40);
  }

  void _set(_Phase phase, {String? message}) {
    if (!mounted) return;
    setState(() {
      _phase = phase;
      if (message != null) _message = message;
    });
    // Vigilante: el botón nunca se queda trabado. Si el teléfono no avisa que
    // terminó de escuchar (o de entender), se cierra a la fuerza.
    _watchdog?.cancel();
    if (phase == _Phase.listening) {
      _watchdog = Timer(const Duration(seconds: 17), () {
        if (_phase == _Phase.listening) _voice.forceFinish();
      });
    } else if (phase == _Phase.thinking) {
      _watchdog = Timer(const Duration(seconds: 12), () {
        if (_phase == _Phase.thinking) _set(_Phase.error, message: "Tardó demasiado. Intenta de nuevo.");
      });
    }
    if (phase == _Phase.listening) {
      _pulse.repeat();
    } else {
      _pulse.stop();
      _pulse.reset();
    }
  }

  Future<void> _onTap() async {
    _resetTimer?.cancel();
    switch (_phase) {
      case _Phase.listening:
        _vibrate();
        await _voice.stop();
        // si en 2 s no llega el resultado, cerrar igual
        Timer(const Duration(seconds: 2), () {
          if (_phase == _Phase.listening) _voice.forceFinish();
        });
        return;
      case _Phase.thinking:
        return;
      default:
        break;
    }

    _vibrate();
    setState(() {
      _words = "";
      _result = null;
    });
    _set(_Phase.listening, message: "Te escucho...");
    await _voice.listen(
      onPartial: (w) {
        if (mounted) setState(() => _words = w);
      },
      onFinal: _process,
      onError: (msg) => _set(_Phase.error, message: msg),
    );
  }

  Future<void> _process(String words) async {
    if (!mounted) return;
    setState(() => _words = words);
    _set(_Phase.thinking, message: "Entendiendo...");

    final result = await interpretCommand(words, useAI: RobotState.useAI.value);
    if (!mounted) return;

    if (result.command.isEmpty) {
      _set(_Phase.error, message: "No entendí la orden. Prueba con \"avanza 30 centímetros\" o \"baila\".");
      return;
    }

    sendInstructions(result.command.instructions);
    _vibrate();
    setState(() => _result = result);
    _set(_Phase.done, message: result.note ?? "Enviado al robot");
    _resetTimer = Timer(const Duration(seconds: 6), () => _set(_Phase.idle, message: "Toca el micrófono y da una orden"));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final listening = _phase == _Phase.listening;
    final buttonColor = switch (_phase) {
      _Phase.listening => scheme.error,
      _Phase.error => scheme.errorContainer,
      _ => scheme.primary,
    };
    final iconColor = _phase == _Phase.error ? scheme.onErrorContainer : (listening ? scheme.onError : scheme.onPrimary);

    return LayoutBuilder(builder: (context, c) {
      final size = min(100.0, c.maxHeight * 0.34);
      return SingleChildScrollView(
        child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: c.maxHeight, minWidth: c.maxWidth),
        child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: size * 1.45,
            height: size * 1.45,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (listening)
                  AnimatedBuilder(
                    animation: Listenable.merge([_pulse, _voice.soundLevel]),
                    builder: (context, _) {
                      final level = (_voice.soundLevel.value.clamp(-2, 10) + 2) / 12;
                      final t = _pulse.value;
                      return Stack(alignment: Alignment.center, children: [
                        _ring(size * (1 + 0.45 * t), scheme.error.withValues(alpha: 0.35 * (1 - t))),
                        _ring(size * (1.05 + 0.35 * level), scheme.error.withValues(alpha: 0.22)),
                      ]);
                    },
                  ),
                Material(
                  color: buttonColor,
                  shape: const CircleBorder(),
                  elevation: listening ? 6 : 2,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _onTap,
                    child: SizedBox(
                      width: size,
                      height: size,
                      child: _phase == _Phase.thinking
                          ? Padding(
                              padding: EdgeInsets.all(size * 0.3),
                              child: CircularProgressIndicator(strokeWidth: 4, color: scheme.onPrimary),
                            )
                          : Icon(
                              listening ? Icons.stop_rounded : Icons.mic_rounded,
                              size: size * 0.5,
                              color: iconColor,
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          if (_words.isNotEmpty)
            Text(
              "“$_words”",
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          const SizedBox(height: 4),
          if (_phase == _Phase.done && _result != null) _StepsView(result: _result!),
          Text(
            listening ? "Habla ahora · toca para terminar" : _message,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _phase == _Phase.error ? scheme.error : scheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
        ),
      );
    });
  }

  Widget _ring(double d, Color color) => Container(
        width: d,
        height: d,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      );
}

class _StepsView extends StatelessWidget {
  const _StepsView({required this.result});

  final InterpretResult result;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final steps = result.command.steps;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final RobotStep s in steps.take(5))
            Chip(
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              avatar: Icon(iconForStep(s), size: 16),
              label: Text(s.label, style: const TextStyle(fontSize: 12)),
            ),
          if (steps.length > 5) Chip(label: Text("+${steps.length - 5}")),
          Chip(
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            backgroundColor: result.source == "IA" ? scheme.tertiaryContainer : scheme.secondaryContainer,
            label: Text(result.source, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
