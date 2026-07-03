import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SubscriptionGuard {
  final _supabase = Supabase.instance.client;

  /// Checks if the user's school is active.
  /// Returns TRUE if they are allowed to proceed.
  /// Shows an error dialog and returns FALSE if they are paused.
  Future<bool> canPerformAction(BuildContext context) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return false;

      // 1. Bypass check for Super Admins (Trideta Owners)
      final superAdminCheck = await _supabase
          .from('super_admins')
          .select()
          .eq('id', userId)
          .maybeSingle();

      if (superAdminCheck != null) return true; // Owners can do anything

      // 2. Fetch the standard user's school status
      final response = await _supabase
          .from('profiles')
          .select('schools(subscription_status)')
          .eq('id', userId)
          .single();

      final status = response['schools']?['subscription_status'];

      if (status == 'paused_payment') {
        if (context.mounted) {
          _showBlockedDialog(context);
        }
        return false;
      }

      // If active, return true.
      return true;
    } catch (e) {
      debugPrint("Error checking subscription status: $e");
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
