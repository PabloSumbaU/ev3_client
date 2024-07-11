import 'package:ev3_client/utils.dart';
import 'package:flutter/material.dart';

import 'presentation/connect_page.dart';

void main() {
  initializeLogger();
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: ConnectPage(),
    );
  }
}
