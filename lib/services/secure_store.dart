import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

/// Encrypted files for everything Trideta keeps on the phone.
///
/// Data is encrypted with AES-256-GCM. The secret key is created on the
/// phone and kept in the phone's secure storage (Android Keystore / iOS
/// Keychain), never next to the data. GCM also detects any tampering: a file
/// that was edited or damaged simply fails to open and is treated as empty.
class SecureStore {
  SecureStore._();
  static final SecureStore instance = SecureStore._();

  static const String _keyName = 'trideta_local_data_key_v1';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final AesGcm _algo = AesGcm.with256bits();
  SecretKey? _key;

  Future<SecretKey?> _getKey() async {
    final existing = _key;
    if (existing != null) return existing;
    try {
      var b64 = await _storage.read(key: _keyName);
      if (b64 == null || b64.isEmpty) {
        final fresh = await _algo.newSecretKey();
        b64 = base64Encode(await fresh.extractBytes());
        await _storage.write(key: _keyName, value: b64);
      }
      return _key = SecretKey(base64Decode(b64));
    } catch (e) {
      debugPrint('Secure key unavailable: $e');
      return null;
    }
  }

  Future<File> _file(String name) async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$name');
  }

  /// Encrypts and saves text. Returns false if it could not be saved
  /// securely. It is never saved unencrypted as a fallback.
  Future<bool> writeText(String name, String text) async {
    final key = await _getKey();
    if (key == null) return false;
    try {
      final box = await _algo.encrypt(utf8.encode(text), secretKey: key);
      final f = await _file(name);
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsBytes(box.concatenation(), flush: true);
      await tmp.rename(f.path);
      return true;
    } catch (e) {
      debugPrint('Secure write failed ($name): $e');
      return false;
    }
  }

  /// Returns the decrypted text, or null if missing, damaged or tampered.
  Future<String?> readText(String name) async {
    final key = await _getKey();
    if (key == null) return null;
    try {
      final f = await _file(name);
      if (!await f.exists()) return null;
      final box = SecretBox.fromConcatenation(
        await f.readAsBytes(),
        nonceLength: 12,
        macLength: 16,
      );
      return utf8.decode(await _algo.decrypt(box, secretKey: key));
    } catch (e) {
      debugPrint('Secure read failed ($name): $e');
      return null;
    }
  }

  Future<String> hashName(String prefix, String input) async {
    final h = await Sha256().hash(utf8.encode(input));
    final hex = h.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '$prefix$hex.bin';
  }

  Future<void> deleteWithPrefix(String prefix) async {
    try {
      final dir = await getApplicationSupportDirectory();
      await for (final e in dir.list()) {
        final name = e.path.split(Platform.pathSeparator).last;
        if (e is File && name.startsWith(prefix)) await e.delete();
      }
    } catch (e) {
      debugPrint('Secure cleanup failed: $e');
    }
  }

  // ---- upgrade from the earlier unencrypted files -------------------------

  Future<String?> readLegacyPlain(String name) async {
    try {
      final f = await _file(name);
      if (await f.exists()) return await f.readAsString();
    } catch (_) {}
    return null;
  }

  /// Overwrites the old readable file with zeros, then deletes it.
  Future<void> wipeLegacy(String name) async {
    try {
      final f = await _file(name);
      if (await f.exists()) {
        final len = await f.length();
        await f.writeAsBytes(List<int>.filled(len, 0), flush: true);
        await f.delete();
      }
    } catch (_) {}
  }
}
