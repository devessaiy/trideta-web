import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // 1. LOGIN
  Future<String?> login(String email, String password) async {
    try {
      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );
      if (response.user != null) return null; // Success
      return "Login Failed: Unknown error.";
    } on AuthException catch (e) {
      return "Login Error: ${e.message}";
    } catch (e) {
      return "System Error: $e";
    }
  }

  // 2. REGISTER NEW SCHOOL (Strict Debug Mode)
  Future<String?> registerSchool({
    required String schoolName,
    required String email,
    required String password,
    required String phone, // 🚨 NEW: Added phone as a required parameter!
    String? address,
    String? ownerName,
  }) async {
    try {
      // A. Create User
      final authResponse = await _supabase.auth.signUp(
        email: email,
        password: password,
      );

      if (authResponse.user == null) {
        return "Registration Failed: Supabase returned no user.";
      }

      final userId = authResponse.user!.id;

      // B. Create School (Database Insert)
      try {
        final schoolData = await _supabase
            .from('schools')
            .insert({
              'name': schoolName,
              'acronym': _generateAcronym(schoolName),
              'address': address ?? "",
              'is_configured': false, // Explicitly set to false initially
            })
            .select()
            .single();

        final schoolId = schoolData['id'];

        // C. Link Profile
        await _supabase.from('profiles').insert({
          'id': userId,
          'school_id': schoolId,
          'full_name': ownerName ?? "Admin",
          'role': 'Admin',
          'email': email,
          'phone':
              phone, // 🚨 NEW: Saving the admin's phone number to the database!
        });
      } on PostgrestException catch (dbError) {
        return "Database Error: ${dbError.message} (Code: ${dbError.code})";
      }

      return null; // TRUE SUCCESS
    } on AuthException catch (e) {
      return "Auth Error: ${e.message}";
    } catch (e) {
      return "Unexpected Error: $e";
    }
  }

  // 3. CHECK IF SCHOOL IS CONFIGURED
  Future<bool> isSchoolConfigured() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return false;

      // Get School ID from Profile
      final profile = await _supabase
          .from('profiles')
          .select('school_id')
          .eq('id', user.id)
          .single();

      final schoolId = profile['school_id'];

      // Check 'is_configured' flag in Schools table
      final school = await _supabase
          .from('schools')
          .select('is_configured')
          .eq('id', schoolId)
          .single();

      return school['is_configured'] ?? false;
    } catch (e) {
      print("Error checking config: $e");
      return false; // Default to false (force setup if unsure)
    }
  }

  String _generateAcronym(String name) {
    if (name.isEmpty) return "TRD";
    List<String> words = name.split(" ");
    String acronym = "";
    for (var word in words) {
      if (word.isNotEmpty &&
          !["of", "the", "and", "&"].contains(word.toLowerCase())) {
        acronym += word[0].toUpperCase();
      }
    }
    return acronym.length < 2 ? name.substring(0, 3).toUpperCase() : acronym;
  }

  Future<void> logout() async {
    await _supabase.auth.signOut();
  }
}
