import 'package:supabase_flutter/supabase_flutter.dart';

class ParentService {
  final supabase = Supabase.instance.client;

  Future<void> autoCreateParent({
    required String email,
    required String phone,
    required String studentName,
  }) async {
    try {
      // This "calls" the Edge Function we just deployed!
      await supabase.functions.invoke(
        'create-parent-account',
        body: {
          'email': email,
          'phone': phone,
          'studentName': studentName,
        },
      );
      print("Success: Parent account logic triggered.");
    } catch (e) {
      print("Error creating parent account: $e");
      rethrow;
    }
  }
}