# Request Response Isolate

This is a simple library to simplify the use with Isolates.

It just needs a handler function, which then handles some task in a dedicated isolate.

It es meant to be used for multiple isolates, each sending requests to a unique Isolates managing global data.

For Example, you can write a Handler, which responds with User IDs which are globally used and so can not be handled by an isolate itself.

## Usage

See the Example.

In your main thread, create an Responder which takes a handler which will handle all Requests in its own Isolate. The Handler Function needs to return a Future<dynamic> and should be async. The Requests will be given as parameter and also of type dynamic. Casting is important to be done in the handler!

    var responder = Responder(handlerFunc);

    // ...

    Future<dynamic> handlerFunc(dynamic request) async {
        // ...

        return response;
    }

Then, request a Requester for a new Isolate

    var newRequester = await responder.requestNewRequester();

Pass this new Requester to a new Isolate (over the SendPort or as init value or part of the init value)
After this, the Isolate can make Requests as followed (Request and Response as String):

    YourResponseType response = await requester.request(YourRequestType request);

The Request and Response type can be any class you wish.

## Program Termination

If you want to terminate the Program, all isolates having a Requester need to kill this Requester with

    requester.kill();

And in the main isolate, where the Responder were created, it also needs to be killed

    responder.kill();

Only if all Isolates killed its Requester, the Responder will kill itself and its attached Isolate.