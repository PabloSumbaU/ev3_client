import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

Logger log = Logger("Progressive Button");

class ProgressiveButton extends StatefulWidget {
  const ProgressiveButton({
    super.key, 
    required this.duration,
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

  final int duration;
  final Future<void> Function({required void Function() reenable}) downAction;
  final Future<void> Function({required void Function() reenable}) upAction;
  final bool manualReenable;
  final bool enableOnDownFuture;
  final bool initEnabled;
  final Color? color;
  final Color? highlightColor;
  final IconData? iconData;
  final double? iconSize;

  @override
  State<StatefulWidget> createState() {
    return _ProgressiveButtonState();
  }
}

class _ProgressiveButtonState extends State<ProgressiveButton> with SingleTickerProviderStateMixin {
  late AnimationController controller;
  late bool _enabled;
  bool _processing = false;

  void reenable() {
    setState(() {
      _enabled = true;
      _processing = false;
    });
  }

  @override
  void initState() {
    super.initState();

    controller = AnimationController(vsync: this, duration: Duration(seconds: widget.duration));
    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _onTapUp();
      }
    });

    log.finest("InitEnabled = ${widget.initEnabled}");

    _enabled = widget.initEnabled;
    _previousEnabled = _enabled;
  }

  // Yes, all of this was necessary just to disable te silly button.
  // If someone is reading this in the future, enjoy the descent into insanity!

  /* 
    Explanation: You see, since we don't have fixed instances of the widgets, we can't just set enabled = false.
    HOWEVER we also don't have direct access to the state of a widget since it's a separate class. Hence we need
    to modify a variable with callbacks, or, in this case, directly upon future completion. Which future? WE DON'T
    KNOW! :D So that warrants an extra variable just so the button can re-enable itself when the *correct* future
    completes. After all, we don't want the button to reenable when we stop listening to voice instead of when we
    finish sending the processed data, do we? BOY, ISN'T FLUTTER FUN!
  */

  void _onTapDown() {
    controller.forward();

    if (widget.manualReenable) {
      widget.downAction(reenable: reenable);
    } else {
      widget.downAction(reenable: reenable).then((_) {
        if (widget.enableOnDownFuture) {
          setState(() => _enabled = true);
        }
      });
    }
  }

  void _onTapUp() {
    controller.reset();

    setState(() {
      _processing = true;
      log.finest("TapUp: Processing...");
    });

    if (widget.manualReenable) {
      widget.upAction(reenable: reenable);
    } else {
      widget.upAction(reenable: reenable).then((_) {
        if (!widget.enableOnDownFuture) {
          setState(() => _processing = false);
        }
      });
    }
  }

  bool _previousEnabled = false;

  void reinitialize() {
    if (widget.initEnabled != _previousEnabled) {
      _enabled = widget.initEnabled;
      _previousEnabled = _enabled;
    }
  }
  
  @override
  Widget build(BuildContext context) {
    reinitialize();
    log.finest("Building: enabled = $_enabled | initEnabled = ${widget.initEnabled}");
    final double size = (widget.iconSize ?? 24) * 1.5;
    return GestureDetector(
      onTapDown: _enabled || _processing ? (details) => _onTapDown() : null,
      onTapUp: _enabled || _processing ? (details) => _onTapUp() : null,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _enabled ? widget.color ?? Theme.of(context).primaryColor : Theme.of(context).disabledColor,
            ),
          ),
          AnimatedBuilder(
            animation: controller,
            builder: (context, child) {
              return ClipOval(
                clipper: CircleProgressClipper(
                  progress: controller.value,
                ),
                child: Container(
                  width: size,
                  height: size,
                  color: widget.highlightColor ?? Theme.of(context).splashColor,
                ),
              );
            },
          ),
          _processing ?
            SizedBox(
              width: size * 0.75,
              height: size * 0.75,
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(
                    Theme.of(context).scaffoldBackgroundColor
                ),
              ),
            )
          :
            Icon(widget.iconData, 
              size: widget.iconSize, 
              color: _enabled ? Theme.of(context).scaffoldBackgroundColor : Theme.of(context).hintColor,
            )
        ],
      ),
    );
  }
}

class CircleProgressClipper extends CustomClipper<Rect> {
  final double progress;

  CircleProgressClipper({required this.progress});

  @override
  Rect getClip(Size size) {
    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final radius = (size.width / 2) * progress;
    return Rect.fromCircle(center: Offset(centerX, centerY), radius: radius);
  }

  @override
  bool shouldReclip(CustomClipper<Rect> oldClipper) {
    return true;
  }
}