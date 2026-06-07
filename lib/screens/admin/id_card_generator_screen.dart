import 'package:trideta_v2/utils/auth_error_handler.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trideta_v2/widgets/trideta_loader.dart';

import 'id_card_preview_screen.dart'; // 🚨 Ensure this points to your preview screen

class IdCardGeneratorScreen extends StatefulWidget {
  const IdCardGeneratorScreen({super.key});

  @override
  State<IdCardGeneratorScreen> createState() => _IdCardGeneratorScreenState();
}

class _IdCardGeneratorScreenState extends State<IdCardGeneratorScreen>
    with AuthErrorHandler {
  final _supabase = Supabase.instance.client;

  bool _isLoadingConfig = true;
  bool _isLoadingStudents = false;
  final bool _isGenerating = false;

  String? _schoolId;
  String _schoolName = "Trideta School";

  // 🚨 RESTORED VARIABLES FOR ID CARD BACK
  String _schoolAddress = "Return to School Administration";
  String _schoolPhone = "";
  String _schoolEmail = "";

  List<String> _activeClasses = [];
  String? _selectedClass;
  List<Map<String, dynamic>> _students = [];

  @override
  void initState() {
    super.initState();
    _fetchConfig();
  }

  Future<void> _fetchConfig() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final profile = await _supabase
          .from('profiles')
          .select('school_id')
          .eq('id', user.id)
          .single();
      _schoolId = profile['school_id'];

      if (_schoolId != null) {
        // 🚨 UPDATED QUERY: Fetching name, address, phone, and email exactly like your Report Card!
        final schoolData = await _supabase
            .from('schools')
            .select('name, address, contact_phone, contact_email')
            .eq('id', _schoolId!)
            .single();

        _schoolName = schoolData['name'] ?? "Trideta School";
        _schoolAddress =
            schoolData['address'] ?? "Return to School Administration";
        _schoolPhone = schoolData['contact_phone'] ?? "";
        _schoolEmail = schoolData['contact_email'] ?? "";

        final classData = await _supabase
            .from('classes')
            .select('name')
            .eq('school_id', _schoolId!)
            .order('list_order', ascending: true);
        _activeClasses = classData.map((c) => c['name'].toString()).toList();

        if (_activeClasses.isNotEmpty) {
          _selectedClass = _activeClasses.first;
          await _fetchStudentsForClass(_selectedClass!);
        }
      }
    } catch (e) {
      debugPrint("Failed to load config: $e");
    } finally {
      if (mounted) setState(() => _isLoadingConfig = false);
    }
  }

  Future<void> _fetchStudentsForClass(String className) async {
    setState(() => _isLoadingStudents = true);
    try {
      final res = await _supabase
          .from('students')
          .select(
            'id, first_name, last_name, admission_no, passport_url, class_level',
          )
          .eq('school_id', _schoolId!)
          .eq('class_level', className)
          .order('first_name', ascending: true);
      if (mounted) {
        setState(() {
          _students = List<Map<String, dynamic>>.from(res);
        });
      }
    } catch (e) {
      debugPrint("Failed to load students: $e");
    } finally {
      if (mounted) setState(() => _isLoadingStudents = false);
    }
  }

  // ============================================================================
  // 🚨 GENERATE INDIVIDUAL ID (ROUTES TO PREVIEW)
  // ============================================================================
  void _generateIndividualId(Map<String, dynamic> student) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => IdCardPreviewScreen(
          student: student,
          schoolName: _schoolName,
          schoolAddress: _schoolAddress, // 🚨 RED LINES FIXED!
          schoolPhone: _schoolPhone, // 🚨 RED LINES FIXED!
          schoolEmail: _schoolEmail, // 🚨 RED LINES FIXED!
        ),
      ),
    );
  }

  // ============================================================================
  // 🚨 BULK ACTION NOTICE
  // ============================================================================
  void _generateBulkIdCards() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          "Bulk A4 generation is currently being updated to the new design system. Please download cards individually for now.",
        ),
        backgroundColor: Colors.orange,
      ),
    );
  }

  // ============================================================================
  // 🚨 SCREEN UI LAYOUT
  // ============================================================================
  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color primaryColor = Theme.of(context).primaryColor;
    Color bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC);
    Color cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    if (_isLoadingConfig)
      return Scaffold(
        backgroundColor: bgColor,
        body: Center(child: TridetaLoader(color: primaryColor)),
      );

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text(
          "ID Card Generator",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: bgColor,
        foregroundColor: isDark ? Colors.white : Colors.black87,
        elevation: 0,
        centerTitle: true,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            children: [
              // ─── TOP CONTROL PANEL ───
              Container(
                margin: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: isDark ? Colors.white10 : Colors.grey.shade200,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: primaryColor.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.badge_rounded,
                            color: primaryColor,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            "Select a class to generate individual standard CR80 PVC ID Cards, or use the bulk action to print the entire class.",
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark
                                  ? Colors.white70
                                  : Colors.grey.shade600,
                              height: 1.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.05)
                                  : Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isDark
                                    ? Colors.transparent
                                    : Colors.grey.shade200,
                              ),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                isExpanded: true,
                                value: _selectedClass,
                                icon: Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  color: Colors.grey.shade400,
                                ),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : Colors.black87,
                                  fontSize: 15,
                                ),
                                items: _activeClasses.map((String c) {
                                  return DropdownMenuItem<String>(
                                    value: c,
                                    child: Text(
                                      c,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  );
                                }).toList(),
                                onChanged: (_isGenerating || _isLoadingStudents)
                                    ? null
                                    : (String? v) {
                                        if (v != null && v != _selectedClass) {
                                          setState(() => _selectedClass = v);
                                          _fetchStudentsForClass(v);
                                        }
                                      },
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 1,
                          child: SizedBox(
                            height: 55,
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: primaryColor,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                elevation: 0,
                              ),
                              onPressed: _isGenerating
                                  ? null
                                  : _generateBulkIdCards,
                              icon: const Icon(Icons.print_rounded, size: 18),
                              label: const Text(
                                "BULK A4",
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // ─── STUDENT LIST ───
              Expanded(
                child: _isLoadingStudents
                    ? Center(child: TridetaLoader(color: primaryColor))
                    : _students.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.05)
                                    : Colors.grey.shade100,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.group_off_rounded,
                                size: 40,
                                color: Colors.grey.shade400,
                              ),
                            ),
                            const SizedBox(height: 20),
                            const Text(
                              "No Students Found",
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 18,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              "There are no registered students in $_selectedClass.",
                              style: TextStyle(
                                color: Colors.grey.shade500,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                        itemCount: _students.length,
                        itemBuilder: (context, index) {
                          final student = _students[index];
                          final String fullName =
                              "${student['first_name']} ${student['last_name']}";
                          final String? photoUrl = student['passport_url'];

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: cardColor,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isDark
                                    ? Colors.white10
                                    : Colors.grey.shade200,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.02),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 12,
                              ),
                              leading: CircleAvatar(
                                radius: 24,
                                backgroundColor: primaryColor.withValues(
                                  alpha: 0.1,
                                ),
                                backgroundImage:
                                    photoUrl != null && photoUrl.isNotEmpty
                                    ? NetworkImage(photoUrl)
                                    : null,
                                child: photoUrl == null || photoUrl.isEmpty
                                    ? Icon(
                                        Icons.person_rounded,
                                        color: primaryColor,
                                      )
                                    : null,
                              ),
                              title: Text(
                                fullName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  "ID: ${student['admission_no'] ?? 'N/A'}",
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade500,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              trailing: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: primaryColor,
                                  side: BorderSide(
                                    color: primaryColor.withValues(alpha: 0.5),
                                    width: 1.5,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                onPressed: _isGenerating
                                    ? null
                                    : () => _generateIndividualId(student),
                                icon: const Icon(
                                  Icons.download_rounded,
                                  size: 16,
                                ),
                                label: const Text(
                                  "CARD",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
