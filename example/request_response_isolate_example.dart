import 'package:request_response_isolate/request_response_isolate.dart';
import 'dart:isolate';

const int requesterAmount = 1;
const int waitTime = 0;

class MyRequest {
  // Can be any Data
  int requestId;
}

class MyResponse {
  // Can be any Data too
  String requestIdString;
}

class RequesterConf {
  Requester<MyRequest, MyResponse> requester;
  int id;
}

void main() async {
  Responder<MyRequest, MyResponse> responder =
      Responder<MyRequest, MyResponse>(responderFunc);

  for (var i = 0; i < requesterAmount; i++) {
    print("C Creating Requester " + i.toString());

    RequesterConf requesterConf = RequesterConf();

    requesterConf.requester = await responder.requestNewRequester();
    requesterConf.id = i;

    Isolate.spawn(requesterIsolateFunc, requesterConf);
  }

  responder.kill();
}

MyResponse responderFunc(MyRequest request) {
  MyResponse response = MyResponse();
  response.requestIdString = request.requestId.toString();
  return response;
}

void requesterIsolateFunc(RequesterConf conf) async {
  print("R Requesting ${conf.id}");

  MyRequest request = MyRequest();
  request.requestId = conf.id;

  MyResponse response = await conf.requester.request(request);
  print("R Got Response: ${response.requestIdString}");

  conf.requester.kill();
}
