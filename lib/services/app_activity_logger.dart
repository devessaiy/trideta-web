import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

class AppActivityLogger {
  static final _supabase = Supabase.instance.client;

  static void log({
    required String schoolId,
    required String module,
    required String action,
  }) {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    _supabase
        .from('activity_logs')
        .insert({
          'school_id': schoolId,
          'user_id': user.id,
          'module': module,
          'action': action,
        })
        .catchError((error) {
          // Fails silently so the user never sees an error if the log drops
          debugPrint("Activity log skipped: $error");
        });
  }
}
