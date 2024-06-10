import 'package:flutter/material.dart';

class JoystickCustomStick extends StatelessWidget {
  final double size;

  JoystickCustomStick({
    this.size = 50,
    shadowColor,
    gradientColors,
    super.key,
  }): 
  shadowColor = shadowColor ?? Colors.blue.withOpacity(0.5),
  gradientColors = gradientColors ?? [Colors.lightBlue.shade900,Colors.lightBlue.shade400]
  ;

  final Color shadowColor;
  final List<Color> gradientColors;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: shadowColor,
            spreadRadius: 5,
            blurRadius: 7,
            offset: const Offset(0, 3),
          )
        ],
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: gradientColors,
        ),
      ),
    );
  }
}