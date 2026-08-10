import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:trideta_v2/utils/auth_error_handler.dart';
import 'package:trideta_v2/widgets/trideta_loader.dart';

class EndOfYearProcessingScreen extends StatefulWidget {
  const EndOfYearProcessingScreen({super.key});

  @override
  State<EndOfYearProcessingScreen> createState() =>
      _EndOfYearProcessingScreenState();
}

class _EndOfYearProcessingScreenState extends State<EndOfYearProcessingScreen>
    with AuthErrorHandler {
  final _supabase = Supabase.instance.client;

  bool _isLoading = true;
  bool _isAnalyzing = false;
  bool _isExecuting = false;
  String? _schoolId;

  List<Map<String, dynamic>> _allClasses = [];
  String? _sourceClassId;
  String? _destinationClassId;

  late String _targetSession;
  final String _targetTerm = "1st Term"; // Always resets to 1st Term

  // Analysis Results (RAM)
  List<Map<String, dynamic>> _analyzedStudents = [];
  double _totalDebtToLock = 0.0;
  int _promotedCount = 0;
  int _retainedCount = 0;

  @override
  void initState() {
    super.initState();
    _targetSession = _generateDynamicSessions().last;
    _fetchInitialData();
  }

  List<String> _generateDynamicSessions() {
    int currentYear = DateTime.now().year;
    List<String> sessions = [];
    for (int y = 2023; y <= currentYear + 2; y++) {
      sessions.add("$y/${y + 1}");
    }
    return sessions;
  }

  Future<void> _fetchInitialData() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final profile = await _supabase
          .from('profiles')
          .select('school_id')
          .eq('id', user.id)
          .single();
      _schoolId = profile['school_id'];

      final schoolData = await _supabase
          .from('schools')
          .select('current_session, current_term')
          .eq('id', _schoolId!)
          .maybeSingle();

      String globalSession = schoolData?['current_session'] ?? 'Unknown';
      String globalTerm = schoolData?['current_term'] ?? 'Unknown';

      final classesData = await _supabase
          .from('classes')
          .select(
            'id, name, override_session, override_term, promotion_criteria',
          )
          .eq('school_id', _schoolId!)
          .order('list_order', ascending: true);

      if (mounted) {
        setState(() {
          _allClasses = List<Map<String, dynamic>>.from(classesData).map((c) {
            return {
              'id': c['id'].toString(),
              'name': c['name'],
              'current_session': c['override_session'] ?? globalSession,
              'current_term': c['override_term'] ?? globalTerm,
              'promotion_criteria':
                  c['promotion_criteria'] ??
                  {'pass_mark': 40, 'core_subjects': []},
            };
          }).toList();

          if (_allClasses.isNotEmpty) {
            _sourceClassId = _allClasses.first['id'];
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        showAuthErrorDialog("Failed to load school data.");
      }
    }
  }

  // ===========================================================================
  // 🚨 THE GRAND AUDIT (RAM CALCULATIONS)
  // ===========================================================================
  Future<void> _runAnalytics() async {
    if (_sourceClassId == null) return;

    setState(() {
      _isAnalyzing = true;
      _analyzedStudents.clear();
      _totalDebtToLock = 0.0;
      _promotedCount = 0;
      _retainedCount = 0;
    });

    try {
      final sourceClass = _allClasses.firstWhere(
        (c) => c['id'] == _sourceClassId,
      );
      Map<String, dynamic> promoCriteria = sourceClass['promotion_criteria'];
      double passMark = (promoCriteria['pass_mark'] ?? 40).toDouble();
      List<String> coreSubjects = List<String>.from(
        promoCriteria['core_subjects'] ?? [],
      );

      // 1. Fetch Students
      final studentsData = await _supabase
          .from('students')
          .select('id, first_name, last_name, category')
          .eq('class_id', _sourceClassId!);

      if (studentsData.isEmpty) {
        showAuthErrorDialog("No students found in ${sourceClass['name']}.");
        setState(() => _isAnalyzing = false);
        return;
      }

      final studentIds = studentsData.map((s) => s['id']).toList();

      // 2. Fetch 3rd Term Fees & Transactions
      final allFeesRes = await _supabase
          .from('fee_structures')
          .select()
          .eq('school_id', _schoolId!);
      final allFees = List<Map<String, dynamic>>.from(allFeesRes);

      final classFees = allFees.where((fee) {
        if (fee['academic_session'] != sourceClass['current_session'])
          return false;
        if (fee['academic_term'] != sourceClass['current_term'] &&
            fee['academic_term'] != 'All Terms')
          return false;

        bool classMatch = false;
        final List<dynamic>? classIdsList = fee['applicable_class_ids'];
        if (classIdsList != null && classIdsList.isNotEmpty) {
          classMatch = classIdsList.contains(_sourceClassId);
        } else {
          classMatch = _doesItApply(
            fee['applicable_classes'],
            sourceClass['name'],
          );
        }
        return classMatch;
      }).toList();

      final txData = await _supabase
          .from('transactions')
          .select('student_id, fee_id, category, amount')
          .eq('academic_session', sourceClass['current_session'])
          .eq('academic_term', sourceClass['current_term'])
          .inFilter('student_id', studentIds);

      // 3. 🚨 NEW: Fetch Live Cumulative Grades from the Database
      final studentGrades = await _fetchStudentGrades(
        studentIds,
        sourceClass['current_session'],
      );

      List<Map<String, dynamic>> analyticsBuffer = [];

      for (var student in studentsData) {
        // --- DEBT CHECK ---
        double totalUnpaid = 0.0;
        String sCategory = (student['category'] ?? '').toString();

        for (var fee in classFees) {
          if (_doesItApply(
            fee['applicable_categories'],
            sCategory,
            isCategory: true,
          )) {
            double expected = (fee['amount'] ?? 0).toDouble();
            double paid = 0.0;

            for (var tx in txData) {
              if (tx['student_id'] == student['id']) {
                if (tx['fee_id'] == fee['id'] ||
                    tx['category'] == fee['fee_name']) {
                  paid += (tx['amount'] ?? 0).toDouble();
                }
              }
            }
            double remaining = expected - paid;
            if (remaining > 0) totalUnpaid += remaining;
          }
        }

        // --- ACADEMIC CHECK ---
        bool hasPassed = true;
        Map<String, dynamic> grades = studentGrades[student['id']] ?? {};
        double average = (grades['average'] ?? 0.0).toDouble();

        // Check overall cumulative average
        if (average < passMark) {
          hasPassed = false;
        } else {
          // Check specific core subjects
          for (String coreSub in coreSubjects) {
            String cleanCore = coreSub.toUpperCase().trim();
            double coreScore = (grades['subjects']?[cleanCore] ?? 0.0)
                .toDouble();
            if (coreScore < passMark) {
              hasPassed = false;
              break;
            }
          }
        }

        if (hasPassed) {
          _promotedCount++;
        } else {
          _retainedCount++;
        }
        _totalDebtToLock += totalUnpaid;

        analyticsBuffer.add({
          'id': student['id'],
          'name': "${student['first_name']} ${student['last_name']}",
          'debt': totalUnpaid,
          'average': average,
          'passed': hasPassed,
        });
      }

      if (mounted) {
        setState(() {
          _analyzedStudents = analyticsBuffer;
          _isAnalyzing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isAnalyzing = false);
        showAuthErrorDialog("Analytics failed. Please check connection.");
      }
    }
  }

  // 🚨 THE LIVE DATABASE INTEGRATION
  Future<Map<String, Map<String, dynamic>>> _fetchStudentGrades(
    List<dynamic> studentIds,
    String targetSession,
  ) async {
    // 1. Fetch every exam score for these students across the entire session (all terms)
    final response = await _supabase
        .from('exam_scores')
        .select('student_id, subject_name, total_score')
        .eq('academic_session', targetSession)
        .inFilter('student_id', studentIds);

    // 2. Group the raw scores by Student -> Subject
    Map<String, Map<String, List<double>>> rawScores = {};

    for (var row in response) {
      String sId = row['student_id'].toString();
      String subName = (row['subject_name'] ?? '')
          .toString()
          .toUpperCase()
          .trim();
      double score = (row['total_score'] ?? 0).toDouble();

      if (!rawScores.containsKey(sId)) rawScores[sId] = {};
      if (!rawScores[sId]!.containsKey(subName)) rawScores[sId]![subName] = [];

      rawScores[sId]![subName]!.add(score);
    }

    Map<String, Map<String, dynamic>> finalGrades = {};

    // 3. Process the cumulative averages
    for (String sId in rawScores.keys) {
      double overallSum = 0;
      int subjectCount = 0;
      Map<String, double> subjectAverages = {};

      for (String subName in rawScores[sId]!.keys) {
        List<double> termScores = rawScores[sId]![subName]!;

        // Calculate the cumulative average for this specific subject across all terms
        double subAvg = termScores.reduce((a, b) => a + b) / termScores.length;

        subjectAverages[subName] = subAvg;
        overallSum += subAvg;
        subjectCount++;
      }

      // Calculate the overall cumulative average across all subjects
      double cumulativeAverage = subjectCount > 0
          ? (overallSum / subjectCount)
          : 0.0;

      finalGrades[sId] = {
        'average': cumulativeAverage,
        'subjects': subjectAverages,
      };
    }

    return finalGrades;
  }

  // ===========================================================================
  // 🚨 THE ATOMIC TRIGGER
  // ===========================================================================
  Future<void> _executeTrigger() async {
    if (_destinationClassId == null) {
      showAuthErrorDialog(
        "Please select a Destination Class for promoted students.",
      );
      return;
    }

    // Double Confirmation Type-to-Confirm Dialog
    final confirmController = TextEditingController();
    bool isConfirmed =
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            backgroundColor: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF1E1E1E)
                : Colors.white,
            title: const Text(
              "IRREVERSIBLE ACTION",
              style: TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "You are about to modify academic and financial records for an entire class. To proceed, type CONFIRM below.",
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: confirmController,
                  decoration: InputDecoration(
                    filled: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    hintText: "Type CONFIRM",
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text("CANCEL"),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                ),
                onPressed: () {
                  if (confirmController.text.trim().toUpperCase() ==
                      "CONFIRM") {
                    Navigator.pop(ctx, true);
                  }
                },
                child: const Text("EXECUTE"),
              ),
            ],
          ),
        ) ??
        false;

    if (!isConfirmed) return;

    setState(() => _isExecuting = true);

    try {
      final destClass = _allClasses.firstWhere(
        (c) => c['id'] == _destinationClassId,
      );
      List<Map<String, dynamic>> promotionsPayload = [];
      List<Map<String, dynamic>> debtsPayload = [];

      for (var student in _analyzedStudents) {
        if (student['debt'] > 0) {
          debtsPayload.add({
            'student_id': student['id'],
            'unpaid_amount': student['debt'],
          });
        }
        if (student['passed'] == true) {
          promotionsPayload.add({
            'student_id': student['id'],
            'new_class_id': destClass['id'],
            'new_class_level': destClass['name'],
          });
        }
      }

      // 🚨 ATOMIC FIRE
      await _supabase.rpc(
        'execute_end_of_year_proceedings',
        params: {
          'p_school_id': _schoolId,
          'p_source_class_id': _sourceClassId,
          'p_new_session': _targetSession,
          'p_new_term': _targetTerm,
          'p_promotions': promotionsPayload,
          'p_debts': debtsPayload,
        },
      );

      if (mounted) {
        showSuccessDialog(
          "Success",
          "End of year processing completed successfully.",
        );
        setState(() {
          _analyzedStudents.clear();
          _isExecuting = false;
        });
        _fetchInitialData();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isExecuting = false);
        showAuthErrorDialog(
          "Execution failed. Connection dropped or database error.",
        );
      }
    }
  }

  // Helper matching logic...
  String _standardizeClass(String val) {
    String v = val.replaceAll(' ', '').toLowerCase();
    v = v
        .replaceAll('one', '1')
        .replaceAll('two', '2')
        .replaceAll('three', '3');
    v = v
        .replaceAll('four', '4')
        .replaceAll('five', '5')
        .replaceAll('six', '6');
    v = v
        .replaceAll('seven', '7')
        .replaceAll('eight', '8')
        .replaceAll('nine', '9');
    return v;
  }

  bool _doesItApply(
    dynamic columnData,
    String studentData, {
    bool isCategory = false,
  }) {
    String cleanStudentData = isCategory
        ? studentData.replaceAll(' ', '').toLowerCase()
        : _standardizeClass(studentData);
    if (isCategory &&
        (cleanStudentData.isEmpty || cleanStudentData == 'notfound'))
      cleanStudentData = 'regular';
    if (cleanStudentData.isEmpty || cleanStudentData == 'notfound')
      return false;
    if (columnData == null) return true;

    String colStr = isCategory
        ? columnData.toString().replaceAll(' ', '').toLowerCase()
        : _standardizeClass(columnData.toString());
    if (colStr.isEmpty ||
        colStr == 'all' ||
        colStr == '[]' ||
        colStr == '["all"]')
      return true;

    if (columnData is List) {
      if (columnData.isEmpty) return true;
      for (var item in columnData) {
        String cleanItem = isCategory
            ? item.toString().replaceAll(' ', '').toLowerCase()
            : _standardizeClass(item.toString());
        if (cleanItem == 'all' || cleanItem == cleanStudentData) return true;
      }
      return false;
    }
    return colStr.contains(cleanStudentData);
  }

  // ===========================================================================
  // 🚨 UI BUILDER
  // ===========================================================================
  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC);
    Color cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    Color primaryColor = Theme.of(context).primaryColor;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: bgColor,
        body: Center(child: TridetaLoader(color: primaryColor)),
      );
    }

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text(
          "End of Year Processing",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: bgColor,
        foregroundColor: isDark ? Colors.white : const Color(0xFF1A1A2E),
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // STEP 1: CONFIGURATION
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isDark ? Colors.white10 : Colors.grey.shade200,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Step 1: Configure Progression Pipeline",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              isExpanded: true,
                              value: _sourceClassId,
                              dropdownColor: cardColor,
                              decoration: _inputStyle(
                                "Source Class (Current)",
                                isDark,
                              ),
                              items: _allClasses
                                  .map(
                                    (c) => DropdownMenuItem<String>(
                                      value: c['id'],
                                      child: Text(
                                        c['name'],
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (val) =>
                                  setState(() => _sourceClassId = val),
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16),
                            child: Icon(
                              Icons.arrow_forward_rounded,
                              color: Colors.grey,
                            ),
                          ),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              isExpanded: true,
                              value: _destinationClassId,
                              dropdownColor: cardColor,
                              decoration: _inputStyle(
                                "Destination Class (Promotion)",
                                isDark,
                              ),
                              items: _allClasses
                                  .map(
                                    (c) => DropdownMenuItem<String>(
                                      value: c['id'],
                                      child: Text(
                                        c['name'],
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (val) =>
                                  setState(() => _destinationClassId = val),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _targetSession,
                              dropdownColor: cardColor,
                              decoration: _inputStyle(
                                "New Academic Session",
                                isDark,
                              ),
                              items: _generateDynamicSessions()
                                  .map(
                                    (e) => DropdownMenuItem(
                                      value: e,
                                      child: Text(e),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (val) =>
                                  setState(() => _targetSession = val!),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              initialValue: "1st Term (Locked)",
                              enabled: false,
                              decoration: _inputStyle(
                                "New Academic Term",
                                isDark,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: primaryColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: _isAnalyzing ? null : _runAnalytics,
                          icon: _isAnalyzing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.analytics_rounded),
                          label: Text(
                            _isAnalyzing
                                ? "ANALYZING..."
                                : "GENERATE ANALYTICS PREVIEW",
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // STEP 2: ANALYTICS RESULTS
                if (_analyzedStudents.isNotEmpty) ...[
                  const SizedBox(height: 30),
                  Row(
                    children: [
                      _buildMetricCard(
                        "PROMOTED",
                        "$_promotedCount",
                        Colors.green,
                        isDark,
                      ),
                      const SizedBox(width: 16),
                      _buildMetricCard(
                        "RETAINED",
                        "$_retainedCount",
                        Colors.orange,
                        isDark,
                      ),
                      const SizedBox(width: 16),
                      _buildMetricCard(
                        "DEBT TO LOCK",
                        "₦${_totalDebtToLock.toStringAsFixed(0)}",
                        Colors.redAccent,
                        isDark,
                      ),
                    ],
                  ),
                  const SizedBox(height: 30),

                  Container(
                    height: 300,
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isDark ? Colors.white10 : Colors.grey.shade200,
                      ),
                    ),
                    child: ListView.builder(
                      itemCount: _analyzedStudents.length,
                      itemBuilder: (ctx, i) {
                        var s = _analyzedStudents[i];
                        bool passed = s['passed'];
                        return ListTile(
                          title: Text(
                            s['name'],
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            "Average: ${s['average'].toStringAsFixed(1)}% | Debt: ₦${s['debt']}",
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: passed
                                  ? Colors.green.withValues(alpha: 0.1)
                                  : Colors.orange.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              passed ? "PROMOTED" : "RETAINED",
                              style: TextStyle(
                                color: passed ? Colors.green : Colors.orange,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 40),
                  SizedBox(
                    width: double.infinity,
                    height: 60,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: _isExecuting ? null : _executeTrigger,
                      icon: _isExecuting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(
                              Icons.warning_rounded,
                              color: Colors.white,
                            ),
                      label: Text(
                        _isExecuting
                            ? "EXECUTING ATOMIC TRANSACTION..."
                            : "EXECUTE END OF YEAR PROCEEDING",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMetricCard(
    String label,
    String value,
    Color color,
    bool isDark,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 8),
            FittedBox(
              child: Text(
                value,
                style: TextStyle(
                  color: color,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputStyle(String label, bool isDark) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: isDark
          ? Colors.white.withValues(alpha: 0.05)
          : Colors.grey.shade50,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
        ),
      ),
    );
  }
}
