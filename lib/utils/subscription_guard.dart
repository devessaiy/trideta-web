import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trideta_v2/utils/resilient_request.dart';

class SubscriptionGuard {
  final _supabase = Supabase.instance.client;

  // Remembers when each user was last confirmed "active", so we don't run
  // two database queries before every single action.
  static final Map<String, DateTime> _lastAllowed = {};
  static const Duration _freshFor = Duration(minutes: 5);
  static const Duration _offlineGrace = Duration(hours: 24);

  /// Checks if the user's school is active.
  /// Returns TRUE if they are allowed to proceed.
  /// Shows an error dialog and returns FALSE if they are paused.
  Future<bool> canPerformAction(BuildContext context) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return false;

    final lastAllowed = _lastAllowed[userId];
    if (lastAllowed != null &&
        DateTime.now().difference(lastAllowed) < _freshFor) {
      return true;
    }

    try {
      // 1. Bypass check for Super Admins (Trideta Owners)
      final superAdminCheck = await retryRead(
        () async => await _supabase
            .from('super_admins')
            .select('id')
            .eq('id', userId)
            .maybeSingle(),
        maxAttempts: 2,
      );

      if (superAdminCheck != null) {
        _lastAllowed[userId] = DateTime.now();
        return true; // Owners can do anything
      }

      // 2. Fetch the standard user's school status
      final response = await retryRead(
        () async => await _supabase
            .from('profiles')
            .select('schools(subscription_status)')
            .eq('id', userId)
            .single(),
        maxAttempts: 2,
      );

      final status = response['schools']?['subscription_status'];

      if (status == 'paused_payment') {
        _lastAllowed.remove(userId);
        if (context.mounted) {
          _showBlockedDialog(context);
        }
        return false;
      }

      // If active, remember it and return true.
      _lastAllowed[userId] = DateTime.now();
      return true;
    } catch (e) {
      debugPrint("Error checking subscription status: $e");
      // Could not reach the server. If this user was confirmed active
      // recently, let them carry on instead of blocking their work.
      if (lastAllowed != null &&
          DateTime.now().difference(lastAllowed) < _offlineGrace) {
        return true;
      }
      return false;
    }
  }

  // 🚨 Custom Error Dialog replacing the AuthErrorHandler mixin
  void _showBlockedDialog(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Row(
          children: [
            Icon(Icons.block_rounded, color: Colors.orange, size: 28),
            SizedBox(width: 10),
            Text(
              "Action Blocked",
              style: TextStyle(
                color: Colors.orange,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ],
        ),
        content: Text(
          "Your school's Trideta subscription is currently paused due to an outstanding balance. Please contact your administrator to restore write access.",
          style: TextStyle(
            fontSize: 14,
            color: isDark ? Colors.white70 : Colors.black87,
            height: 1.5,
          ),
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.orange,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              "Understood",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
