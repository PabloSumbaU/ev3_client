import "dart:async";
import "dart:isolate";

class _IsolateArgs<T> {
  _IsolateArgs(this.sendPort, this.runnable, this.portCallback);

  final SendPort sendPort;
  final void Function(SendPort, ReceivePort) runnable;
  final void Function(T) portCallback;
}

class Worker {
  Worker._(this._responses, this._commands, portCallback) {
    _responses.listen(portCallback);
  }

  ReceivePort _responses;
  SendPort _commands;
  Completer _isolateReady = Completer();

  /// Creates a new instance of a Worker. This method will attempt to spawn a new isolate to run the given `runnable` function.
  /// `mainListener` will be called on the main isolate when a message is received from the worker isolate. Conversely,
  /// `workerListener` will be called on the worker isolate when a message is received from the main isolate.
  static Future<Worker> getInstance<T>(
    void Function(SendPort, ReceivePort) runnable,
    void Function(T) mainListener, 
    void Function(T) workerListener
  ) async {
    //RawReceivePort so we can perform the initial handshake between isolates to exchange ports
    final initPort = RawReceivePort();
    //Completer that will hold a record of the ReceivePort and SendPort for the MAIN isolate
    final connection = Completer<(ReceivePort, SendPort)>.sync();
    
    //Handles first message sent by the worker isolate
    initPort.handler = (message) {
      final commandPort = message as SendPort;

      //Connection completes, now holding the ReceivePort and SendPort
      connection.complete((ReceivePort.fromRawReceivePort(initPort), commandPort));
    };

    try {
      //Attempt to spawn the worker isolate
      Isolate.spawn(_runIsolate, _IsolateArgs<T>(initPort.sendPort, runnable, workerListener));
    } on Object {
      //If failed, close the port and rethrow
      initPort.close();
      rethrow;
    }

    //Wait for the connection to complete and destructure the ports
    final (receivePort, sendPort) = await connection.future;

    //Return instance of Worker
    return Worker._(receivePort, sendPort, mainListener);
  }

  void send(dynamic message) async {
    await _isolateReady.future;
    _commands.send(message);
  }

  static void _runIsolate(_IsolateArgs args) {
    //This code runs on the worker isolate

    //Creates the ReceivePort for the WORKER isolate
    final receivePort = ReceivePort();
    //Gets the SendPort passed from the main isolate
    final sendPort = args.sendPort;

    //Sends the ReceivePort reference back to the main isolate
    sendPort.send(receivePort);

    //Registers the worker isolate receiver callback:
    //When a message from the main isolate is received, attempts to run the callback, if an error occurs, sends it back to the
    //main isolate in the form of a RemoteError
    receivePort.listen((message) {
      try {
        args.portCallback(message);
      } catch (e) {
        sendPort.send(RemoteError(e.toString(), ''));
      }
    });

    //Runs the main process for the worker isolate
    args.runnable(sendPort, receivePort);
  }
}