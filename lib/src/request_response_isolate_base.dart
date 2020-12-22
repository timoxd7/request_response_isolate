import 'dart:async';
import 'dart:isolate';
import 'package:mutex/mutex.dart';

class Requester<Request, Response> {
  SendPort _responderSendPort;
  bool _dead = false;

  /// Besides the lock between the independent isolates, there also needs to be
  /// a Lock between async code in the same Isolate. To lock them against each
  /// other, using a Mutex from the mutex package is the best way.
  Mutex _m = Mutex();

  /// Awaiting this Future, you can Lock the specific IsolateLocker to
  /// exclusively use it. Use just with "await" to wait for the lock to be
  /// accepted
  Future<Response> request(Request request) async {
    if (_dead) return null;

    await _m.acquire();

    ___RequestCapsule<Request> requestCapsule = ___RequestCapsule<Request>();
    var newReceivePort = ReceivePort();
    requestCapsule.request = request;
    requestCapsule.responsePort = newReceivePort.sendPort;

    Future<Response> responseListener() async {
      Response gotResponse;

      await for (dynamic message in newReceivePort) {
        if (message is Response) {
          gotResponse = message;
          newReceivePort.close();
          break;
        }
      }

      return gotResponse;
    }

    var responseFuture = responseListener();
    _responderSendPort.send(requestCapsule);
    var response = await responseFuture;
    return response;
  }

  /// Only if the Isolate should be terminated! This will render this Locker
  /// permanently useless. Only use if all sync and async code which could
  /// use this Locker is fully completed!
  void kill() async {
    await _m.acquire();

    ___KillRequest message = ___KillRequest();
    message.action = true;
    _responderSendPort.send(message);
    _dead = true;

    _m.release();
  }

  bool isDead() {
    return _dead;
  }
}

class ___SendPortRequest {
  bool action =
      true; // true == get new SendPort, false == kill this ReceivePort
}

class ___KillRequest {
  bool action = true; // true == kill
}

class ___ResponderConf<Request, Response> {
  SendPort mainSendPort;
  Response Function(Request) callback;
}

class ___RequestCapsule<Request> {
  SendPort responsePort;
  Request request;
}

void _responderIsolateFunc<Request, Response>(
    ___ResponderConf<Request, Response> conf) {
  ReceivePort receivePort = ReceivePort();
  int openPortCount = 0;

  bool killRequested = false;

  void tryKillMe() {
    if (openPortCount == 0 && killRequested) {
      ___KillRequest killRequest = ___KillRequest();
      killRequest.action = true;
      conf.mainSendPort.send(killRequest);
      receivePort.close();
    }
  }

  receivePort.listen((dynamic message) {
    // Listening from the main isolate (or creater isolate)
    if (killRequested) return;

    if (message is ___SendPortRequest) {
      ___SendPortRequest request = message;

      if (request.action == true) {
        var newReceivePort = ReceivePort();

        newReceivePort.listen((message) {
          // Listening from a Requester
          if (message is ___RequestCapsule<Request>) {
            ___RequestCapsule<Request> requestCapsule = message;
            Response response = conf.callback(requestCapsule.request);
            requestCapsule.responsePort.send(response);
          } else if (message is ___KillRequest) {
            ___KillRequest killRequest = message;

            if (killRequest.action == true) {
              newReceivePort.close();
              openPortCount--;
            }

            tryKillMe();
          }
        });

        conf.mainSendPort.send(newReceivePort.sendPort);
        openPortCount++;
      }
    } else if (message is ___KillRequest) {
      ___KillRequest killRequest = message;

      if (killRequest.action == true) {
        killRequested = true;

        tryKillMe();
      }
    }
  });

  conf.mainSendPort.send(receivePort.sendPort);
}

class Responder<Request, Response> {
  SendPort _responderSendPort;
  final _responderReceivePort = ReceivePort();
  final _responderSendPortCompleter = Completer();
  var _newResponderCompleter = Completer();
  bool _dead = false;
  Mutex _m = Mutex();

  /// Create a new IsolateLocker to lock something globally
  Responder(Response Function(Request) callback) {
    void _isolateListener() async {
      await for (dynamic message in _responderReceivePort) {
        if (message is SendPort) {
          if (_responderSendPort == null) {
            // Use first sendPort for the communication with main
            _responderSendPort = message;
            print("Responder set up");
            _responderSendPortCompleter.complete();
          } else {
            Requester<Request, Response> newRequester =
                Requester<Request, Response>();
            newRequester._responderSendPort = message;
            _newResponderCompleter.complete(newRequester);
          }
        } else if (message is ___KillRequest) {
          ___KillRequest killRequest = message;
          if (killRequest.action == true) _responderReceivePort.close();
        }
      }
    }

    _isolateListener();
    ___ResponderConf<Request, Response> responderConf =
        ___ResponderConf<Request, Response>();
    responderConf.callback = callback;
    responderConf.mainSendPort = _responderReceivePort.sendPort;
    Isolate.spawn(_responderIsolateFunc, responderConf);
  }

  /// Get a new Locker to pass to a new Isolate which then can Lock the
  /// IsolateLocker once it needs a specific resource.
  Future<Requester<Request, Response>> requestNewRequester() async {
    if (_dead) return null;

    await _m.acquire();

    await _responderSendPortCompleter.future;

    _newResponderCompleter = Completer();
    var sendPortRequest = ___SendPortRequest();
    sendPortRequest.action = true;
    _responderSendPort.send(sendPortRequest);
    Requester newRequester = await _newResponderCompleter.future;

    _m.release();

    return newRequester;
  }

  /// Kill the IsolateLocker. This only gives a Signal to the Isolate Locker.
  /// The Kill will only be executed if all Locks also have been killed.
  /// This will Render this IsolateLocker useless!
  void kill() {
    ___KillRequest _killRequest = ___KillRequest();
    _killRequest.action = true;
    _responderSendPort.send(_killRequest);
    _dead = true;
  }
}
