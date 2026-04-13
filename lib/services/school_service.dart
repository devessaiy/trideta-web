import 'package:supabase_flutter/supabase_flutter.dart';

class SchoolService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Fetch School & Admin Details
  Future<Map<String, dynamic>?> getSchoolProfile() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return null;

      // 1. Get User Profile (To find out which school they belong to)
      final profile = await _supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .single();

      // 2. Get School Details using the school_id from profile
      final school = await _supabase
          .from('schools')
          .select()
          .eq('id', profile['school_id'])
          .single();

      return {
        'admin_name': profile['full_name'] ?? 'Admin',
        'school_name': school['name'] ?? 'My School',
        'school_acronym': school['acronym'] ?? 'TRD',
      };
    } catch (e) {
      print("Error fetching school profile: $e");
      return null;
    }
  }
}