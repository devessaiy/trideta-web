import 'dart:async';
import 'dart:math';

/// True for errors that are worth retrying: weak or dropped internet,
/// timeouts, and temporary server hiccups. Everything else (permission
/// errors, bad data, missing rows) is NOT retried so real bugs still show up.
bool isTransientError(Object e) {
  if (e is TimeoutException) return true;
  final s = e.toString().toLowerCase();
  return s.contains('socketexception') ||
      s.contains('clientexception') ||
      s.contains('handshakeexception') ||
      s.contains('authretryablefetchexception') ||
      s.contains('failed host lookup') ||
      s.contains('connection closed') ||
      s.contains('connection reset') ||
      s.contains('connection refused') ||
      s.contains('connection timed out') ||
      s.contains('network is unreachable') ||
      RegExp(r'\b(502|503|504)\b').hasMatch(s);
}

/// Runs a READ request with a timeout and automatic retries (waiting a bit
/// longer between each try). Use this only for reads or for requests that are
/// safe to repeat. Never use it for plain inserts, because a retry could
/// create duplicates.
Future<T> retryRead<T>(
  Future<T> Function() request, {
  int maxAttempts = 3,
  Duration timeout = const Duration(seconds: 15),
  Duration baseDelay = const Duration(milliseconds: 800),
}) async {
  var attempt = 0;
  while (true) {
    attempt++;
    try {
      return await request().timeout(timeout);
    } catch (e) {
      if (attempt >= maxAttempts || !isTransientError(e)) rethrow;
      await Future.delayed(baseDelay * (1 << (attempt - 1)));
    }
  }
}

/// Same as [retryRead], for WRITES that are safe to repeat (for example a
/// save that carries its own unique request id, or an upsert on a fixed id).
/// A repeat of the same request can never create a duplicate.
Future<T> retryIdempotent<T>(
  Future<T> Function() request, {
  int maxAttempts = 3,
  Duration timeout = const Duration(seconds: 20),
}) =>
    retryRead(request, maxAttempts: maxAttempts, timeout: timeout);

/// Creates a random unique id (UUID v4) on the device. Used so that a retried
/// save is recognised by the database instead of being recorded twice.
String newRequestId() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  String x(int i) => b[i].toRadixString(16).padLeft(2, '0');
  return '${x(0)}${x(1)}${x(2)}${x(3)}-${x(4)}${x(5)}-${x(6)}${x(7)}-'
      '${x(8)}${x(9)}-${x(10)}${x(11)}${x(12)}${x(13)}${x(14)}${x(15)}';
}
