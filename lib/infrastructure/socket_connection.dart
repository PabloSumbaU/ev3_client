import 'dart:io';
import 'dart:convert' show utf8;
import 'package:logging/logging.dart';

final _log = Logger("Socket Connection");
Socket? _mainSocket;
Socket? _sensorSocket;
Socket? _speechSocket;
Socket? _positionSocket;
List<void Function(String message)> _sensorCallbacks = [];
String _lastSensorValue = "";
List<void Function(double x, double y, double angle)> _positionCallbacks = [];

bool isConnected() {
  return _mainSocket != null;
}

Future<void> connect(String ipAddress, [int port=8000, int sensorPort=8001, int speechPort=8002, int positionPort = 8003]) async {
  try { 
    _mainSocket = await Socket.connect(ipAddress, port, timeout: const Duration(seconds: 60));
    _log.fine("Main socket connection established");
    _sensorSocket = await Socket.connect(ipAddress, sensorPort, timeout: const Duration(seconds: 60));
    _log.fine("Sensor socket connection established");
    _speechSocket = await Socket.connect(ipAddress, speechPort, timeout: const Duration(seconds: 60));
    _log.fine("Speech socket connection established");
    _positionSocket = await Socket.connect(ipAddress, positionPort, timeout: const Duration(seconds: 60));
    _log.fine("Position socket connection established");

    _sensorListen((message) {
      _lastSensorValue = message;

      for (var callback in _sensorCallbacks) {
        callback(message);
      }
    });

    _positionListen((message) {
      String data = message.split(messageEnd)[0];
      List<String> parts = data.split(";");

      double x = double.parse(parts[0]);
      double y = double.parse(parts[1]);
      double angle = double.parse(parts[2]);

      for (var callback in _positionCallbacks) {
        callback(x, y, angle);
      }
    });
  } on SocketException catch (e) {
    _log.severe("Connection failed: ${e.message}");
  }
}

const messageEnd = "|";

void send(String message) {
  _log.fine("Message sent: $message");
  _mainSocket!.write(message + messageEnd);
}

void sendSpeech(String message) {
  _log.fine("Message sent: $message");
  _speechSocket!.write(message);
}

void _sensorListen(void Function(String message) callback) {
  _sensorSocket!.listen((event) {callback(utf8.decode(event).split(messageEnd)[0]);});
}

void addSensorCallback(void Function(String message) callback) {
  _sensorCallbacks.add(callback);
}

String getLastSensorValue() {
  return _lastSensorValue;
}

void _positionListen(void Function(String message) callback) {
  _positionSocket!.listen((event) { callback(utf8.decode(event).split(messageEnd)[0]);});
}

void addPositionCallback(void Function(double x, double y, double angle) callback) {
  _positionCallbacks.add(callback);
}

void disconnect() {
  _mainSocket!.close();
  _sensorSocket!.close();
  _speechSocket!.close();
  _positionSocket!.close();

  _sensorCallbacks.clear();
  _lastSensorValue = "";
}