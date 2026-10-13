import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:local_auth/local_auth.dart';

/// Set this to true ONLY if you decide that phones with no screen lock at
/// all should be allowed into protected modules.
const bool kAllowWhenNoScreenLock = false;

bool get _isPhone =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

/// Asks the user to unlock with their phone's screen lock (fingerprint, face,
/// PIN, pattern or password). Returns true ONLY when they really passed it.
/// Pressing Back, cancelling, timing out or failing returns false.
Future<bool> requireDeviceLock(BuildContext context, String reason) async {
  // Phone screen locks cannot be checked on web or desktop test builds.
  if (!_isPhone) return true;

  final auth = LocalAuthentication();
  try {
    if (!await auth.isDeviceSupported()) {
      if (!context.mounted) return false;
      return await _noScreenLock(context);
    }
    return await auth.authenticate(
      localizedReason: reason,
      persistAcrossBackgrounding: true,
    );
  } on LocalAuthException catch (e) {
    debugPrint('Lock screen check: ${e.code.name}');
    if (!context.mounted) return false;
    switch (e.code) {
      case LocalAuthExceptionCode.noCredentialsSet:
      case LocalAuthExceptionCode.noBiometricsEnrolled:
      case LocalAuthExceptionCode.noBiometricHardware:
        return await _noScreenLock(context);
      case LocalAuthExceptionCode.temporaryLockout:
      case LocalAuthExceptionCode.biometricLockout:
        await _info(
          context,
          'Too many attempts',
          'Please wait a moment, then try again.',
        );
        return false;
      case LocalAuthExceptionCode.userCanceled:
      case LocalAuthExceptionCode.systemCanceled:
      case LocalAuthExceptionCode.timeout:
      case LocalAuthExceptionCode.authInProgress:
      case LocalAuthExceptionCode.userRequestedFallback:
        return false; // Back / cancel: do NOT open the module.
      default:
        await _info(
          context,
          'Could not verify you',
          'We could not open your phone lock screen. Please try again.',
        );
        return false;
    }
  } on MissingPluginException {
    // Only happens on a broken or outdated build. Nothing can be enforced.
    debugPrint('Screen lock plugin is not available in this build.');
    return true;
  } catch (e) {
    debugPrint('Lock screen check failed: $e');
    if (!context.mounted) return false;
    await _info(
      context,
      'Could not verify you',
      'We could not open your phone lock screen. Please try again.',
    );
    return false;
  }
}

Future<bool> _noScreenLock(BuildContext context) async {
  if (kAllowWhenNoScreenLock) return true;
  await _info(
    context,
    'Screen lock required',
    'To protect school data, this section needs a screen lock on your phone. '
        'Please set a PIN, pattern, password or fingerprint in your phone '
        'Settings, then try again.',
  );
  return false;
}

Future<void> _info(BuildContext context, String title, String message) async {
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
