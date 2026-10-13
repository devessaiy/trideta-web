import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trideta_v2/services/secure_store.dart';
import 'package:trideta_v2/utils/resilient_request.dart';

/// Small encrypted copy on the phone of data the app already downloaded
/// (class lists, the school calendar) so screens can open when the internet
/// is down. One encrypted file per item. Everything is wiped on sign-out.
class LocalCache {
  static final Map<String, dynamic> _mem = {};
  static bool _migrated = false;

  static Future<void> _migrateLegacy() async {
    if (_migrated) return;
    _migrated = true;
    final text = await SecureStore.instance.readLegacyPlain(
      'trideta_cache.json',
    );
    if (text == null) return;
    try {
      final decoded = jsonDecode(text);
      var allSaved = true;
      if (decoded is Map) {
        for (final e in decoded.entries) {
          final name = await SecureStore.instance.hashName(
            'tc_',
            e.key.toString(),
          );
          final ok = await SecureStore.instance.writeText(
            name,
            jsonEncode(e.value),
          );
          if (!ok) allSaved = false;
        }
      }
      if (allSaved) await SecureStore.instance.wipeLegacy('trideta_cache.json');
    } catch (e) {
      debugPrint('LocalCache upgrade failed: $e');
    }
  }

  static Future<void> put(String key, Object? value) async {
    await _migrateLegacy();
    final text = jsonEncode(value);
    _mem[key] = jsonDecode(text); // private copy, same shape as from disk
    final name = await SecureStore.instance.hashName('tc_', key);
    await SecureStore.instance.writeText(name, text);
  }

  static Future<dynamic> get(String key) async {
    await _migrateLegacy();
    if (_mem.containsKey(key)) return _mem[key];
    final name = await SecureStore.instance.hashName('tc_', key);
    final text = await SecureStore.instance.readText(name);
    if (text == null) return null;
    try {
      return _mem[key] = jsonDecode(text);
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearAll() async {
    _mem.clear();
    await SecureStore.instance.deleteWithPrefix('tc_');
  }
}

enum _Login { ok, offline, revoked }

/// One saved-on-phone change that still has to reach Supabase.
class PendingJob {
  PendingJob({
    required this.id,
    required this.userId,
    required this.label,
    required this.table,
    required this.onConflict,
    required this.rows,
    required this.createdAt,
    this.status = 'pending',
    this.lastError,
  });

  final String id;
  final String userId;
  final String label;
  final String table;
  final String onConflict;
  final List<Map<String, dynamic>> rows;
  final DateTime createdAt;
  String status; // 'pending' or 'failed'
  String? lastError;

  Map<String, dynamic> toJson() => {
    'id': id,
    'userId': userId,
    'label': label,
    'table': table,
    'onConflict': onConflict,
    'rows': rows,
    'createdAt': createdAt.toIso8601String(),
    'status': status,
    'lastError': lastError,
  };

  factory PendingJob.fromJson(Map<String, dynamic> j) => PendingJob(
    id: j['id'] as String,
    userId: j['userId'] as String,
    label: (j['label'] ?? '') as String,
    table: j['table'] as String,
    onConflict: j['onConflict'] as String,
    rows: (j['rows'] as List)
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList(),
    createdAt: DateTime.parse(j['createdAt'] as String),
    status: (j['status'] ?? 'pending') as String,
    lastError: j['lastError'] as String?,
  );
}

/// Keeps saves that could not reach the server (weak or no internet) safely
/// on the phone and uploads them automatically later, in the order they were
/// made. Only saves that are safe to repeat (upserts on a fixed key) go in
/// here, so uploading twice can never create duplicates.
class OfflineQueue with WidgetsBindingObserver {
  OfflineQueue._();
  static final OfflineQueue instance = OfflineQueue._();

  static const _fileName = 'trideta_pending_saves.json';

  final ValueNotifier<int> pendingCount = ValueNotifier<int>(0);
  final ValueNotifier<int> failedCount = ValueNotifier<int>(0);

  final List<PendingJob> _jobs = [];
  Future<void>? _loading;
  bool _started = false;
  bool _flushing = false;

  String? get _userId => Supabase.instance.client.auth.currentUser?.id;

  /// Safe to call many times. Loads saved changes and starts the background
  /// upload (every 30 seconds while something is waiting, and whenever the
  /// app comes back to the foreground).
  Future<void> start() async {
    await ready();
    if (!_started) {
      _started = true;
      // Whenever anyone signs out (or the session ends), wipe the saved
      // copies of school data from this phone.
      Supabase.instance.client.auth.onAuthStateChange.listen((data) {
        if (data.event == AuthChangeEvent.signedOut) {
          LocalCache.clearAll();
          _updateCounts();
        }
      });
      WidgetsBinding.instance.addObserver(this);
      Timer.periodic(const Duration(seconds: 30), (_) => flush());
    }
    unawaited(flush());
  }

  Future<void> ready() => _loading ??= _loadFromDisk();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(flush());
  }

  static const _encName = 'trideta_pending_saves.enc';
  static const _legacyName = 'trideta_pending_saves.json';

  Future<void> _loadFromDisk() async {
    try {
      var text = await SecureStore.instance.readText(_encName);
      var fromLegacy = false;
      if (text == null) {
        // Upgrade: changes saved by an earlier version in a readable file.
        text = await SecureStore.instance.readLegacyPlain(_legacyName);
        fromLegacy = text != null;
      }
      if (text != null) {
        final decoded = jsonDecode(text);
        if (decoded is List) {
          for (final item in decoded) {
            try {
              _jobs.add(
                PendingJob.fromJson(Map<String, dynamic>.from(item as Map)),
              );
            } catch (e) {
              debugPrint('Skipped unreadable pending job: $e');
            }
          }
        }
      }
      if (fromLegacy && await _persist()) {
        await SecureStore.instance.wipeLegacy(_legacyName);
      }
    } catch (e) {
      debugPrint('Pending saves load failed: $e');
    }
    _updateCounts();
  }

  Future<bool> _persist() => SecureStore.instance.writeText(
    _encName,
    jsonEncode(_jobs.map((j) => j.toJson()).toList()),
  );

  void _updateCounts() {
    final uid = _userId;
    pendingCount.value = _jobs
        .where((j) => j.userId == uid && j.status == 'pending')
        .length;
    failedCount.value = _jobs
        .where((j) => j.userId == uid && j.status == 'failed')
        .length;
  }

  /// Saves a change on the phone to be uploaded later.
  Future<void> enqueueUpsert({
    required String label,
    required String table,
    required String onConflict,
    required List<Map<String, dynamic>> rows,
  }) async {
    await ready();
    final uid = _userId;
    if (uid == null) throw StateError('Not signed in');
    _jobs.add(
      PendingJob(
        id: newRequestId(),
        userId: uid,
        label: label,
        table: table,
        onConflict: onConflict,
        rows: rows,
        createdAt: DateTime.now(),
      ),
    );
    await _persist();
    _updateCounts();
  }

  /// Rows that are saved on this phone but not yet on the server. Used so a
  /// screen can show them instead of the older server copy.
  List<Map<String, dynamic>> queuedRows(String table) {
    final uid = _userId;
    final out = <Map<String, dynamic>>[];
    for (final j in _jobs) {
      if (j.userId == uid && j.table == table) out.addAll(j.rows);
    }
    return out;
  }

  /// Called after a save reached the server directly. Any older copy of the
  /// same rows still waiting on the phone is now out of date, so it is
  /// removed. Without this, the old copy could upload later and overwrite
  /// the newer one.
  Future<void> dropSuperseded({
    required String table,
    required List<Map<String, dynamic>> savedRows,
    required String Function(Map<String, dynamic> row) keyOf,
  }) async {
    await ready();
    final uid = _userId;
    final saved = savedRows.map(keyOf).toSet();
    var changed = false;
    for (final j in List<PendingJob>.of(_jobs)) {
      if (j.userId != uid || j.table != table) continue;
      final before = j.rows.length;
      j.rows.removeWhere((r) => saved.contains(keyOf(r)));
      if (j.rows.length != before) {
        changed = true;
        if (j.rows.isEmpty) _jobs.remove(j);
      }
    }
    if (changed) {
      await _persist();
      _updateCounts();
    }
  }

  List<PendingJob> get failedJobs {
    final uid = _userId;
    return _jobs.where((j) => j.userId == uid && j.status == 'failed').toList();
  }

  bool _shouldRetryLater(Object e) {
    if (isTransientError(e) || e is AuthException) return true;
    if (e is PostgrestException) {
      return e.code == 'PGRST301' || e.message.toLowerCase().contains('jwt');
    }
    return false;
  }

  /// Uploads waiting changes, oldest first. Stops quietly when the internet
  /// is still down. A change the server refuses is kept and flagged, never
  /// silently thrown away.
  Future<void> flush() async {
    if (_flushing) return;
    await ready();
    final uid = _userId;
    if (uid == null) return;
    if (!_jobs.any((j) => j.userId == uid && j.status == 'pending')) return;

    _flushing = true;
    try {
      for (final job in List<PendingJob>.of(_jobs)) {
        if (job.userId != uid || job.status != 'pending') continue;
        try {
          await Supabase.instance.client
              .from(job.table)
              .upsert(job.rows, onConflict: job.onConflict)
              .timeout(const Duration(seconds: 30));
          _jobs.remove(job);
          await _persist();
          _updateCounts();
        } catch (e) {
          if (_isLoginProblem(e)) {
            final state = await _refreshLogin();
            if (state == _Login.revoked) {
              // The account was removed, suspended or signed out by the
              // server: nothing from it may reach the school, and nothing
              // of it stays on this phone.
              await purgeUser(uid);
              await LocalCache.clearAll();
            }
            break; // refreshed (next round succeeds) or still offline
          }
          if (_shouldRetryLater(e)) break; // still offline: try again later
          job.status = 'failed';
          job.lastError = e.toString();
          await _persist();
          _updateCounts();
        }
      }
    } finally {
      _flushing = false;
    }
  }

  bool _isLoginProblem(Object e) {
    if (e is AuthException) return true;
    if (e is PostgrestException) {
      return e.code == 'PGRST301' || e.message.toLowerCase().contains('jwt');
    }
    return false;
  }

  Future<_Login> _refreshLogin() async {
    try {
      await Supabase.instance.client.auth.refreshSession();
      return _Login.ok;
    } catch (e) {
      if (isTransientError(e)) return _Login.offline;
      final s = e.toString().toLowerCase();
      const definite = [
        'banned',
        'user not found',
        'user_not_found',
        'refresh_token_not_found',
        'invalid refresh token',
        'session_not_found',
      ];
      return definite.any(s.contains) ? _Login.revoked : _Login.offline;
    }
  }

  /// Removes everything this account still had waiting on the phone.
  Future<void> purgeUser(String userId) async {
    _jobs.removeWhere((j) => j.userId == userId);
    await _persist();
    _updateCounts();
  }

  Future<void> retryFailed() async {
    final uid = _userId;
    for (final j in _jobs) {
      if (j.userId == uid && j.status == 'failed') {
        j.status = 'pending';
        j.lastError = null;
      }
    }
    await _persist();
    _updateCounts();
    unawaited(flush());
  }

  Future<void> discardFailed() async {
    final uid = _userId;
    _jobs.removeWhere((j) => j.userId == uid && j.status == 'failed');
    await _persist();
    _updateCounts();
  }
}
