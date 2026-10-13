import 'package:trideta_v2/services/offline_queue.dart';
import 'package:trideta_v2/utils/resilient_request.dart';

/// Reads data with the phone's saved copy as a safety net.
///
/// - If a saved copy is younger than [fresh], it is returned at once and no
///   request is sent (fast, and lighter on your Supabase free tier).
/// - Otherwise the server is asked, with a time limit. The answer is saved
///   for next time.
/// - If the server cannot be reached, the last saved copy is returned, so the
///   screen still opens offline. With no saved copy the error is passed on.
class ReadThrough {
  static DateTime _epoch = DateTime.fromMillisecondsSinceEpoch(0);

  /// Call after something changes (for example the classes were edited) so
  /// short-lived saved copies are not used.
  static void invalidateAll() => _epoch = DateTime.now();
}

Future<T> readThrough<T>(
  String key,
  Future<T> Function() fetch, {
  Duration fresh = Duration.zero,
}) async {
  final cacheKey = 'rt:$key';
  final raw = await LocalCache.get(cacheKey);
  final Map? entry = raw is Map && raw.containsKey('data') ? raw : null;

  if (entry != null && fresh > Duration.zero) {
    final at = DateTime.tryParse('${entry['at']}');
    if (at != null &&
        at.isAfter(ReadThrough._epoch) &&
        DateTime.now().difference(at) < fresh) {
      return _coerce<T>(entry['data']);
    }
  }

  try {
    // With a saved copy to fall back on, don't wait long on a weak network.
    final data = await retryRead(
      fetch,
      maxAttempts: entry != null ? 1 : 2,
      timeout: Duration(seconds: entry != null ? 6 : 12),
    );
    await LocalCache.put(cacheKey, {
      'at': DateTime.now().toIso8601String(),
      'data': data,
    });
    return data;
  } catch (e) {
    if (entry != null) return _coerce<T>(entry['data']);
    rethrow;
  }
}

T _coerce<T>(dynamic d) {
  if (d is List) {
    return d.map((x) => Map<String, dynamic>.from(x as Map)).toList() as T;
  }
  if (d is Map) return Map<String, dynamic>.from(d) as T;
  return d as T;
}
