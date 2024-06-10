import 'package:flutter/material.dart';

class SensorWidget extends StatelessWidget {
  const SensorWidget({
    super.key, 
    required this.icon,
    required this.label, 
    required this.data,
  });

  final Icon icon;
  final Text label;
  final String data;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        icon,
        const SizedBox(width: 0, height: 5,),
        label,
        const SizedBox(width: 0, height: 5,),
        Text(data),
      ],
    );
  }
}