import 'package:ev3_client/presentation/components/progressive_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:logging/logging.dart';

Logger log = Logger("Toggle Progressive Button");

class ToggleProgressiveButton extends HookWidget {
  const ToggleProgressiveButton({
    super.key, 
    required this.initToggled,
    required this.duration,
    required this.toggleAction,
    required this.downAction,
    required this.upAction,
    this.manualReenable = false,
    this.enableOnDownFuture = true,
    required this.initEnabled,
    this.color,
    this.highlightColor,
    this.iconData,
    this.iconSize
  });

  final bool initToggled;
  final int duration;
  final Future<bool> Function() toggleAction;
  final Future<void> Function({required void Function() reenable}) downAction;
  final Future<void> Function({required void Function() reenable}) upAction;
  final bool manualReenable;
  final bool enableOnDownFuture;
  final bool initEnabled;
  final Color? color;
  final Color? highlightColor;
  final IconData? iconData;
  final double? iconSize;

  void Function() _onPressed(ValueNotifier<bool> stateHook) {
    return () => toggleAction().then((value) => stateHook.value = value);
  }

  @override
  Widget build(BuildContext context) {
    final toggled = useState(initToggled);
    
    useEffect(() {
      toggled.value = initToggled;
      log.finest("Side effect: initToggled = $initToggled");
      return null;
    }, [initToggled]);

    if (toggled.value) {
      return ProgressiveButton(
        duration: duration, 
        downAction: downAction, 
        upAction: upAction, 
        manualReenable: manualReenable,
        enableOnDownFuture: enableOnDownFuture,
        initEnabled: initEnabled,
        color: color,
        highlightColor: highlightColor,
        iconData: iconData,
        iconSize: iconSize,
      );
    } else {
      return Ink(
        decoration: ShapeDecoration(
          color: color ?? Theme.of(context).scaffoldBackgroundColor,
          shape: const CircleBorder(),
        ),
        child: IconButton(
          onPressed: _onPressed(toggled),
          icon: Icon(iconData),
          iconSize: iconSize,
          color: color ?? Theme.of(context).primaryColor,
        ),
      );
    }
  }
}