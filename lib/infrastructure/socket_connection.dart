import 'dart:io';
import 'dart:convert' show utf8;
import 'package:logging/logging.dart';

final _log = Logger("Socket Connection");
Socket? _mainSocket;
Socket? _sensorSocket;
Socket? _speechSocket;

bool isConnected() {
  return _mainSocket != null;
}

Future<void> connect(String ipAddress, [int port=8000, int sensorPort=8001, int speechPort=8002]) async {
  try { 
    _mainSocket = await Socket.connect(ipAddress, port, timeout: const Duration(seconds: 60));
    _log.fine("Main socket connection established");
    _sensorSocket = await Socket.connect(ipAddress, sensorPort, timeout: const Duration(seconds: 60));
    _log.fine("Sensor socket connection established");
    _speechSocket = await Socket.connect(ipAddress, speechPort, timeout: const Duration(seconds: 60));
    _log.fine("Speech socket connection established");
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

void sensorListen(void Function(String) callback) {
  _sensorSocket!.listen((event) {callback(utf8.decode(event).split(messageEnd)[0]);});
}

void disconnect() {
  _mainSocket!.close();
  _sensorSocket!.close();
}