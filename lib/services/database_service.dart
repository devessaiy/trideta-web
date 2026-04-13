import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';

class DatabaseService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // 1. UPLOAD PASSPORT IMAGE
  Future<String?> uploadPassport(File imageFile, String admissionNo) async {
    try {
      // Create a clean filename: "SSIA-25-J1-001.jpg"
      final fileName = '${admissionNo.replaceAll('/', '-')}.jpg';
      final path = fileName; 

      // Upload to Supabase Storage Bucket "passports"
      await _supabase.storage.from('passports').upload(
        path,
        imageFile,
        fileOptions: const FileOptions(upsert: true), // Overwrite if exists
      );

      // Get the Public URL to save in the database
      final imageUrl = _supabase.storage.from('passports').getPublicUrl(path);
      return imageUrl;
    } catch (e) {
      print('Error uploading passport: $e');
      return null;
    }
  }

  // 2. SAVE STUDENT DATA
  Future<bool> admitStudent({
    required String admissionNo,
    required String firstName,
    required String lastName,
    required String gender,
    required String dob,
    required String studentClass,
    required String category,
    required String parentName,
    required String parentPhone,
    required String parentEmail,
    required String? passportUrl,
  }) async {
    try {
      await _supabase.from('students').insert({
        'admission_no': admissionNo,
        'first_name': firstName,
        'last_name': lastName,
        'gender': gender,
        'dob': dob, // Format: YYYY-MM-DD
        'class_level': studentClass,
        'category': category,
        'parent_name': parentName,
        'parent_phone': parentPhone,
        'parent_email': parentEmail,
        'passport_url': passportUrl,
        // IMPORTANT: This uses the Default School ID we created in SQL
        'school_id': '00000000-0000-0000-0000-000000000000', 
        'is_active': true,
      });
      return true;
    } catch (e) {
      print('Error saving student: $e');
      return false; // Failed
    }
  }

  // 3. GET ALL STUDENTS (Real-time Stream)
  // This listens to the database. If you add a student on your phone, 
  // it appears here instantly without refreshing!
  Stream<List<Map<String, dynamic>>> getStudents() {
    return _supabase
        .from('students')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false); // Newest students first
  }
}