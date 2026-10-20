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

const messageEnd = "|";

/// Retorna true si el socket principal y el de audio están inicializados
bool isConnected() {
  return _mainSocket != null && _speechSocket != null;
}

Future<void> connect(
  String ipAddress, [
  int port = 8000,
  int sensorPort = 8001,
  int speechPort = 8002,
  int positionPort = 8003,
]) async {
  try {
    _mainSocket = await Socket.connect(ipAddress, port, timeout: const Duration(seconds: 15));
    _log.fine("Main socket connection established");

    _sensorSocket = await Socket.connect(ipAddress, sensorPort, timeout: const Duration(seconds: 15));
    _log.fine("Sensor socket connection established");

    _speechSocket = await Socket.connect(ipAddress, speechPort, timeout: const Duration(seconds: 15));
    _log.fine("Speech socket connection established");

    _positionSocket = await Socket.connect(ipAddress, positionPort, timeout: const Duration(seconds: 15));
    _log.fine("Position socket connection established");

    _sensorListen((message) {
      _lastSensorValue = message;
      for (var callback in _sensorCallbacks) {
        callback(message);
      }
    });

    _positionListen((message) {
      try {
        String data = message.split(messageEnd)[0];
        List<String> parts = data.split(";");

        if (parts.length >= 3) {
          double x = double.parse(parts[0]);
          double y = double.parse(parts[1]);
          double angle = double.parse(parts[2]);

          for (var callback in _positionCallbacks) {
            callback(x, y, angle);
          }
        }
      } catch (e) {
        _log.warning("Error parsing position data: $e");
      }
    });
  } on SocketException catch (e) {
    _log.severe("Connection failed: ${e.message}");
    disconnect();
  } catch (e) {
    _log.severe("Unexpected error on connect: $e");
    disconnect();
  }
}

/// Envía comandos de movimiento al socket principal
void send(String message) {
  if (_mainSocket == null) {
    _log.warning("Main socket is null. Message not sent.");
    return;
  }
  _log.fine("Message sent to main socket: $message");
  _mainSocket!.add(utf8.encode(message + messageEnd));
  _mainSocket!.flush();
}

/// Envía texto para ser reproducido por voz en el parlante del robot
void sendSpeech(String message) {
  if (_speechSocket == null) {
    _log.warning("Speech socket is null. Speech message not sent.");
    return;
  }
  _log.fine("Message sent to speech socket: $message");
  
  // Incluye el delimitador de fin de mensaje '|'
  // Codifica explícitamente a UTF-8 (tildes y caracteres especiales)
  // Forzar el envío inmediato
  _speechSocket!.add(utf8.encode(message + messageEnd));
  _speechSocket!.flush();
}

void _sensorListen(void Function(String message) callback) {
  _sensorSocket?.listen(
    (event) {
      callback(utf8.decode(event).split(messageEnd)[0]);
    },
    onError: (error) => _log.severe("Sensor socket error: $error"),
    onDone: () => _log.warning("Sensor socket disconnected"),
  );
}

void addSensorCallback(void Function(String message) callback) {
  _sensorCallbacks.add(callback);
}

String getLastSensorValue() {
  return _lastSensorValue;
}

void _positionListen(void Function(String message) callback) {
  _positionSocket?.listen(
    (event) {
      callback(utf8.decode(event).split(messageEnd)[0]);
    },
    onError: (error) => _log.severe("Position socket error: $error"),
    onDone: () => _log.warning("Position socket disconnected"),
  );
}

void addPositionCallback(void Function(double x, double y, double angle) callback) {
  _positionCallbacks.add(callback);
}

/// Cierra todas las conexiones activas y limpia los callbacks
void disconnect() {
  _mainSocket?.close();
  _sensorSocket?.close();
  _speechSocket?.close();
  _positionSocket?.close();

  _mainSocket = null;
  _sensorSocket = null;
  _speechSocket = null;
  _positionSocket = null;

  _sensorCallbacks.clear();
  _positionCallbacks.clear();
  _lastSensorValue = "";
  _log.fine("Sockets disconnected and cleaned");
}