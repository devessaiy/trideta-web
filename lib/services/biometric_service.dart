import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/material.dart';

class BiometricService {
  final LocalAuthentication _auth = LocalAuthentication();

  // 🚨 FIX 1: encryptedSharedPreferences is now the permanent default!
  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(),
  );

  // 1. CHECK IF HARDWARE IS AVAILABLE
  Future<bool> isBiometricAvailable() async {
    try {
      bool canCheckBiometrics = await _auth.canCheckBiometrics;
      bool isDeviceSupported = await _auth.isDeviceSupported();
      return canCheckBiometrics && isDeviceSupported;
    } catch (e) {
      return false;
    }
  }

  // 2. SCAN FINGERPRINT
  Future<bool> authenticate() async {
    try {
      // 🚨 FIX 2: AuthenticationOptions removed; parameters are passed directly
      return await _auth.authenticate(
        localizedReason: 'Scan your fingerprint to login to TriDeta',
        persistAcrossBackgrounding: true, // Replaces stickyAuth
        biometricOnly: true,
      );
    } catch (e) {
      // 🚨 FIX 3: Catch all exceptions since local_auth now throws LocalAuthException
      debugPrint("Biometric Error: $e");
      return false;
    }
  }

  // 3. SAVE CREDENTIALS
  Future<void> saveCredentials(String email, String password) async {
    await _storage.write(key: 'email', value: email);
    await _storage.write(key: 'password', value: password);
  }

  // 4. GET CREDENTIALS
  Future<Map<String, String>?> getCredentials() async {
    String? email = await _storage.read(key: 'email');
    String? password = await _storage.read(key: 'password');

    if (email != null && password != null) {
      return {'email': email, 'password': password};
    }
    return null;
  }

  // 5. SAVE USER PREFERENCE
  Future<void> setBiometricEnabled(bool isEnabled) async {
    await _storage.write(key: 'biometric_enabled', value: isEnabled.toString());

    if (!isEnabled) {
      await deleteCredentials();
    }
  }

  // 6. CHECK USER PREFERENCE
  Future<bool> isBiometricEnabled() async {
    String? value = await _storage.read(key: 'biometric_enabled');
    return value == 'true';
  }

  // 7. DELETE CREDENTIALS
  Future<void> deleteCredentials() async {
    await _storage.delete(key: 'email');
    await _storage.delete(key: 'password');
    await _storage.delete(key: 'biometric_enabled');
  }
}
