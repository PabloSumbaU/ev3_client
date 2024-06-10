import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

class ThemedCyclingButton<T extends Enum> extends HookWidget {
  const ThemedCyclingButton({
    super.key,
    required this.states,
    required this.initialState,
    required this.updateHandler,
    required this.icons,
    this.colors,
    this.iconColors,
    required this.iconSize,
  });
  
  final List<T> states;
  final T initialState;
  final Function(T) updateHandler;
  final List<IconData> icons;
  final List<Color>? colors;
  final List<Color>? iconColors;
  final double iconSize;

  void Function() _onPressed(ValueNotifier<T> stateHook) {
    return () {
      int currentIndex = states.indexOf(stateHook.value);
      stateHook.value = states[++currentIndex % states.length];
      updateHandler(stateHook.value);
    };
  }

  @override
  Widget build(BuildContext context) {
    final state = useState(initialState);
    final int index = states.indexOf(state.value);

    return Ink(
      decoration: ShapeDecoration(
        color: colors?[index] ?? Theme.of(context).primaryColor,
        shape: const CircleBorder(),
      ),
      child: IconButton(
        onPressed: _onPressed(state),
        icon: Icon(icons[index], color: iconColors?[index] ?? Theme.of(context).scaffoldBackgroundColor,),
        iconSize: iconSize,
      ),
    );
  }
}