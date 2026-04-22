import 'package:trideta_v2/utils/auth_error_handler.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ResultComputationScreen extends StatefulWidget {
  const ResultComputationScreen({super.key});

  @override
  State<ResultComputationScreen> createState() =>
      _ResultComputationScreenState();
}

class _ResultComputationScreenState extends State<ResultComputationScreen>
    with AuthErrorHandler {
  final _supabase = Supabase.instance.client;

  bool _isLoading = true;
  bool _isSaving = false;
  String? _schoolId;

  // 🚨 ROLE TRACKER
  String _userRole = 'teacher';

  // --- FILTERS ---
  String? _selectedSession;
  String? _selectedTerm;
  String? _selectedClass;
  String? _selectedSubject;

  final List<String> _sessions = ['2024/2025', '2025/2026', '2026/2027'];
  final List<String> _terms = ['1st Term', '2nd Term', '3rd Term'];
  List<String> _activeClasses = [];
  List<String> _classSubjects = [];

  // --- ROSTER & SCORES ---
  List<Map<String, dynamic>> _students = [];

  final Map<String, Map<String, dynamic>> _scoreData = {};
  final Map<String, Map<String, TextEditingController>> _controllers = {};

  @override
  void initState() {
    super.initState();
    _fetchInitialData();
  }

  @override
  void dispose() {
    for (var student in _controllers.values) {
      for (var ctrl in student.values) {
        ctrl.dispose();
      }
    }
    super.dispose();
  }

  // ===========================================================================
  // 1. DATA FETCHING WITH ROLE-BASED ACCESS CONTROL (RBAC)
  // ===========================================================================

  Future<void> _fetchInitialData() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final profile = await _supabase
          .from('profiles')
          .select('school_id, role')
          .eq('id', user.id)
          .single();

      _schoolId = profile['school_id'];
      _userRole = profile['role']?.toString().toLowerCase() ?? 'teacher';

      final school = await _supabase
          .from('schools')
          .select('current_session, current_term')
          .eq('id', _schoolId!)
          .single();

      List<String> fetchedClasses = [];

      if (_userRole == 'admin') {
        final classesData = await _supabase
            .from('classes')
            .select('name')
            .eq('school_id', _schoolId!)
            .order('list_order', ascending: true);
        fetchedClasses = classesData.map((c) => c['name'].toString()).toList();
      } else {
        final assignments = await _supabase
            .from('staff_assignments')
            .select('class_assigned')
            .eq('staff_id', user.id);
        fetchedClasses = assignments
            .map((a) => a['class_assigned'].toString())
            .toSet()
            .toList();
        fetchedClasses.sort();
      }

      if (mounted) {
        setState(() {
          _selectedSession = school['current_session'] ?? _sessions[1];
          _selectedTerm = school['current_term'] ?? _terms[0];
          _activeClasses = fetchedClasses;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        showAuthErrorDialog("Failed to initialize. Check connection.");
      }
    }
  }

  // 🚨 SMART SUBJECT ROUTING: Unlocks all subjects for Class Teachers
  Future<void> _fetchSubjectsForClass(String className) async {
    setState(() {
      _isLoading = true;
      _selectedSubject = null;
      _classSubjects.clear();
      _students.clear();
    });

    try {
      final user = _supabase.auth.currentUser!;
      List<String> fetchedSubjects = [];

      if (_userRole == 'admin') {
        // Admin gets all subjects for this class
        final subjectsData = await _supabase
            .from('class_subjects')
            .select('subject_name')
            .eq('school_id', _schoolId!)
            .eq('class_name', className);
        fetchedSubjects = subjectsData
            .map((s) => s['subject_name'].toString())
            .toList();
      } else {
        // Fetch teacher's specific assignments for this selected class
        final assignments = await _supabase
            .from('staff_assignments')
            .select('subject_assigned')
            .eq('staff_id', user.id)
            .eq('class_assigned', className);

        // 🚨 MAGIC CHECK: If subject is NULL, they are the Class Teacher!
        bool isClassTeacher = assignments.any(
          (a) =>
              a['subject_assigned'] == null ||
              a['subject_assigned'].toString().trim().isEmpty,
        );

        if (isClassTeacher) {
          // Class Teachers get ALL subjects for their class
          final classSubjects = await _supabase
              .from('class_subjects')
              .select('subject_name')
              .eq('school_id', _schoolId!)
              .eq('class_name', className);
          fetchedSubjects = classSubjects
              .map((s) => s['subject_name'].toString())
              .toList();
        } else {
          // Subject Teachers only get the subjects explicitly assigned to them in this class
          fetchedSubjects = assignments
              .where(
                (a) =>
                    a['subject_assigned'] != null &&
                    a['subject_assigned'].toString().trim().isNotEmpty,
              )
              .map((a) => a['subject_assigned'].toString())
              .toSet()
              .toList();
        }
      }

      if (mounted) {
        setState(() {
          _classSubjects = fetchedSubjects..sort();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchRosterAndExistingScores() async {
    if (_selectedClass == null || _selectedSubject == null) return;

    setState(() => _isLoading = true);
    try {
      final studentsData = await _supabase
          .from('students')
          .select('id, first_name, last_name, admission_no')
          .eq('school_id', _schoolId!)
          .eq('class_level', _selectedClass!)
          .order('first_name', ascending: true);

      final existingScores = await _supabase
          .from('exam_scores')
          .select()
          .eq('school_id', _schoolId!)
          .eq('class_level', _selectedClass!)
          .eq('subject_name', _selectedSubject!)
          .eq('academic_session', _selectedSession!)
          .eq('term', _selectedTerm!);

      final Map<String, dynamic> scoreMap = {
        for (var score in existingScores) score['student_id'].toString(): score,
      };

      _scoreData.clear();
      _controllers.clear();

      for (var s in studentsData) {
        String sId = s['id'].toString();
        var existing = scoreMap[sId];

        _scoreData[sId] = {
          'ca_attendance': existing?['ca_attendance'] ?? 0.0,
          'ca_assignment': existing?['ca_assignment'] ?? 0.0,
          'ca_midterm': existing?['ca_midterm'] ?? 0.0,
          'exam_score': existing?['exam_score'] ?? 0.0,
          'total_score': existing?['total_score'] ?? 0.0,
          'grade': existing?['grade'] ?? '-',
          'remark': existing?['remark'] ?? '-',
        };

        _controllers[sId] = {
          'ca_attendance': TextEditingController(
            text: existing != null && existing['ca_attendance'] > 0
                ? existing['ca_attendance'].toString()
                : '',
          ),
          'ca_assignment': TextEditingController(
            text: existing != null && existing['ca_assignment'] > 0
                ? existing['ca_assignment'].toString()
                : '',
          ),
          'ca_midterm': TextEditingController(
            text: existing != null && existing['ca_midterm'] > 0
                ? existing['ca_midterm'].toString()
                : '',
          ),
          'exam_score': TextEditingController(
            text: existing != null && existing['exam_score'] > 0
                ? existing['exam_score'].toString()
                : '',
          ),
        };
      }

      if (mounted) {
        setState(() {
          _students = List<Map<String, dynamic>>.from(studentsData);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        showAuthErrorDialog("Failed to load roster: $e");
      }
    }
  }

  // ===========================================================================
  // 2. THE GRADING ENGINE (BECE/WAEC STANDARD)
  // ===========================================================================

  void _recalculateScore(String studentId) {
    double ca1 =
        double.tryParse(_controllers[studentId]!['ca_attendance']!.text) ?? 0.0;
    double ca2 =
        double.tryParse(_controllers[studentId]!['ca_assignment']!.text) ?? 0.0;
    double ca3 =
        double.tryParse(_controllers[studentId]!['ca_midterm']!.text) ?? 0.0;
    double exam =
        double.tryParse(_controllers[studentId]!['exam_score']!.text) ?? 0.0;

    if (ca1 > 5) {
      ca1 = 5;
      _controllers[studentId]!['ca_attendance']!.text = '5';
    }
    if (ca2 > 10) {
      ca2 = 10;
      _controllers[studentId]!['ca_assignment']!.text = '10';
    }
    if (ca3 > 25) {
      ca3 = 25;
      _controllers[studentId]!['ca_midterm']!.text = '25';
    }
    if (exam > 60) {
      exam = 60;
      _controllers[studentId]!['exam_score']!.text = '60';
    }

    double total = ca1 + ca2 + ca3 + exam;
    String grade = '-';
    String remark = '-';

    if (total > 0) {
      if (total >= 70) {
        grade = 'A';
        remark = 'Excellent';
      } else if (total >= 60) {
        grade = 'B';
        remark = 'Very Good';
      } else if (total >= 50) {
        grade = 'C';
        remark = 'Credit';
      } else if (total >= 45) {
        grade = 'P';
        remark = 'Pass';
      } else {
        grade = 'F';
        remark = 'Fail';
      }
    }

    setState(() {
      _scoreData[studentId]!['ca_attendance'] = ca1;
      _scoreData[studentId]!['ca_assignment'] = ca2;
      _scoreData[studentId]!['ca_midterm'] = ca3;
      _scoreData[studentId]!['exam_score'] = exam;
      _scoreData[studentId]!['total_score'] = total;
      _scoreData[studentId]!['grade'] = grade;
      _scoreData[studentId]!['remark'] = remark;
    });
  }

  // ===========================================================================
  // 3. DATABASE SAVING
  // ===========================================================================

  Future<void> _saveScoresToDatabase() async {
    FocusScope.of(context).unfocus();
    setState(() => _isSaving = true);

    try {
      final user = _supabase.auth.currentUser!;
      List<Map<String, dynamic>> upsertPayload = [];

      for (var s in _students) {
        String sId = s['id'].toString();
        var data = _scoreData[sId]!;

        if (data['total_score'] > 0) {
          upsertPayload.add({
            'school_id': _schoolId,
            'student_id': sId,
            'academic_session': _selectedSession,
            'term': _selectedTerm,
            'class_level': _selectedClass,
            'subject_name': _selectedSubject,
            'ca_attendance': data['ca_attendance'],
            'ca_assignment': data['ca_assignment'],
            'ca_midterm': data['ca_midterm'],
            'exam_score': data['exam_score'],
            'total_score': data['total_score'],
            'grade': data['grade'],
            'remark': data['remark'],
            'last_edited_by': user.id,
            'updated_at': DateTime.now().toIso8601String(),
          });
        }
      }

      if (upsertPayload.isNotEmpty) {
        await _supabase
            .from('exam_scores')
            .upsert(
              upsertPayload,
              onConflict: 'student_id, subject_name, academic_session, term',
            );
      }

      if (mounted) {
        setState(() => _isSaving = false);
        showSuccessDialog(
          "Scores Saved!",
          "Successfully recorded scores for $_selectedSubject - $_selectedClass.",
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        showAuthErrorDialog("Failed to save scores. Check connection.");
      }
    }
  }

  // ===========================================================================
  // 4. UI BUILDERS
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC);
    Color cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    Color primaryColor = Theme.of(context).primaryColor;

    // 🚨 ROLE CHECK
    bool isAdmin = _userRole == 'admin';

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text(
          "Result Engine",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 0,
      ),
      body: Column(
        children: [
          // 1. FILTER HEADER
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cardColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              children: [
                if (isAdmin)
                  Container(
                    margin: const EdgeInsets.only(bottom: 15),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.red.withOpacity(0.3)),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.admin_panel_settings,
                          size: 16,
                          color: Colors.red,
                        ),
                        SizedBox(width: 8),
                        Text(
                          "ADMIN OVERRIDE ACTIVE",
                          style: TextStyle(
                            color: Colors.red,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),

                Row(
                  children: [
                    // 🚨 LOCKED FOR TEACHERS
                    Expanded(
                      child: _buildFilterDropdown(
                        "Session",
                        _sessions,
                        _selectedSession,
                        isAdmin
                            ? (val) {
                                setState(() {
                                  _selectedSession = val;
                                  _students.clear();
                                });
                              }
                            : null,
                        isDark,
                        primaryColor,
                      ),
                    ),
                    const SizedBox(width: 10),
                    // 🚨 LOCKED FOR TEACHERS
                    Expanded(
                      child: _buildFilterDropdown(
                        "Term",
                        _terms,
                        _selectedTerm,
                        isAdmin
                            ? (val) {
                                setState(() {
                                  _selectedTerm = val;
                                  _students.clear();
                                });
                              }
                            : null,
                        isDark,
                        primaryColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                Row(
                  children: [
                    Expanded(
                      child: _buildFilterDropdown(
                        "Class",
                        _activeClasses,
                        _selectedClass,
                        (val) {
                          setState(() => _selectedClass = val);
                          _fetchSubjectsForClass(val!);
                        },
                        isDark,
                        primaryColor,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildFilterDropdown(
                        "Subject",
                        _classSubjects,
                        _selectedSubject,
                        (val) {
                          setState(() => _selectedSubject = val);
                          _fetchRosterAndExistingScores();
                        },
                        isDark,
                        primaryColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 2. MAIN LIST AREA
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator(color: primaryColor))
                : _selectedSubject == null
                ? _buildPlaceholderState(isDark)
                : _students.isEmpty
                ? const Center(
                    child: Text(
                      "No students in this class.",
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _students.length,
                    itemBuilder: (context, index) {
                      return _buildScoreCard(
                        _students[index],
                        cardColor,
                        isDark,
                        primaryColor,
                      );
                    },
                  ),
          ),

          // 3. SAVE BUTTON BAR
          if (_students.isNotEmpty && _selectedSubject != null)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cardColor,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  onPressed: _isSaving ? null : _saveScoresToDatabase,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.save_rounded, color: Colors.white),
                  label: Text(
                    _isSaving
                        ? "SAVING SECURELY..."
                        : "SAVE ${_selectedSubject!.toUpperCase()} SCORES",
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFilterDropdown(
    String hint,
    List<String> items,
    String? value,
    Function(String?)? onChanged, // Notice this can be null now
    bool isDark,
    Color primaryColor,
  ) {
    bool isLocked = onChanged == null;
    return Container(
      decoration: BoxDecoration(
        color: isLocked
            ? (isDark ? Colors.white.withOpacity(0.02) : Colors.grey[200])
            : (isDark ? Colors.white.withOpacity(0.05) : Colors.grey[50]),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade300,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: value,
          hint: Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Text(
              hint,
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ),
          icon: Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Icon(
              isLocked ? Icons.lock_outline : Icons.arrow_drop_down,
              color: isLocked ? Colors.grey : primaryColor,
              size: isLocked ? 18 : 24,
            ),
          ),
          items: items
              .map(
                (e) => DropdownMenuItem(
                  value: e,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Text(
                      e,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isLocked ? Colors.grey : null,
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
          onChanged: onChanged, // Will automatically disable dropdown if null
          dropdownColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        ),
      ),
    );
  }

  Widget _buildPlaceholderState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _userRole == 'admin'
                ? Icons.admin_panel_settings
                : Icons.edit_document,
            size: 80,
            color: isDark ? Colors.white10 : Colors.grey[200],
          ),
          const SizedBox(height: 15),
          Text(
            _userRole == 'admin'
                ? "Admin Mode: You have global access.\nSelect any Class and Subject to edit scores."
                : "Select your assigned Class and Subject\nto start computing results.",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isDark ? Colors.white38 : Colors.grey[400],
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScoreCard(
    Map<String, dynamic> student,
    Color cardColor,
    bool isDark,
    Color primaryColor,
  ) {
    String sId = student['id'].toString();
    var data = _scoreData[sId]!;

    Color gradeColor = Colors.grey;
    if (data['grade'] == 'A') gradeColor = Colors.green;
    if (data['grade'] == 'B') gradeColor = Colors.blue;
    if (data['grade'] == 'C') gradeColor = Colors.orange;
    if (data['grade'] == 'P') gradeColor = Colors.purple;
    if (data['grade'] == 'F') gradeColor = Colors.red;

    String fName = student['first_name']?.toString() ?? "";
    String initial = fName.isNotEmpty ? fName[0].toUpperCase() : "?";

    String displayFullName = "${student['last_name'] ?? 'Unknown'} $fName"
        .trim();
    if (displayFullName.isEmpty) displayFullName = "Unnamed Student";

    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: primaryColor.withOpacity(0.05),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: primaryColor.withOpacity(0.2),
                  child: Text(
                    initial,
                    style: TextStyle(
                      color: primaryColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayFullName.toUpperCase(),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        student['admission_no']?.toString() ?? "NO ID",
                        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: gradeColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: gradeColor.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Text(
                        "${data['total_score'].toInt()}%",
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: gradeColor,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        data['grade'],
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: gradeColor,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _buildScoreInput(
                  "ATT\n(5)",
                  _controllers[sId]!['ca_attendance']!,
                  sId,
                  isDark,
                ),
                const SizedBox(width: 8),
                _buildScoreInput(
                  "ASS\n(10)",
                  _controllers[sId]!['ca_assignment']!,
                  sId,
                  isDark,
                ),
                const SizedBox(width: 8),
                _buildScoreInput(
                  "MID\n(25)",
                  _controllers[sId]!['ca_midterm']!,
                  sId,
                  isDark,
                ),
                const SizedBox(width: 12),
                _buildScoreInput(
                  "EXAM\n(60)",
                  _controllers[sId]!['exam_score']!,
                  sId,
                  isDark,
                  isExam: true,
                  primaryColor: primaryColor,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScoreInput(
    String label,
    TextEditingController controller,
    String studentId,
    bool isDark, {
    bool isExam = false,
    Color? primaryColor,
  }) {
    return Expanded(
      flex: isExam ? 2 : 1,
      child: Column(
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: isExam ? primaryColor : Colors.grey,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.center,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
            ],
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: isExam
                  ? primaryColor
                  : (isDark ? Colors.white : Colors.black87),
            ),
            decoration: InputDecoration(
              filled: true,
              fillColor: isExam
                  ? primaryColor!.withOpacity(0.05)
                  : (isDark ? Colors.white.withOpacity(0.02) : Colors.grey[50]),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: isExam
                      ? primaryColor!.withOpacity(0.3)
                      : Colors.transparent,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: isExam ? primaryColor! : Colors.blue,
                  width: 2,
                ),
              ),
            ),
            onChanged: (val) => _recalculateScore(studentId),
          ),
        ],
      ),
    );
  }
}
