import 'dart:isolate';

Future<T> runBackground<T>(T Function() operation) => Isolate.run(operation);
