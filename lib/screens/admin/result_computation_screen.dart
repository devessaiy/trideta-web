import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trideta_v2/utils/auth_error_handler.dart';

// --- MODELS --- //
class StudentScore {
  final String id; // student_id
  final String name; // First + Last Name
  final String admissionNo;
  String? resultId; // The ID of the existing record in exam_scores (if any)

  double caAttendance; // 5
  double caAssignment; // 10
  double caMidterm; // 25
  double examScore; // 60

  StudentScore({
    required this.id,
    required this.name,
    required this.admissionNo,
    this.resultId,
    this.caAttendance = 0,
    this.caAssignment = 0,
    this.caMidterm = 0,
    this.examScore = 0,
  });

  double get total => caAttendance + caAssignment + caMidterm + examScore;

  String get grade {
    if (total >= 75) return 'A';
    if (total >= 65) return 'B';
    if (total >= 50) return 'C';
    if (total >= 40) return 'D';
    if (total >= 35) return 'E';
    return 'F';
  }

  String get remark {
    if (total >= 75) return 'Excellent';
    if (total >= 65) return 'Very Good';
    if (total >= 50) return 'Credit';
    if (total >= 40) return 'Pass';
    if (total >= 35) return 'Poor';
    return 'Fail';
  }
}

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
  String? _userId;
  String _userRole = 'teacher';

  // --- FILTERS --- //
  final List<String> _sessions = ['2024/2025', '2025/2026', '2026/2027'];
  final List<String> _terms = ['1st Term', '2nd Term', '3rd Term'];
  String? _selectedSession;
  String? _selectedTerm;

  // Classes & Subjects mappings
  List<Map<String, dynamic>> _activeClasses = [];
  List<Map<String, dynamic>> _classSubjects = [];

  String? _selectedClassId;
  String? _selectedClassName;

  String? _selectedSubjectId;
  String? _selectedSubjectName;

  // --- DATA --- //
  List<StudentScore> _students = [];

  // Used for text field focus & cursor management to stop "sticky" typing
  final Map<String, List<FocusNode>> _focusNodes = {};
  final Map<String, List<TextEditingController>> _controllers = {};

  @override
  void initState() {
    super.initState();
    _fetchInitialData();
  }

  @override
  void dispose() {
    for (var nodes in _focusNodes.values) {
      for (var node in nodes) {
        node.dispose();
      }
    }
    for (var ctrls in _controllers.values) {
      for (var ctrl in ctrls) {
        ctrl.dispose();
      }
    }
    super.dispose();
  }

  Future<void> _fetchInitialData() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;
      _userId = user.id;

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

      List<Map<String, dynamic>> fetchedClasses = [];

      if (_userRole == 'admin') {
        final classesData = await _supabase
            .from('classes')
            .select('id, name')
            .eq('school_id', _schoolId!)
            .order('list_order', ascending: true);
        fetchedClasses = List<Map<String, dynamic>>.from(classesData);
      } else {
        // Teacher Logic: Fetch assigned classes, then their IDs & Names
        final assignments = await _supabase
            .from('staff_assignments')
            .select('class_id')
            .eq('staff_id', user.id);

        final Set<String> uniqueClassIds = {};
        for (var a in assignments) {
          if (a['class_id'] != null) {
            uniqueClassIds.add(a['class_id'].toString());
          }
        }

        if (uniqueClassIds.isNotEmpty) {
          final freshClasses = await _supabase
              .from('classes')
              .select('id, name')
              .inFilter('id', uniqueClassIds.toList())
              .order('name');
          fetchedClasses = List<Map<String, dynamic>>.from(freshClasses);
        }
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
        showAuthErrorDialog("Init Error: $e");
      }
    }
  }

  Future<void> _fetchSubjectsForClass(String classId) async {
    setState(() {
      _isLoading = true;
      _selectedSubjectId = null;
      _selectedSubjectName = null;
      _classSubjects = [];
      _students = [];
      _focusNodes.clear();
      _controllers.clear();
    });

    try {
      List<Map<String, dynamic>> subjects = [];

      if (_userRole == 'admin') {
        subjects = await _supabase
            .from('class_subjects')
            .select('id, subject_name')
            .eq('school_id', _schoolId!)
            .eq('class_id', classId)
            .order('subject_name');
      } else {
        // Teacher Logic: Get the assigned subject UUIDs for this specific class
        final assignments = await _supabase
            .from('staff_assignments')
            .select('subject_id')
            .eq('staff_id', _userId!)
            .eq('class_id', classId);

        final Set<String> uniqueSubjectIds = {};
        for (var a in assignments) {
          if (a['subject_id'] != null) {
            uniqueSubjectIds.add(a['subject_id'].toString());
          }
        }

        if (uniqueSubjectIds.isNotEmpty) {
          final freshSubjectsData = await _supabase
              .from('class_subjects')
              .select('id, subject_name')
              .inFilter('id', uniqueSubjectIds.toList())
              .order('subject_name');

          subjects = List<Map<String, dynamic>>.from(freshSubjectsData);
        }
      }

      if (mounted) {
        setState(() {
          _classSubjects = subjects;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        showAuthErrorDialog("Subject Fetch Error: $e");
      }
    }
  }

  Future<void> _fetchStudentsAndScores() async {
    if (_selectedClassId == null || _selectedSubjectId == null) return;

    setState(() {
      _isLoading = true;
      _focusNodes.clear();
      _controllers.clear();
    });

    try {
      // 1. Get all active students in the class via UUID
      final studentsData = await _supabase
          .from('students')
          .select('id, first_name, last_name, admission_no')
          .eq('school_id', _schoolId!)
          .eq('class_id', _selectedClassId!)
          .eq('is_active', true)
          .order('first_name');

      // 2. Get existing scores via UUID
      final existingScoresData = await _supabase
          .from('exam_scores')
          .select(
            'id, student_id, ca_attendance, ca_assignment, ca_midterm, exam_score',
          )
          .eq('school_id', _schoolId!)
          .eq('class_id', _selectedClassId!)
          .eq('subject_id', _selectedSubjectId!)
          .eq('academic_session', _selectedSession!)
          .eq('term', _selectedTerm!);

      final Map<String, Map<String, dynamic>> existingScoreMap = {
        for (var score in existingScoresData)
          score['student_id'].toString(): score,
      };

      final List<StudentScore> combinedList = [];
      for (var student in studentsData) {
        final String sId = student['id'].toString();
        final existing = existingScoreMap[sId];

        combinedList.add(
          StudentScore(
            id: sId,
            name: "${student['first_name']} ${student['last_name']}",
            admissionNo: student['admission_no'] ?? 'N/A',
            resultId: existing?['id'],
            caAttendance:
                double.tryParse(
                  existing?['ca_attendance']?.toString() ?? '0',
                ) ??
                0,
            caAssignment:
                double.tryParse(
                  existing?['ca_assignment']?.toString() ?? '0',
                ) ??
                0,
            caMidterm:
                double.tryParse(existing?['ca_midterm']?.toString() ?? '0') ??
                0,
            examScore:
                double.tryParse(existing?['exam_score']?.toString() ?? '0') ??
                0,
          ),
        );
      }

      if (mounted) {
        setState(() {
          _students = combinedList;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        showAuthErrorDialog("Failed to load student list.");
      }
    }
  }

  // 🚨 FIXED: Smart Split into Insert vs Upsert to bypass 400 errors
  Future<void> _saveAllScores() async {
    if (_selectedClassId == null ||
        _selectedSubjectId == null ||
        _students.isEmpty) {
      return;
    }

    setState(() => _isSaving = true);

    try {
      List<Map<String, dynamic>> toInsert = [];
      List<Map<String, dynamic>> toUpdate = [];

      for (var s in _students) {
        final Map<String, dynamic> rowData = {
          'school_id': _schoolId,
          'student_id': s.id,
          'academic_session': _selectedSession,
          'term': _selectedTerm,
          'class_id': _selectedClassId,
          'subject_id': _selectedSubjectId,
          'class_level': _selectedClassName,
          'subject_name': _selectedSubjectName,
          'ca_attendance': s.caAttendance,
          'ca_assignment': s.caAssignment,
          'ca_midterm': s.caMidterm,
          'exam_score': s.examScore,
          'total_score': s.total,
          'grade': s.grade,
          'remark': s.remark,
          'last_edited_by': _userId,
        };

        if (s.resultId != null) {
          rowData['id'] = s.resultId;
          toUpdate.add(rowData);
        } else {
          toInsert.add(rowData);
        }
      }

      // 🚨 SMART SPLIT: Insert new records vs Update existing ones to bypass 400 Errors
      if (toInsert.isNotEmpty) {
        await _supabase.from('exam_scores').insert(toInsert);
      }
      if (toUpdate.isNotEmpty) {
        await _supabase.from('exam_scores').upsert(toUpdate, onConflict: 'id');
      }

      if (mounted) {
        showSuccessDialog("Success", "All scores saved successfully.");
        // Refetch to ensure we grab the freshly created result IDs
        _fetchStudentsAndScores();
      }
    } catch (e) {
      if (mounted) {
        showAuthErrorDialog("Failed to save scores. Check connection.");
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC);
    Color cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    Color primaryColor = Theme.of(context).primaryColor;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text(
          "Result Computation",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 0,
      ),
      body: Column(
        children: [
          // --- TOP FILTER PANEL ---
          Container(
            padding: const EdgeInsets.all(16),
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
                Row(
                  children: [
                    Expanded(
                      child: _buildDropdown(
                        hint: "Session",
                        value: _selectedSession,
                        items: _sessions,
                        isDark: isDark,
                        primaryColor: primaryColor,
                        onChanged: _userRole == 'admin'
                            ? (val) {
                                setState(() {
                                  _selectedSession = val;
                                  _fetchStudentsAndScores();
                                });
                              }
                            : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildDropdown(
                        hint: "Term",
                        value: _selectedTerm,
                        items: _terms,
                        isDark: isDark,
                        primaryColor: primaryColor,
                        onChanged: _userRole == 'admin'
                            ? (val) {
                                setState(() {
                                  _selectedTerm = val;
                                  _fetchStudentsAndScores();
                                });
                              }
                            : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildClassDropdown(
                        hint: "Select Class",
                        value: _selectedClassId,
                        items: _activeClasses,
                        isDark: isDark,
                        primaryColor: primaryColor,
                        onChanged: (val) {
                          if (val != null) {
                            final clsName = _activeClasses.firstWhere(
                              (c) => c['id'].toString() == val,
                            )['name'];
                            setState(() {
                              _selectedClassId = val;
                              _selectedClassName = clsName;
                            });
                            _fetchSubjectsForClass(val);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildSubjectDropdown(
                        hint: "Select Subject",
                        value: _selectedSubjectId,
                        items: _classSubjects,
                        isDark: isDark,
                        primaryColor: primaryColor,
                        onChanged: (val) {
                          if (val != null) {
                            final subName = _classSubjects.firstWhere(
                              (s) => s['id'].toString() == val,
                            )['subject_name'];
                            setState(() {
                              _selectedSubjectId = val;
                              _selectedSubjectName = subName;
                            });
                            _fetchStudentsAndScores();
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // --- STUDENTS LIST ---
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator(color: primaryColor))
                : _selectedClassId == null || _selectedSubjectId == null
                ? const Center(
                    child: Text(
                      "Select a class and subject to begin grading.",
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : _students.isEmpty
                ? const Center(
                    child: Text(
                      "No students found in this class.",
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _students.length,
                    itemBuilder: (ctx, i) {
                      return _buildStudentGradeCard(
                        _students[i],
                        i,
                        isDark,
                        primaryColor,
                      );
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: _students.isNotEmpty
          ? Container(
              padding: const EdgeInsets.all(16),
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
              child: SafeArea(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _isSaving ? null : _saveAllScores,
                  child: _isSaving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          "SAVE SCORES",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildDropdown({
    required String hint,
    required String? value,
    required List<String> items,
    required bool isDark,
    required Color primaryColor,
    required Function(String?)? onChanged,
  }) {
    bool isLocked = onChanged == null;
    return Container(
      decoration: BoxDecoration(
        color: isLocked
            ? (isDark ? Colors.white.withOpacity(0.02) : Colors.grey[200])
            : (isDark ? Colors.white.withOpacity(0.05) : Colors.grey[50]),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade300,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: value,
          hint: Padding(
            padding: const EdgeInsets.only(left: 10),
            child: Text(
              hint,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
          icon: Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Icon(
              isLocked ? Icons.lock_outline : Icons.arrow_drop_down,
              color: isLocked ? Colors.grey : primaryColor,
              size: isLocked ? 16 : 24,
            ),
          ),
          items: items
              .map(
                (e) => DropdownMenuItem(
                  value: e,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: Text(
                      e,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isLocked ? Colors.grey : null,
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
          onChanged: onChanged,
          dropdownColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        ),
      ),
    );
  }

  // Custom Dropdown for Classes using UUID mappings
  Widget _buildClassDropdown({
    required String hint,
    required String? value,
    required List<Map<String, dynamic>> items,
    required bool isDark,
    required Color primaryColor,
    required Function(String?)? onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey[50],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade300,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: value,
          hint: Padding(
            padding: const EdgeInsets.only(left: 10),
            child: Text(
              hint,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
          icon: Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Icon(Icons.arrow_drop_down, color: primaryColor),
          ),
          items: items
              .map(
                (c) => DropdownMenuItem<String>(
                  value: c['id'].toString(),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: Text(
                      c['name'],
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
          onChanged: onChanged,
          dropdownColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        ),
      ),
    );
  }

  // Custom Dropdown for Subjects using UUID mappings
  Widget _buildSubjectDropdown({
    required String hint,
    required String? value,
    required List<Map<String, dynamic>> items,
    required bool isDark,
    required Color primaryColor,
    required Function(String?)? onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: items.isEmpty
            ? (isDark ? Colors.white.withOpacity(0.02) : Colors.grey[200])
            : (isDark ? Colors.white.withOpacity(0.05) : Colors.grey[50]),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade300,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: value,
          hint: Padding(
            padding: const EdgeInsets.only(left: 10),
            child: Text(
              hint,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
          icon: Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Icon(
              items.isEmpty ? Icons.lock_outline : Icons.arrow_drop_down,
              color: items.isEmpty ? Colors.grey : primaryColor,
              size: items.isEmpty ? 16 : 24,
            ),
          ),
          items: items
              .map(
                (s) => DropdownMenuItem<String>(
                  value: s['id'].toString(),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: Text(
                      s['subject_name'],
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
          onChanged: items.isEmpty ? null : onChanged,
          dropdownColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        ),
      ),
    );
  }

  Widget _buildStudentGradeCard(
    StudentScore s,
    int index,
    bool isDark,
    Color primaryColor,
  ) {
    // Initialize persistent controllers to prevent typing format jumps
    if (!_controllers.containsKey(s.id)) {
      String fmt(double val) {
        if (val == 0) return "";
        String str = val.toStringAsFixed(1);
        return str.endsWith(".0") ? str.substring(0, str.length - 2) : str;
      }

      _controllers[s.id] = [
        TextEditingController(text: fmt(s.caAttendance)),
        TextEditingController(text: fmt(s.caAssignment)),
        TextEditingController(text: fmt(s.caMidterm)),
        TextEditingController(text: fmt(s.examScore)),
      ];
    }

    if (!_focusNodes.containsKey(s.id)) {
      _focusNodes[s.id] = List.generate(4, (_) => FocusNode());
    }

    final ctrls = _controllers[s.id]!;
    final nodes = _focusNodes[s.id]!;

    final ctrlAtt = ctrls[0];
    final ctrlAss = ctrls[1];
    final ctrlMid = ctrls[2];
    final ctrlExm = ctrls[3];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Header: Name & Total
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "${index + 1}. ${s.name.toUpperCase()}",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        s.admissionNo,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: _getGradeColor(s.grade).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "${s.total.toStringAsFixed(1)} ",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        "(${s.grade})",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _getGradeColor(s.grade),
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),

            // Input Fields
            Row(
              children: [
                Expanded(
                  child: _buildScoreInput(
                    label: "Att (5)",
                    ctrl: ctrlAtt,
                    focusNode: nodes[0],
                    maxVal: 5,
                    isDark: isDark,
                    onChanged: (val) {
                      setState(() => s.caAttendance = val);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildScoreInput(
                    label: "Ass (10)",
                    ctrl: ctrlAss,
                    focusNode: nodes[1],
                    maxVal: 10,
                    isDark: isDark,
                    onChanged: (val) {
                      setState(() => s.caAssignment = val);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildScoreInput(
                    label: "Mid (25)",
                    ctrl: ctrlMid,
                    focusNode: nodes[2],
                    maxVal: 25,
                    isDark: isDark,
                    onChanged: (val) {
                      setState(() => s.caMidterm = val);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2, // Make Exam wider
                  child: _buildScoreInput(
                    label: "Exam (60)",
                    ctrl: ctrlExm,
                    focusNode: nodes[3],
                    maxVal: 60,
                    isDark: isDark,
                    onChanged: (val) {
                      setState(() => s.examScore = val);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScoreInput({
    required String label,
    required TextEditingController ctrl,
    required FocusNode focusNode,
    required double maxVal,
    required bool isDark,
    required Function(double) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 40,
          child: TextField(
            controller: ctrl,
            focusNode: focusNode,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              filled: true,
              fillColor: isDark ? Colors.black26 : Colors.grey[100],
              contentPadding: EdgeInsets.zero,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (val) {
              double num = double.tryParse(val) ?? 0;
              if (num > maxVal) {
                num = maxVal; // Prevent entering score higher than max
                ctrl.text = maxVal.toStringAsFixed(0); // Clamp visually
                ctrl.selection = TextSelection.fromPosition(
                  TextPosition(offset: ctrl.text.length),
                );
              }
              onChanged(num);
            },
          ),
        ),
      ],
    );
  }

  Color _getGradeColor(String grade) {
    switch (grade) {
      case 'A':
        return Colors.green;
      case 'B':
        return Colors.blue;
      case 'C':
        return Colors.orange;
      case 'D':
        return Colors.deepOrange;
      case 'E':
        return Colors.redAccent;
      case 'F':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}
