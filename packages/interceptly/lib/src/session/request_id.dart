/// Generates unique IDs for captured requests.
///
/// Using [DateTime.now().microsecondsSinceEpoch] alone is unsafe: Dart's event
/// loop can schedule multiple async continuations within the same microsecond,
/// producing duplicate timestamps. A monotonically-increasing counter paired
/// with the timestamp guarantees uniqueness for the lifetime of the process.
///
/// Safe without a lock: all [InspectorSession.record] calls originate from the
/// main isolate's single-threaded event loop, so increments never race.
abstract final class RequestId {
  static int _counter = 0;

  static String generate() {
    final ts = DateTime.now().microsecondsSinceEpoch;
    final seq = _counter++;
    return '${ts}_$seq';
  }
}
