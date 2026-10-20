
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_joystick/flutter_joystick.dart';
import 'package:vibration/vibration.dart';

import '../infrastructure/gemini.dart';
import '../infrastructure/socket_connection.dart';
import '../infrastructure/voice_recognition.dart';
import '../utils.dart';
import 'components/custom_stick.dart';
import 'components/map_widget.dart';
import 'components/social_panel.dart';
import 'components/voice_panel.dart';
import 'robot_state.dart';

void hapticFeedback() async {
  if (await Vibration.hasVibrator()) {
    Vibration.vibrate(duration: 50);
  }
}

enum ControlType { joystick, area, voice }

/// Pantalla de control (horizontal):
///  izquierda: movimiento (joystick / área / voz) + garra + PARAR
///  derecha:   estado del robot + acciones sociales + hacer hablar al robot
class ControlPage extends StatefulWidget {
  const ControlPage({super.key});

  @override
  State<ControlPage> createState() => _ControlPageState();
}

class _ControlPageState extends State<ControlPage> {
  ControlType _control = ControlType.joystick;
  bool _leaving = false;

  void _onSensor(String message) {
    RobotState.status.value = RobotStatus.parse(message);
  }

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    RobotState.reset();
    addSensorCallback(_onSensor);
    connectionLost.addListener(_onConnectionLost);
  }

  @override
  void dispose() {
    removeSensorCallback(_onSensor);
    connectionLost.removeListener(_onConnectionLost);
    VoiceService.instance.cancel();
    super.dispose();
  }

  void _onConnectionLost() {
    if (!connectionLost.value || _leaving || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Se perdió la conexión con el robot")),
    );
    _leave();
  }

  void _leave() {
    if (_leaving) return;
    _leaving = true;
    MapWidget.terminate();
    disconnect();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ------------------------------------------------ movimiento
                Expanded(
                  flex: 5,
                  child: Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        children: [
                          SegmentedButton<ControlType>(
                            showSelectedIcon: false,
                            style: const ButtonStyle(visualDensity: VisualDensity.compact),
                            segments: const [
                              ButtonSegment(value: ControlType.joystick, icon: Icon(Icons.gamepad_rounded), label: Text("Joystick")),
                              ButtonSegment(value: ControlType.area, icon: Icon(Icons.touch_app_rounded), label: Text("Área")),
                              ButtonSegment(value: ControlType.voice, icon: Icon(Icons.mic_rounded), label: Text("Voz")),
                            ],
                            selected: {_control},
                            onSelectionChanged: (s) {
                              hapticFeedback();
                              send("stick:*;${RobotState.clawClosed.value ? 1 : 0}");
                              setState(() => _control = s.first);
                            },
                          ),
                          Expanded(child: Center(child: _buildControl(context))),
                          Row(
                            children: [
                              const Expanded(child: _ClawButton()),
                              const SizedBox(width: 8),
                              Expanded(
                                child: FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: scheme.error,
                                    foregroundColor: scheme.onError,
                                    minimumSize: const Size.fromHeight(44),
                                  ),
                                  onPressed: () {
                                    hapticFeedback();
                                    sendInstructions("s");
                                  },
                                  icon: const Icon(Icons.stop_circle_rounded),
                                  label: const Text("PARAR", style: TextStyle(fontWeight: FontWeight.bold)),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // ------------------------------------------------ social
                Expanded(
                  flex: 6,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _StatusBar(onDisconnect: _leave),
                      const SizedBox(height: 6),
                      const Expanded(
                        child: Card(
                          margin: EdgeInsets.zero,
                          clipBehavior: Clip.antiAlias,
                          child: SocialPanel(),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _joystickListener(StickDragDetails details) {
    var joyX = normalizeStringLen(details.x, 5);
    var joyY = normalizeStringLen(details.y, 5);
    send("stick:$joyX;$joyY;${RobotState.clawClosed.value ? 1 : 0}");
  }

  void _joystickEnd() => send("stick:*;${RobotState.clawClosed.value ? 1 : 0}");

  Widget _buildControl(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    switch (_control) {
      case ControlType.joystick:
        return FittedBox(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Joystick(
              listener: _joystickListener,
              onStickDragEnd: _joystickEnd,
              base: JoystickBase(color: scheme.primary.withValues(alpha: 0.75)),
              stick: JoystickCustomStick(
                shadowColor: scheme.primary.withValues(alpha: 0.5),
                gradientColors: [scheme.primary, scheme.primaryContainer],
              ),
            ),
          ),
        );
      case ControlType.area:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: const BorderRadius.all(Radius.circular(16)),
            ),
            child: Stack(
              children: [
                Center(
                  child: Text(
                    "Arrastra el dedo en cualquier parte",
                    style: TextStyle(color: scheme.onPrimaryContainer.withValues(alpha: 0.6)),
                  ),
                ),
                JoystickArea(
                  listener: _joystickListener,
                  onStickDragEnd: _joystickEnd,
                  base: const JoystickSquareBase(color: Color.fromARGB(0, 0, 0, 0), drawArrows: false),
                  stick: JoystickCustomStick(
                    size: 44,
                    shadowColor: scheme.primary.withValues(alpha: 0.3),
                    gradientColors: [scheme.primary, scheme.primary.withValues(alpha: 0.6)],
                  ),
                ),
              ],
            ),
          ),
        );
      case ControlType.voice:
        return const VoicePanel();
    }
  }
}

// ------------------------------------------------------------------ garra
class _ClawButton extends StatelessWidget {
  const _ClawButton();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: RobotState.clawClosed,
      builder: (context, closed, _) {
        final child = Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(closed ? Icons.back_hand_rounded : Icons.front_hand_outlined),
            const SizedBox(width: 6),
            Text(closed ? "Soltar" : "Agarrar"),
          ],
        );
        void onPressed() {
          hapticFeedback();
          RobotState.clawClosed.value = !closed;
          send("stick:*;${!closed ? 1 : 0}");
        }

        const size = Size.fromHeight(44);
        return closed
            ? FilledButton(style: FilledButton.styleFrom(minimumSize: size), onPressed: onPressed, child: child)
            : FilledButton.tonal(style: FilledButton.styleFrom(minimumSize: size), onPressed: onPressed, child: child);
      },
    );
  }
}

// ------------------------------------------------------------------ estado
class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.onDisconnect});

  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        child: ValueListenableBuilder<RobotStatus>(
          valueListenable: RobotState.status,
          builder: (context, status, _) {
            final prox = status.proximity;
            final near = prox != null && prox <= 15;
            final action = actionLabels[status.action] ?? (status.action.isEmpty ? "Listo" : status.action);
            return Row(
              children: [
                Text(emotionEmoji[status.emotion] ?? "🙂", style: const TextStyle(fontSize: 26)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(action, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall),
                      Text("Ánimo: ${status.emotion}", maxLines: 1,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                Tooltip(
                  message: "Sensor de proximidad (0 = muy cerca)",
                  child: Chip(
                    visualDensity: VisualDensity.compact,
                    backgroundColor: near ? scheme.errorContainer : null,
                    avatar: Icon(Icons.sensors_rounded, size: 18, color: near ? scheme.error : null),
                    label: Text(prox?.toString() ?? "--"),
                  ),
                ),
                const SizedBox(width: 4),
                ValueListenableBuilder<bool>(
                  valueListenable: RobotState.useAI,
                  builder: (context, ai, _) => FilterChip(
                    visualDensity: VisualDensity.compact,
                    tooltip: Gemini.isConfigured
                        ? "Usar Gemini para entender la voz"
                        : "Sin clave de Gemini: solo intérprete local",
                    selected: ai && Gemini.isConfigured,
                    avatar: const Icon(Icons.auto_awesome_rounded, size: 16),
                    showCheckmark: false,
                    label: const Text("IA"),
                    onSelected: Gemini.isConfigured ? (v) => RobotState.useAI.value = v : null,
                  ),
                ),
                IconButton(
                  tooltip: "Mapa",
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _showMap(context),
                  icon: const Icon(Icons.map_rounded),
                ),
                IconButton(
                  tooltip: "Desconectar",
                  visualDensity: VisualDensity.compact,
                  onPressed: onDisconnect,
                  icon: Icon(Icons.link_off_rounded, color: scheme.error),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _showMap(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Mapa aproximado"),
        contentPadding: const EdgeInsets.all(12),
        content: const SizedBox(
          width: 240,
          height: 240,
          child: FittedBox(child: MapWidget()),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cerrar"))],
      ),
    );
  }
}
