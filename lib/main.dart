import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

import 'presentation/connect_page.dart';

void main() {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    String color = "";
    String reset = "\x1B[0m";
    
    switch (record.level) {
      case Level.FINEST:
        color = "\x1B[37m";
        break;

      case Level.FINER:
        color = "\x1B[36m";
        break;
      
      case Level.FINE:
        color = "\x1B[32m";
        break;
      
      case Level.SEVERE:
        color = "\x1B[31m";
        break;

      case Level.WARNING:
        color = "\x1B[33m";
        break;
      default:
        color = "";
    }

    //ignore: avoid_print
    print('$color${record.level.name}: ${record.time}: ${record.message}$reset');
  });
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
