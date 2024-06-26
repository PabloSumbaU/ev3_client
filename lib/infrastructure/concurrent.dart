import "dart:async";
import "dart:isolate";

class _IsolateArgs<T, R> {
  _IsolateArgs(this.sendPort, this.runnable, this.portCallback, this.setWorkerState, this.getWorkerState);

  final SendPort sendPort;
  final void Function(SendPort, ReceivePort, WorkerState Function()) runnable;
  final R Function(T) portCallback;
  final void Function(WorkerState newState) setWorkerState;
  final WorkerState Function() getWorkerState;
}

class Worker<T, R> {
  Worker._(this._responses, this._commands, void Function(R)? portCallback, this._setWorkerState, this._getWorkerState) {
    _responses.listen((message) {
      final (id, result) = message as (int, R);
      final completer = _activeRequests.remove(id)!;

      if (result is RemoteError) {
        completer.completeError(result);
      } else {
        portCallback?.call(result);
        completer.complete(result);
      }
    });
  }

  final ReceivePort _responses;
  final SendPort _commands;
  final Map<int, Completer<R>> _activeRequests = {};
  int _idCounter = 0;
  final void Function(WorkerState newState) _setWorkerState;
  final WorkerState Function() _getWorkerState;

  WorkerState get state => _getWorkerState();

  /// Creates a new instance of a Worker. This method will attempt to spawn a new isolate to run the given `runnable` function.
  /// `mainListener` will be called on the main isolate when a message is received from the worker isolate. Conversely,
  /// `workerListener` will be called on the worker isolate when a message is received from the main isolate.
  /// In order to gracefully terminate the worker isolate, verify the [state] of the worker inside the `runnable` function.
  /// If the state is `WorkerState.terminated`, the function should exit.
  static Future<Worker> getInstance<T, R>(
    void Function(SendPort sendPort, ReceivePort receivePort, WorkerState Function() workerState) runnable,
    R Function(T data) workerListener,
    [void Function(R result)? mainListener]
  ) async {
    var workerState = WorkerState.initializing;
    void setState(WorkerState newState) => workerState = newState;
    getState() => workerState;
    
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
      Isolate.spawn(_runIsolate<T, R>, _IsolateArgs<T, R>(initPort.sendPort, runnable, workerListener, setState, getState));
    } on Object {
      //If failed, close the port and rethrow
      initPort.close();
      rethrow;
    }

    //Wait for the connection to complete and destructure the ports
    final (receivePort, sendPort) = await connection.future;

    //Return instance of Worker
    return Worker<T, R>._(receivePort, sendPort, mainListener, setState, getState);
  }

  static void _runIsolate<T, R>(_IsolateArgs<T, R> args) {
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
      if (message is _ShutdownCommand) {
        receivePort.close();
        if (message.forceShutdown) {
          Isolate.exit();
        }
        return;
      }

      final (int id, T data) = message as (int, T);

      try {
        final R result = args.portCallback(data);
        sendPort.send((id, result));
      } catch (e) {
        sendPort.send((id, RemoteError(e.toString(), '')));
      }
    });

    //Runs the main process for the worker isolate
    args.runnable(sendPort, receivePort, args.getWorkerState);
  }

  /// Sends a message from the [main] isolate to the [worker] isolate. Will wait for the response from the [worker] isolate.
  /// If a `mainListener` was provided on the constructor, it will be called with the result passed as an argument before
  /// the result is returned from this method, whether the callback modifies the result or not is up to the programmer.
  Future<R> send(T message) async {
    if (state == WorkerState.terminated) {
      throw StateError("Connection has been closed!");
    }
    //Completer that will hold the result of the request
    //This along with the ID ensures that the values will be returned in the same order that they were sent
    final completer = Completer<R>.sync();
    final id = _idCounter++;
    _activeRequests[id] = completer;

    _commands.send((id, message));

    return await completer.future;
  }

  /// Terminates the worker isolate. If the optional argument `force` is true, the isolate will be forcefully terminated.
  void terminate([bool force = false]) {
    if (state != WorkerState.terminated) {
      _setWorkerState(WorkerState.terminated);
      _commands.send(_ShutdownCommand(force));

      if (_activeRequests.isEmpty) {
        _responses.close();
      }
    }
  }
}

class _ShutdownCommand {
  _ShutdownCommand(this.forceShutdown);
  
  final bool forceShutdown;
}

enum WorkerState {
  initializing, running, terminated
}