import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';

class AlertService {
  final _supabase = Supabase.instance.client;

  // 🚨 THIS IS THE BUTTON TRIGGER FOR YOUR ADMIN APP
  Future<bool> createSchoolAlert({
    required String title,
    required String message,
    required String type, // Remember, our database requires this!
  }) async {
    try {
      // 1. Get the Admin's School ID so it routes to the right parents
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception("Admin not logged in");

      final profile = await _supabase
          .from('profiles')
          .select('school_id')
          .eq('id', user.id)
          .single();

      final schoolId = profile['school_id'];

      // 2. Insert into the database (This fires the webhook -> Edge Function -> Phone)
      await _supabase.from('alerts').insert({
        'title': title,
        'message': message,
        'type': type,
        'school_id': schoolId,
      });

      debugPrint("✅ Alert successfully fired to the cloud!");
      return true;
    } catch (e) {
      debugPrint("❌ Failed to send alert: $e");
      return false;
    }
  }
}
