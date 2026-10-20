import 'package:ev3_client/utils.dart';
import 'package:flutter/material.dart';

import 'presentation/connect_page.dart';

void main() {
  initializeLogger();
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  static const _seed = Color(0xFF6C4BD8); // violeta amigable

  ThemeData _theme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      chipTheme: const ChipThemeData(shape: StadiumBorder()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Robot social EV3",
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: const ConnectPage(),
    );
  }
}
