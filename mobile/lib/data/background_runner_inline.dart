/// Browsers do not support Dart isolates. Yield before using the shared parser
/// so the loading state can be drawn, without downloading platform-only code.
Future<T> runBackground<T>(T Function() operation) => Future<T>(operation);
