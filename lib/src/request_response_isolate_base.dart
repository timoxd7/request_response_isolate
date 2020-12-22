import 'dart:async';
import 'dart:isolate';
import 'package:mutex/mutex.dart';

class Requester {
  SendPort _responderSendPort;
  bool _dead = false;
  Mutex _m = Mutex();

  /// Make a new Request and wait for the Response
  Future<dynamic> request(dynamic request) async {
    if (_dead) return null;

    await _m.acquire();

    ___RequestCapsule requestCapsule = ___RequestCapsule();
    var newReceivePort = ReceivePort();
    requestCapsule.request = request;
    requestCapsule.responsePort = newReceivePort.sendPort;

    Future<dynamic> responseListener() async {
      dynamic gotResponse;

      await for (dynamic message in newReceivePort) {
        gotResponse = message;
        newReceivePort.close();
        break;
      }

      return gotResponse;
    }

    var responseFuture = responseListener();
    _responderSendPort.send(requestCapsule);
    var response = await responseFuture;

    _m.release();
    return response;
  }

  /// Only if the Isolate should be terminated! This will render this Requester
  /// permanently useless. Only use if all sync and async code which could
  /// use this Requester is fully completed!
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

// Some Helper Classes

class ___SendPortRequest {
  bool action = true; // true == get new SendPort
}

class ___KillRequest {
  bool action = true; // true == kill
}

class ___ResponderConf {
  SendPort mainSendPort;
  Future<dynamic> Function(dynamic) callback;
}

class ___RequestCapsule {
  SendPort responsePort;
  dynamic request;
}

// Needed internally by the Responder Isolate to handle requests
void _responderIsolateFunc(___ResponderConf conf) {
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

        newReceivePort.listen((message) async {
          // Listening from a Requester
          if (message is ___KillRequest) {
            ___KillRequest killRequest = message;

            if (killRequest.action == true) {
              newReceivePort.close();
              openPortCount--;
            }

            tryKillMe();
          } else if (message is ___RequestCapsule) {
            ___RequestCapsule requestCapsule = message;
            dynamic response = await conf.callback(requestCapsule.request);
            requestCapsule.responsePort.send(response);
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

class Responder {
  SendPort _responderSendPort;
  final _responderReceivePort = ReceivePort();
  final _responderSendPortCompleter = Completer();
  var _newResponderCompleter = Completer();
  bool _dead = false;
  Mutex _m = Mutex();

  /// Create a new Responder to request some globally needed Data from an
  /// Isolate. Using a Request-Response-Syntax, you can get globally sync
  /// Data within any Isolate.
  Responder(Future<dynamic> Function(dynamic) callback) {
    void _isolateListener() async {
      await for (dynamic message in _responderReceivePort) {
        if (message is SendPort) {
          if (_responderSendPort == null) {
            // Use first sendPort for the communication with main
            _responderSendPort = message;
            print("Responder set up");
            _responderSendPortCompleter.complete();
          } else {
            Requester newRequester = Requester();
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
    ___ResponderConf responderConf = ___ResponderConf();
    responderConf.callback = callback;
    responderConf.mainSendPort = _responderReceivePort.sendPort;
    Isolate.spawn(_responderIsolateFunc, responderConf);
  }

  /// Get a new Requester to pass to a new Isolate which then can make Requests
  /// to get globally synced data.
  Future<Requester> requestNewRequester() async {
    await _m.acquire();

    if (_dead) return null;

    await _responderSendPortCompleter.future;

    _newResponderCompleter = Completer();
    var sendPortRequest = ___SendPortRequest();
    sendPortRequest.action = true;
    _responderSendPort.send(sendPortRequest);
    Requester newRequester = await _newResponderCompleter.future;

    _m.release();

    return newRequester;
  }

  /// Kill the Responder. This only gives a Signal to the Responder Isolate.
  /// The Kill will only be executed if all Requesters also have been killed.
  /// This will Render this Responder useless!
  void kill() async {
    await _m.acquire();

    if (_dead) return null;

    await _responderSendPortCompleter.future;

    ___KillRequest killRequest = ___KillRequest();
    killRequest.action = true;
    _responderSendPort.send(killRequest);
    _dead = true;
  }
}
