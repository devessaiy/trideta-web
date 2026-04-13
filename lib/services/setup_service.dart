import 'package:supabase_flutter/supabase_flutter.dart';

class SetupService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<String?> completeSetup({
    required String session,
    required String term,
    required String address,
    required List<String> activeClasses,
    required List<String> activeSubjects,
    // Map<ClassName, Map<SubjectName, {offered, mandatory}>>
    required Map<String, Map<String, Map<String, dynamic>>> allocations,
  }) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        return "You are no longer logged in. Please sign in again.";
      }

      // 1. Get School ID
      final profile = await _supabase
          .from('profiles')
          .select('school_id')
          .eq('id', user.id)
          .single();
      final schoolId = profile['school_id'];

      // 2. Update School Details
      await _supabase
          .from('schools')
          .update({
            'address': address,
            'current_session': session,
            'current_term': term,
            'is_configured': true, // MARK AS DONE
          })
          .eq('id', schoolId);

      // 3. Insert Classes & Get IDs
      final Map<String, String> classIdMap = {};
      for (String className in activeClasses) {
        final res = await _supabase
            .from('classes')
            .insert({'school_id': schoolId, 'name': className})
            .select()
            .single();
        classIdMap[className] = res['id'];
      }

      // 4. Insert Subjects & Get IDs
      final Map<String, String> subjectIdMap = {};
      for (String subjectName in activeSubjects) {
        final res = await _supabase
            .from('subjects')
            .insert({'school_id': schoolId, 'name': subjectName})
            .select()
            .single();
        subjectIdMap[subjectName] = res['id'];
      }

      // 5. Insert Allocations (Curriculum)
      for (var className in allocations.keys) {
        final classId = classIdMap[className];
        final subjectsMap = allocations[className]!;

        for (var subjectName in subjectsMap.keys) {
          final config = subjectsMap[subjectName]!;
          if (config['offered'] == true) {
            final subjectId = subjectIdMap[subjectName];

            if (classId != null && subjectId != null) {
              await _supabase.from('class_subjects').insert({
                'class_id': classId,
                'subject_id': subjectId,
                'is_compulsory': config['mandatory'] ?? false,
              });
            }
          }
        }
      }

      return null; // Success
    } on PostgrestException catch (e) {
      // 🚨 Layman translations for database errors
      if (e.message.contains("unique constraint")) {
        return "It looks like some of these classes or subjects were already set up.";
      }
      return "We couldn't save your settings to the database. Please check your connection.";
    } catch (e) {
      return "An unexpected error occurred during setup. Please try again.";
    }
  }
}
