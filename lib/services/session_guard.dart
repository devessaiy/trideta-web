import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trideta_v2/main.dart' show navigatorKey;
import 'package:trideta_v2/screens/auth/login_screen.dart';
import 'package:trideta_v2/services/offline_queue.dart';
import 'package:trideta_v2/utils/resilient_request.dart';

/// What the app learned about a signed-in user the last time it could reach
/// the server (role, school colour, setup state). Saved encrypted on the
/// phone so the next start can open the right dashboard at once, even with
/// no internet.
class SessionSnapshot {
  static String _key(String uid) => 'route:$uid';

  static Future<void> save(
    String uid, {
    required String role,
    bool isOwner = false,
    bool isConfigured = true,
    bool isAlsoParent = false,
    String? brandColor,
    String? subStatus,
  }) => LocalCache.put(_key(uid), {
    'role': role,
    'isOwner': isOwner,
    'isConfigured': isConfigured,
    'isAlsoParent': isAlsoParent,
    'brandColor': brandColor,
    'subStatus': subStatus,
    'savedAt': DateTime.now().toIso8601String(),
  });

  static Future<Map<String, dynamic>?> load(String uid) async {
    final v = await LocalCache.get(_key(uid));
    return v is Map ? Map<String, dynamic>.from(v) : null;
  }
}

/// Runs in the background after the app opens straight from a saved session.
/// If the server says the account is suspended, removed or the school's
/// subscription is terminated, the user is signed out right away.
/// With no internet it does nothing and the user keeps working.
class SessionGuard {
  static bool _running = false;

  static Future<void> revalidate() async {
    if (_running) return;
    _running = true;
    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null) return;

      final snap = await SessionSnapshot.load(user.id);
      if (snap == null || snap['isOwner'] == true) return;

      final profile = await retryRead(
        () async => await client
            .from('profiles')
            .select(
              'role, is_suspended, schools(brand_color, subscription_status)',
            )
            .eq('id', user.id)
            .maybeSingle(),
        maxAttempts: 2,
        timeout: const Duration(seconds: 12),
      );

      String? deny;
      if (profile == null) {
        deny =
            'Your account is no longer active. Please contact your school administrator.';
      } else if (profile['is_suspended'] == true) {
        deny =
            'Access Denied. Your account has been suspended. Please contact support.';
      } else if (profile['schools']?['subscription_status'] == 'terminated') {
        deny =
            "Access Denied. Your school's Trideta subscription has been terminated. Please contact your school administrator.";
      }

      if (deny != null) {
        await _forceLogout(deny);
        return;
      }

      // Still allowed: keep the saved copy up to date.
      await SessionSnapshot.save(
        user.id,
        role: (profile!['role'] ?? 'parent').toString().toLowerCase(),
        isConfigured: snap['isConfigured'] == true,
        isAlsoParent: snap['isAlsoParent'] == true,
        brandColor: profile['schools']?['brand_color']?.toString(),
        subStatus: profile['schools']?['subscription_status']?.toString(),
      );
    } catch (e) {
      debugPrint('Session check skipped: $e'); // offline or temporary problem
    } finally {
      _running = false;
    }
  }

  static Future<void> _forceLogout(String message) async {
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId != null) {
      await LocalCache.put('route:$userId', null);
    }
    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = navigatorKey.currentContext;
      if (ctx == null) return;
      showDialog<void>(
        context: ctx,
        builder: (dialogCtx) => AlertDialog(
          title: const Text('Signed out'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    });
  }
}
