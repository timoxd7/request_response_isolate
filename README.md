# Isolate Locker

This is a mutex-kind locker for isolate-wide locking. You can create an IsolateLocker (mutex) which then
can Create Locks, which are given to each isolate that should be able to lock the resource.

For me, it is mainly used that only one Isolate can write to a Database at a time. Still, every
isolate has its own Database, but only one can write to it by requesting a lock.

If you want to terminate an Isolate using a Lock or even the main isolate itself, see the
attached example.

## Usage

In your main thread, create an IsolateLocker

    var isolateLocker = IsolateLocker();

Then, request a Locker for a new Isolate

    var newLocker = await isolateLocker.requestNewLocker();

Pass this new Locker to a new Isolate (over the SendPort or as init value or part of the init value)
After this, the Isolate can access the Locker as followed:

    await locker.request();
    // This code will only be executed after the Lock was exclusively given to this Locker
    locker.release(); // -> Needed to allow another Locker to request a new lock

For more save code, you can use this function caller. With this, you can't forget to release the lock,
as it is released automatically!

    await locker.protect(() {
      // Your code...
    });

## Program Termination

If you want to terminate the Program, all isolates having a Locker need to kill this locker with

    locker.kill();

And in the main isolate, where the IsolateLocker were created, it also needs to be killed

    isolateLocker.kill();

Only if all Isolates killed its Locker, the IsolateLocker will kill itself and its attached Isolate.