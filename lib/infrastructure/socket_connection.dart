import 'dart:io';
import 'dart:convert' show utf8;
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

final _log = Logger("Socket Connection");

Socket? _mainSocket;
Socket? _sensorSocket;
Socket? _speechSocket;
Socket? _positionSocket;

final List<void Function(String message)> _sensorCallbacks = [];
String _lastSensorValue = "";
final List<void Function(double x, double y, double angle)> _positionCallbacks = [];

const messageEnd = "|";

/// Se pone en true si el robot cierra la conexión (p. ej. se apagó).
final ValueNotifier<bool> connectionLost = ValueNotifier(false);

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
  connectionLost.value = false;
  try {
    _mainSocket = await Socket.connect(ipAddress, port, timeout: const Duration(seconds: 10));
    _mainSocket!.setOption(SocketOption.tcpNoDelay, true);
    _log.fine("Main socket connection established");

    _sensorSocket = await Socket.connect(ipAddress, sensorPort, timeout: const Duration(seconds: 10));
    _log.fine("Sensor socket connection established");

    _speechSocket = await Socket.connect(ipAddress, speechPort, timeout: const Duration(seconds: 10));
    _speechSocket!.setOption(SocketOption.tcpNoDelay, true);
    _log.fine("Speech socket connection established");

    _positionSocket = await Socket.connect(ipAddress, positionPort, timeout: const Duration(seconds: 10));
    _log.fine("Position socket connection established");

    _listenMessages(_sensorSocket!, "Sensor", (message) {
      _lastSensorValue = message;
      for (var callback in List.of(_sensorCallbacks)) {
        callback(message);
      }
    });

    _listenMessages(_positionSocket!, "Position", (message) {
      try {
        List<String> parts = message.split(";");
        if (parts.length >= 3) {
          double x = double.parse(parts[0]);
          double y = double.parse(parts[1]);
          double angle = double.parse(parts[2]);
          for (var callback in List.of(_positionCallbacks)) {
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

/// Escucha un socket y entrega solo el ÚLTIMO mensaje completo de cada lote
/// (los datos de sensor/posición viejos no sirven).
void _listenMessages(Socket socket, String name, void Function(String) callback) {
  var buffer = "";
  socket.listen(
    (event) {
      buffer += utf8.decode(event, allowMalformed: true);
      final parts = buffer.split(messageEnd);
      buffer = parts.removeLast();
      final complete = parts.where((p) => p.isNotEmpty);
      if (complete.isNotEmpty) callback(complete.last);
    },
    onError: (error) => _log.severe("$name socket error: $error"),
    onDone: () {
      _log.warning("$name socket disconnected");
      if (_mainSocket != null) connectionLost.value = true;
    },
  );
}

/// Envía comandos de movimiento al socket principal
void send(String message) {
  if (_mainSocket == null) {
    _log.warning("Main socket is null. Message not sent.");
    return;
  }
  _log.finer("Message sent to main socket: $message");
  try {
    _mainSocket!.add(utf8.encode(message + messageEnd));
  } catch (e) {
    _log.severe("Error sending: $e");
  }
}

/// Envía instrucciones de texto (voz o botones): p. ej. "f-20-cm;l;g".
void sendInstructions(String instructions) {
  if (instructions.isEmpty) return;
  send("text:$instructions");
}

/// Envía texto para ser reproducido por voz en el parlante del robot
void sendSpeech(String message) {
  if (_speechSocket == null) {
    _log.warning("Speech socket is null. Speech message not sent.");
    return;
  }
  final clean = message.replaceAll(messageEnd, " ").trim();
  if (clean.isEmpty) return;
  _log.fine("Message sent to speech socket: $clean");
  try {
    _speechSocket!.add(utf8.encode(clean + messageEnd));
  } catch (e) {
    _log.severe("Error sending speech: $e");
  }
}

void addSensorCallback(void Function(String message) callback) {
  _sensorCallbacks.add(callback);
}

void removeSensorCallback(void Function(String message) callback) {
  _sensorCallbacks.remove(callback);
}

String getLastSensorValue() {
  return _lastSensorValue;
}

void addPositionCallback(void Function(double x, double y, double angle) callback) {
  _positionCallbacks.add(callback);
}

/// Cierra todas las conexiones activas y limpia los callbacks
void disconnect() {
  final sockets = [_mainSocket, _sensorSocket, _speechSocket, _positionSocket];
  _mainSocket = null;
  _sensorSocket = null;
  _speechSocket = null;
  _positionSocket = null;
  for (final s in sockets) {
    try {
      s?.destroy();
    } catch (_) {}
  }

  _sensorCallbacks.clear();
  _positionCallbacks.clear();
  _lastSensorValue = "";
  _log.fine("Sockets disconnected and cleaned");
}
