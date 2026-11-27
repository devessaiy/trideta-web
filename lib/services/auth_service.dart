import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trideta_v2/services/notification_service.dart';

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // 🚨 GOOGLE SIGN-IN CONFIG
  // Paste the *Web application* OAuth client ID from Google Cloud Console
  // (the same one entered in Supabase > Authentication > Providers > Google).
  static const String _googleWebClientId =
      '141687394764-abmtvvcfmf38pmhhnb5cbfdtg9agpqh6.apps.googleusercontent.com';

  /// Returned by [signInWithGoogle] when the user closes the Google picker.
  static const String googleCancelled = '__google_cancelled__';

  static bool _googleInitialised = false;

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

  // 1b. SIGN IN WITH GOOGLE (login only - never creates a Trideta profile)
  // Returns null on success, [googleCancelled] if the user backed out,
  // or an error message. After success the caller MUST run the normal
  // routing check (_checkAndNavigate), which signs the user straight back
  // out if no Trideta profile exists for this Google email.
  Future<String?> signInWithGoogle({bool forRegistration = false}) async {
    try {
      if (kIsWeb) {
        // Web uses Supabase's redirect flow; the app resumes with a session
        // and the login screen's existing session-resume path routes it.
        await _supabase.auth.signInWithOAuth(
          OAuthProvider.google,
          redirectTo: forRegistration
              ? '${Uri.base.origin}/?intent=register'
              : Uri.base.origin,
        );
        return googleCancelled; // page navigates away; nothing more to do
      }

      if (!_googleInitialised) {
        await GoogleSignIn.instance.initialize(
          serverClientId: _googleWebClientId,
        );
        _googleInitialised = true;
      }

      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        return "Google Sign-In Failed: no ID token was returned.";
      }

      final response = await _supabase.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
      );
      if (response.user == null) return "Google Sign-In Failed: Unknown error.";
      return null;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return googleCancelled;
      return "Google Sign-In Error: ${e.description ?? e.code.name}";
    } on AuthException catch (e) {
      return "Google Sign-In Error: ${e.message}";
    } catch (e) {
      return "Google Sign-In Error: $e";
    }
  }

  // 1c. HELPERS FOR "REGISTER WITH GOOGLE"
  String? get currentEmail => _supabase.auth.currentUser?.email;

  /// True when the signed-in user already has a Trideta profile.
  /// If we cannot tell, we answer true so we never offer to create a second account.
  Future<bool> currentUserHasProfile() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return false;
    try {
      final p = await _supabase
          .from('profiles')
          .select('id')
          .eq('id', user.id)
          .maybeSingle();
      return p != null;
    } catch (_) {
      return true;
    }
  }

  /// Creates a NEW school for the Google user who is signed in right now.
  /// The email always comes from the verified Google session, never from the form.
  /// (register_school itself also refuses anyone who already has a profile.)
  Future<String?> registerSchoolWithGoogle({
    required String schoolName,
    required String phone,
    String? address,
  }) async {
    try {
      final user = _supabase.auth.currentUser;
      final email = user?.email;
      if (user == null || email == null || email.isEmpty) {
        return "Please sign in with Google first.";
      }
      final meta = user.userMetadata ?? {};
      final ownerName = (meta['full_name'] ?? meta['name'] ?? 'Admin')
          .toString();

      await _supabase.rpc(
        'register_school',
        params: {
          'new_school_name': schoolName,
          'new_acronym': _generateAcronym(schoolName),
          'new_address': address ?? "",
          'new_full_name': ownerName,
          'new_email': email,
          'new_phone': phone,
        },
      );
      return null;
    } on PostgrestException catch (dbError) {
      return "Database Error: ${dbError.message} (Code: ${dbError.code})";
    } catch (e) {
      return "Unexpected Error: $e";
    }
  }

  // 2. REGISTER NEW SCHOOL (via atomic register_school RPC)
  Future<String?> registerSchool({
    required String schoolName,
    required String email,
    required String password,
    required String phone,
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

      // B. Create School + Admin Profile atomically (single RPC call)
      try {
        await _supabase.rpc(
          'register_school',
          params: {
            'new_school_name': schoolName,
            'new_acronym': _generateAcronym(schoolName),
            'new_address': address ?? "",
            'new_full_name': ownerName ?? "Admin",
            'new_email': email,
            'new_phone': phone,
          },
        );
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

      // A school is set up when either flag says so ('setup_completed' is the
      // one the setup wizard writes). This lets admins go straight to the
      // dashboard instead of passing through the setup wizard every login.
      final school = await _supabase
          .from('schools')
          .select('is_configured, setup_completed')
          .eq('id', schoolId)
          .single();

      return school['is_configured'] == true ||
          school['setup_completed'] == true;
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

  /// Ends the Supabase session AND forgets the chosen Google account, so the next
  /// Google tap shows the account picker. Used when access is denied after a
  /// successful sign-in (suspended, terminated subscription, no account).
  Future<void> signOutSession() async {
    if (!kIsWeb) {
      try {
        if (!_googleInitialised) {
          await GoogleSignIn.instance.initialize(
            serverClientId: _googleWebClientId,
          );
          _googleInitialised = true;
        }
        await GoogleSignIn.instance.signOut();
      } catch (_) {}
    }
    await _supabase.auth.signOut();
  }

  Future<void> logout() async {
    await NotificationService.removeThisDeviceToken();
    try {
      if (!kIsWeb && _googleInitialised) await GoogleSignIn.instance.signOut();
    } catch (_) {}
    await _supabase.auth.signOut();
  }
}
