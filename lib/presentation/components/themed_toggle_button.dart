import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

class ThemedToggleButton extends HookWidget {
  const ThemedToggleButton({
    super.key,
    required this.initialState,
    required this.handler,
    required this.toggledIcon,
    required this.untoggledIcon,
    required this.iconSize,
    this.toggledColor,
    this.untoggledColor,
    this.toggledIconColor,
    this.untoggledIconColor,
  });

  final bool initialState;
  final void Function(ValueNotifier<bool>) handler;
  final Icon toggledIcon;
  final Icon untoggledIcon;
  final Color? toggledColor;
  final Color? untoggledColor;
  final Color? toggledIconColor;
  final Color? untoggledIconColor;
  final double iconSize;

  void Function() _onPressed(ValueNotifier<bool> stateHook) {
    return () {
      handler(stateHook);
    };
  }

  @override
  Widget build(BuildContext context) {
    final toggled = useState(initialState);

    return Ink(
      decoration: ShapeDecoration(
        color: toggled.value ? 
          toggledColor ?? Theme.of(context).primaryColor 
        : 
          untoggledColor ?? Theme.of(context).disabledColor,
        shape: const CircleBorder(),
      ),
      child: IconButton(
        onPressed: _onPressed(toggled),
        icon: toggled.value ? toggledIcon : untoggledIcon,
        iconSize: iconSize,
        color: toggled.value ? 
          toggledIconColor ?? Theme.of(context).scaffoldBackgroundColor 
        : 
          untoggledIconColor ?? Theme.of(context).hintColor,
      ),
    );
  }
}