import 'dart:async';

import 'package:ev3_client/presentation/components/toggle_progressive_button.dart';
import 'package:ev3_client/presentation/custom_icons.dart';
import 'package:ev3_client/utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_joystick/flutter_joystick.dart';
import 'package:flutter_vibrate/flutter_vibrate.dart';
import 'package:logging/logging.dart';

import './components/themed_toggle_button.dart';
import './components/themed_cycling_button.dart';
import './components/sensor_widget.dart';
import './components/custom_stick.dart';
import './components/progressive_button.dart';
import './components/map_widget.dart';

import '../infrastructure/socket_connection.dart';
import '../infrastructure/voice_recognition.dart';

final Logger _log = Logger("Control");
void hapticFeedback() async {
  if (await Vibrate.canVibrate) {
    Vibrate.feedback(FeedbackType.light);
  }
}

class ControlPage extends StatelessWidget {
  const ControlPage({super.key});

  final SnackBar _disconnected = const SnackBar(content: Text("Desconectado"));

  @override
  Widget build(BuildContext context) {
    SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);

    return Scaffold(
      body: const Center(
        child: Padding(
          padding: EdgeInsets.fromLTRB(8, 15, 8, 8),
          child: Stack(
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  SensorBar(),
                  Controls(),
                ],
              ),
              Positioned(
                top: 0,
                right: 0,
                child: MapWidget(),
              )
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _onDisconnectPressed(context), 
        child: const Icon(
          Icons.link_off,
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.miniStartTop,
    );
  }

  void _onDisconnectPressed(BuildContext context) {
    disconnect();
    ScaffoldMessenger.of(context).showSnackBar(_disconnected);
    Navigator.pop(context);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }
}

class SensorBar extends HookWidget {
  const SensorBar({super.key});

  @override
  Widget build(BuildContext context) {
    final sensorData = useState("-");
    
    useEffect(() {
      addSensorCallback((message) {sensorData.value = message;});
      return;
    }, []);

    List<String> sensorsData = sensorData.value.split(";");
    List<Widget> sensorWidgets = [];

    for (String sensor in sensorsData) {
      final data = sensor.split(":");

      switch (data[0]) {
        case "ir":
          sensorWidgets.add(
            SensorWidget(icon: const Icon(Icons.track_changes), label: const Text("Proximidad"), data: data[1])
          );
          break;
        
        case "cl":
          sensorWidgets.add(
            SensorWidget(icon: const Icon(Icons.color_lens), label: const Text("Color"), data: data[1])
          );
        break;

        case "gy":
          sensorWidgets.add(
            SensorWidget(icon: const Icon(Icons.threesixty), label: const Text("Giroscopio"), data: data[1])
          );
        break;

        case "tc":
          sensorWidgets.add(
            SensorWidget(icon: const Icon(Icons.touch_app), label: const Text("Táctil"), data: data[1])
          );
        break;

        default:
          _log.warning("Unhandled or invalid sensor data: $sensor");
      }
    }

    if (sensorWidgets.isNotEmpty) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: sensorWidgets,
      );
    } else {
      return const SensorWidget(icon: Icon(Icons.sensors_off), label: Text("No disponible"), data: "");
    }
  }
}

enum ControlType {
  joystick, area, voice
}

ControlType _currentControl = ControlType.joystick;
bool listenerAdded = false;

class ControlTypeButton extends StatelessWidget {
  const ControlTypeButton({
    super.key,
    required this.updateHandler,
  });

  final void Function(ControlType) updateHandler;

  @override
  Widget build(BuildContext context) {
    return ThemedCyclingButton<ControlType>(
      initialState: ControlType.joystick,
      updateHandler: updateHandler,
      states: ControlType.values,
      icons: const [CustomIcons.joystick, Icons.touch_app, Icons.mic],
      iconSize: 35,
    );
  }
}

VoiceRecognition? vRecog;
const SnackBar _voiceUnavailable = SnackBar(content: Text("El reconocimiento de voz no está disponible"));

Future<bool> instantiateVoiceRecognition(BuildContext context) async {
    _log.fine("Initializing voice recognition...");
    vRecog = await VoiceRecognition.getInstance(
      () => ScaffoldMessenger.of(context).showSnackBar(_voiceUnavailable)
    );
    return vRecog != null;
  }

class Controls extends HookWidget {
  const Controls({super.key});

  final SnackBar _invalidVCommand = const SnackBar(content: Text("El comando no se reconoció o fue inválido"));

  void _joystickListener(StickDragDetails details) {
    still = details.x == 0 && details.y == 0;

    var joyX = normalizeStringLen(details.x, 5);
    var joyY = normalizeStringLen(details.y, 5);

    send("stick:$joyX;$joyY;${_useClaw ? 1 : 0}");
  }

  Timer ensureReenable(void Function() reenable) {
    return Timer.periodic(const Duration(seconds: 3), (timer) {
      if (!vRecog!.isListening()) {
        reenable();
        timer.cancel();
      }
    });
  }

  Future<void> startVoice(BuildContext context, void Function() reenable) async {
    hapticFeedback();
    Timer timer = ensureReenable(reenable);
    
    await vRecog!.listen(
      (result) => getInstructionSet(result).then(
        (message) {
          if (message == null) {
            ScaffoldMessenger.of(context).showSnackBar(_invalidVCommand);
          } else {
            send("text:$message");
          }

          timer.cancel();
          reenable();
        }
      )
    );
  }

  Future<void> endVoice({required reenable}) async {
    await vRecog!.stop();
    hapticFeedback();
  }

  @override
  Widget build(BuildContext context) {
    final controlType = useState(_currentControl);
    final voiceInitialized = useState(false);

    if (!listenerAdded) {
      controlType.addListener(() {
        if (controlType.value == ControlType.voice && vRecog == null) {
          instantiateVoiceRecognition(context).then((value) { 
            voiceInitialized.value = value;
            _log.fine("Voice recognition initialized: ${voiceInitialized.value}");
          });
        }
      });

      listenerAdded = true;
    }
    
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: ControlTypeButton(updateHandler: (ControlType newState) {
                _currentControl = newState;
                controlType.value = _currentControl;
              }),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: ToggleProgressiveButton(
                initToggled: voiceInitialized.value,
                duration: 8, 
                toggleAction: () {
                  if (vRecog == null) {
                    return instantiateVoiceRecognition(context).then(
                      (value) {
                        voiceInitialized.value = value;
                        return value;
                      });
                  } else {
                    return Future(() => true);
                  }
                },
                downAction: ({required reenable}) {
                  // Sometimes hangs showing the progress indicator despite being reenabled, not sure why
                  hapticFeedback();
                  Timer timer = ensureReenable(reenable);
                  
                  return vRecog!.listen((result) {
                    sendSpeech(result);
                    timer.cancel();
                    reenable();
                  });
                }, 
                upAction: ({required reenable}) {
                  hapticFeedback();
                  return vRecog!.stop();
                }, 
                initEnabled: true,
                iconData: Icons.speaker,
                iconSize: 35,
              ),
            )
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            switch(_currentControl) {
              ControlType.joystick => 
                Joystick(
                  listener: _joystickListener,
                  onStickDragEnd: () => send("stick:*;${_useClaw ? 1 : 0}"),
                  base: JoystickBase(color: Theme.of(context).primaryColor.withOpacity(0.75),),
                  stick: JoystickCustomStick(
                    shadowColor: Theme.of(context).primaryColor.withOpacity(0.5),
                    gradientColors: [
                      Theme.of(context).primaryColor, 
                      Theme.of(context).highlightColor,
                      //TODO: Check the colors
                    ],
                  ),
                ),

              ControlType.area =>
                SizedBox(
                  width: 300,
                  height: 200,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor.withOpacity(0.75),
                      borderRadius: const BorderRadius.all(Radius.circular(15)),
                    ),
                    child: SafeArea(
                      child: JoystickArea(
                        listener: _joystickListener,
                        onStickDragEnd: () => send("stick:*;${_useClaw ? 1 : 0}"),
                        base: const JoystickSquareBase(
                          color: Color.fromARGB(0, 0, 0, 0),
                          drawArrows: false,
                        ),
                        stick: JoystickCustomStick(
                          shadowColor: const Color.fromARGB(0, 0, 0, 0),
                          gradientColors: const [Color.fromARGB(0, 0, 0, 0), Color.fromARGB(0, 0, 0, 0)],
                        ),
                      ),
                    ),
                  ),
                ),

              ControlType.voice =>
                SizedBox(
                  width: 200,
                  height: 200,
                  child: ProgressiveButton(
                    duration: 8, 
                    downAction: ({required reenable}) => startVoice(context, reenable), 
                    upAction: endVoice,
                    initEnabled: voiceInitialized.value,
                    iconData: Icons.mic,
                    iconSize: 70,
                  )
                )
            },
            const ClawButton(),
          ],
        ),
      ],
    );
  }
}

bool _useClaw = false, still = true;

class ClawButton extends StatelessWidget {
  const ClawButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ThemedToggleButton(
      initialState: _useClaw,
      handler: (clawing) {
        _useClaw = !_useClaw;
        clawing.value = _useClaw;

        if (still) {
          send("stick:0.000;0.000;${_useClaw ? 1 : 0}");
        }
      },
      toggledIcon: const Icon(Icons.precision_manufacturing),
      untoggledIcon: const Icon(Icons.precision_manufacturing_outlined),
      iconSize: 100,
    );
  }
}