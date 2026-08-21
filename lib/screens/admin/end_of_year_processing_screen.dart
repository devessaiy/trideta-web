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

  // Global Calendar
  String _currentSession = "";
  late String _nextSession;
  final String _nextTerm = "1st Term"; // Hardcoded reset

  // Pipeline State
  List<Map<String, dynamic>> _allClasses = [];
  String _terminalAction = 'graduate'; // 'graduate' or 'create_class'
  final _newClassNameController = TextEditingController();

  // Unified Analytics Results (RAM)
  List<Map<String, dynamic>> _classSummaries = [];
  int _totalPromoted = 0;
  int _totalRetained = 0;
  int _totalGraduating = 0;
  double _totalDebtToLock = 0.0;

  // Payloads for Atomic Server-Side Execution
  final List<Map<String, dynamic>> _promotionsPayload = [];
  final List<String> _graduationsPayload = [];
  final List<Map<String, dynamic>> _debtsPayload = [];

  @override
  void initState() {
    super.initState();
    _fetchInitialData();
  }

  String _calculateNextSession(String session) {
    try {
      List<String> parts = session.split('/');
      int startYear = int.parse(parts[0]);
      int endYear = int.parse(parts[1]);
      return "${startYear + 1}/${endYear + 1}";
    } catch (e) {
      int currentYear = DateTime.now().year;
      return "$currentYear/${currentYear + 1}";
    }
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

      // Fetch Global Calendar
      final schoolData = await _supabase
          .from('schools')
          .select('current_session, current_term')
          .eq('id', _schoolId!)
          .single();

      _currentSession = schoolData['current_session'] ?? "2025/2026";
      String currentTerm = schoolData['current_term'] ?? "";
      _nextSession = _calculateNextSession(_currentSession);

      // ==========================================
      // 🚨 END OF YEAR CONSTRAINT LOGIC
      // ==========================================
      if (currentTerm != '3rd Term') {
        if (mounted) {
          setState(() => _isLoading = false);
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Row(
                children: [
                  Icon(Icons.block_rounded, color: Colors.redAccent, size: 28),
                  SizedBox(width: 10),
                  Text(
                    "Action Locked",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.redAccent,
                    ),
                  ),
                ],
              ),
              content: Text(
                "You cannot run End of Year Proceedings during the $currentTerm.\n\nPlease use the 'End of Term Proceedings' module to advance the term first.",
                style: const TextStyle(height: 1.5, fontSize: 14),
              ),
              actions: [
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.pop(
                      context,
                    ); // Kick admin completely off the screen
                  },
                  child: const Text(
                    "Go Back",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          );
        }
        return;
      }
      // ==========================================

      // Fetch Classes Ordered by Hierarchy
      final classesData = await _supabase
          .from('classes')
          .select('id, name, list_order, promotion_criteria')
          .eq('school_id', _schoolId!)
          .order('list_order', ascending: true);

      if (mounted) {
        setState(() {
          _allClasses = List<Map<String, dynamic>>.from(classesData).map((c) {
            return {
              'id': c['id'].toString(),
              'name': c['name'].toString(),
              'list_order': c['list_order'],
              'promotion_criteria':
                  c['promotion_criteria'] ??
                  {'pass_mark': 40, 'core_subjects': []},
            };
          }).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        showAuthErrorDialog("Failed to load school progression pipeline.");
      }
    }
  }

  // ===========================================================================
  // 🚨 THE UNIFIED SCHOOL-WIDE AUDIT (RAM)
  // ===========================================================================
  Future<void> _runUnifiedAnalytics() async {
    if (_allClasses.isEmpty) {
      showAuthErrorDialog("No classes found to process.");
      return;
    }

    if (_terminalAction == 'create_class' &&
        _newClassNameController.text.trim().isEmpty) {
      showAuthErrorDialog("Please enter a name for the new terminal class.");
      return;
    }

    setState(() {
      _isAnalyzing = true;
      _classSummaries.clear();
      _promotionsPayload.clear();
      _graduationsPayload.clear();
      _debtsPayload.clear();
      _totalPromoted = 0;
      _totalRetained = 0;
      _totalGraduating = 0;
      _totalDebtToLock = 0.0;
    });

    try {
      // 1. Fetch Shared Dependencies
      final studentsData = await _supabase
          .from('students')
          .select(
            'id, first_name, last_name, category, class_id, wallet_balance',
          )
          .eq('school_id', _schoolId!);
      final txData = await _supabase
          .from('transactions')
          .select('student_id, fee_id, category, amount, academic_term')
          .eq('school_id', _schoolId!)
          .eq('academic_session', _currentSession);
      final allFeesRes = await _supabase
          .from('fee_structures')
          .select()
          .eq('school_id', _schoolId!)
          .eq('academic_session', _currentSession);
      final allFees = List<Map<String, dynamic>>.from(allFeesRes);

      List<Map<String, dynamic>> summaries = [];

      // 2. Process Class by Class
      for (int i = 0; i < _allClasses.length; i++) {
        var currentClass = _allClasses[i];
        String currentClassId = currentClass['id'];
        String currentClassName = currentClass['name'];

        final classGrades = await _fetchClassGrades(
          currentClassId,
          _currentSession,
        );

        String destinationName;
        String? destinationId;
        bool isTerminal = i == _allClasses.length - 1;

        if (isTerminal) {
          destinationName = _terminalAction == 'graduate'
              ? "GRADUATION"
              : _newClassNameController.text.trim().toUpperCase();
        } else {
          destinationName = _allClasses[i + 1]['name'];
          destinationId = _allClasses[i + 1]['id'];
        }

        Map<String, dynamic> promoCriteria = currentClass['promotion_criteria'];
        double passMark = (promoCriteria['pass_mark'] ?? 40).toDouble();
        List<String> coreSubjects = List<String>.from(
          promoCriteria['core_subjects'] ?? [],
        );

        var classStudents = studentsData
            .where((s) => s['class_id'] == currentClassId)
            .toList();

        // 🚨 PREVENTING DOUBLE-COUNTING: Since Term 1 and 2 lock debts natively, End Of Year ONLY evaluates 3rd Term fees!
        var classFees = allFees.where((f) {
          String fTerm = (f['academic_term'] ?? 'All Terms').toString();
          return (_doesItApply(f['applicable_class_ids'], currentClassId) ||
                  _doesItApply(f['applicable_classes'], currentClassName)) &&
              fTerm == '3rd Term';
        }).toList();

        int classPromoted = 0;
        int classRetained = 0;
        int classGraduating = 0;

        for (var student in classStudents) {
          // --- DEBT CHECK WITH WALLET INCLUDED ---
          double totalUnpaid = 0.0;
          String sCategory = (student['category'] ?? '').toString();

          for (var fee in classFees) {
            if (_doesItApply(
              fee['applicable_categories'],
              sCategory,
              isCategory: true,
            )) {
              String feeName = (fee['fee_name'] ?? '').toString();
              double expected = (fee['amount'] ?? 0).toDouble();
              double paid = 0.0;
              for (var tx in txData) {
                String txTerm = (tx['academic_term'] ?? 'All Terms').toString();
                if (txTerm == '3rd Term' || txTerm == 'All Terms') {
                  if (tx['student_id'] == student['id'] &&
                      (tx['fee_id'] == fee['id'] ||
                          tx['category'].toString().toLowerCase().trim() ==
                              feeName.toLowerCase().trim())) {
                    paid += (tx['amount'] ?? 0).toDouble();
                  }
                }
              }
              double remaining = expected - paid;
              if (remaining > 0) totalUnpaid += remaining;
            }
          }

          if (totalUnpaid > 0) {
            // 🚨 FLAWLESS MATH: We pass 'unpaid_amount' directly to the RPC.
            // The server natively updates: wallet_balance = wallet_balance - unpaid_amount
            _debtsPayload.add({
              'student_id': student['id'],
              'unpaid_amount': totalUnpaid,
            });
            _totalDebtToLock += totalUnpaid;
          }

          // --- ACADEMIC CHECK ---
          bool hasPassed = true;
          Map<String, dynamic> grades = classGrades[student['id']] ?? {};
          double average = (grades['average'] ?? 0.0).toDouble();

          if (average < passMark) {
            hasPassed = false;
          } else {
            for (String coreSub in coreSubjects) {
              double coreScore =
                  (grades['subjects']?[coreSub.toUpperCase().trim()] ?? 0.0)
                      .toDouble();
              if (coreScore < passMark) {
                hasPassed = false;
                break;
              }
            }
          }

          if (hasPassed) {
            if (isTerminal && _terminalAction == 'graduate') {
              _graduationsPayload.add(student['id']);
              classGraduating++;
              _totalGraduating++;
            } else {
              _promotionsPayload.add({
                'student_id': student['id'],
                'new_class_level': destinationName,
                'new_class_id': destinationId,
              });
              classPromoted++;
              _totalPromoted++;
            }
          } else {
            // Retained
            _promotionsPayload.add({
              'student_id': student['id'],
              'new_class_level': currentClassName,
              'new_class_id': currentClassId,
            });
            classRetained++;
            _totalRetained++;
          }
        }

        summaries.add({
          'class_name': currentClassName,
          'destination': destinationName,
          'promoted': classPromoted,
          'retained': classRetained,
          'graduating': classGraduating,
        });
      }

      if (mounted) {
        setState(() {
          _classSummaries = summaries;
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

  Future<Map<String, Map<String, dynamic>>> _fetchClassGrades(
    String classId,
    String targetSession,
  ) async {
    final response = await _supabase
        .from('exam_scores')
        .select('student_id, subject_name, total_score')
        .eq('class_id', classId)
        .eq('academic_session', targetSession);

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
    for (String sId in rawScores.keys) {
      double overallSum = 0;
      int subjectCount = 0;
      Map<String, double> subjectAverages = {};
      for (String subName in rawScores[sId]!.keys) {
        List<double> termScores = rawScores[sId]![subName]!;
        double subAvg = termScores.reduce((a, b) => a + b) / termScores.length;
        subjectAverages[subName] = subAvg;
        overallSum += subAvg;
        subjectCount++;
      }
      finalGrades[sId] = {
        'average': subjectCount > 0 ? (overallSum / subjectCount) : 0.0,
        'subjects': subjectAverages,
      };
    }
    return finalGrades;
  }

  // ===========================================================================
  // 🚨 THE SAFE ATOMIC TRIGGER (POWERED BY SERVER-SIDE RPC)
  // ===========================================================================
  Future<void> _executeUnifiedTrigger() async {
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
              "IRREVERSIBLE SCHOOL-WIDE ACTION",
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
                  "You are about to safely advance the entire school to the next academic session. Debts will be locked to wallets, students will be promoted/retained, and seniors will be processed. To proceed, type CONFIRM below.",
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
                child: const Text("EXECUTE PIPELINE"),
              ),
            ],
          ),
        ) ??
        false;

    if (!isConfirmed) return;

    setState(() => _isExecuting = true);

    try {
      // 1. Pack New Classes if needed
      List<Map<String, dynamic>> newClassesPayload = [];
      if (_terminalAction == 'create_class' &&
          _newClassNameController.text.trim().isNotEmpty) {
        newClassesPayload.add({
          'name': _newClassNameController.text.trim().toUpperCase(),
          'list_order': _allClasses.length,
          'promotion_criteria': {'pass_mark': 40, 'core_subjects': []},
        });
      }

      // 🚨 2. FIRE THE SERVER-SIDE ATOMIC ENGINE (ONE NETWORK CALL)
      await _supabase.rpc(
        'execute_end_of_year_proceedings',
        params: {
          'p_school_id': _schoolId,
          'p_new_session': _nextSession,
          'p_new_term': _nextTerm,
          'p_new_classes': newClassesPayload,
          'p_promotions': _promotionsPayload,
          'p_graduations': _graduationsPayload,
          'p_debts': _debtsPayload,
        },
      );

      if (mounted) {
        showSuccessDialog(
          "Success",
          "School successfully advanced to $_nextSession. The financial engine has safely preserved the historical records.",
        );
        setState(() {
          _classSummaries.clear();
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

  // Matching Utils
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
        (cleanStudentData.isEmpty || cleanStudentData == 'notfound')) {
      cleanStudentData = 'regular';
    }
    if (cleanStudentData.isEmpty || cleanStudentData == 'notfound') {
      return false;
    }
    if (columnData == null) return true;

    if (columnData is String && columnData.startsWith('[')) {
      try {
        List<dynamic> parsedList = jsonDecode(columnData);
        if (parsedList.isEmpty) return true;
        for (var item in parsedList) {
          String cleanItem = isCategory
              ? item.toString().replaceAll(' ', '').toLowerCase()
              : _standardizeClass(item.toString());
          if (cleanItem == 'all' || cleanItem == cleanStudentData) return true;
        }
        return false;
      } catch (e) {
        // Fallback
      }
    }

    String colStr = isCategory
        ? columnData.toString().replaceAll(' ', '').toLowerCase()
        : _standardizeClass(columnData.toString());
    if (colStr.isEmpty ||
        colStr == 'all' ||
        colStr == '[]' ||
        colStr == '["all"]') {
      return true;
    }

    return colStr.contains(cleanStudentData);
  }

  // ===========================================================================
  // 🚨 FLAT UI BUILDER
  // ===========================================================================
  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    Color bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC);
    Color thickDividerColor = isDark ? Colors.black : Colors.grey.shade100;
    Color primaryColor = Theme.of(context).primaryColor;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: bgColor,
        body: Center(child: TridetaLoader(color: primaryColor)),
      );
    }

    if (_allClasses.isEmpty) {
      return Scaffold(
        backgroundColor: bgColor,
        appBar: AppBar(
          title: const Text("End of Year Processing"),
          backgroundColor: bgColor,
          elevation: 0,
        ),
        body: const Center(
          child: Text(
            "No classes configured. Please setup your school structure first.",
          ),
        ),
      );
    }

    String terminalClassName = _allClasses.last['name'];

    Widget mainContent = SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "STEP 1: UNIFIED PROGRESSION PIPELINE",
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                        color: Colors.grey,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "The system will automatically advance the school calendar and process all classes simultaneously based on their hierarchy.",
                      style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.grey.shade600,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 25),

                    // Calendar Advance UI
                    Row(
                      children: [
                        Expanded(
                          child: _buildInfoField(
                            "Closing Session",
                            _currentSession,
                            isDark,
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
                          child: _buildInfoField(
                            "Opening Session",
                            _nextSession,
                            isDark,
                            highlight: true,
                            color: primaryColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 25),

                    // Terminal Class Config
                    Text(
                      "TERMINAL CLASS ACTION: ${terminalClassName.toUpperCase()}",
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                        color: Colors.orange,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        "Graduate Seniors",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: const Text(
                        "Move to Alumni",
                        style: TextStyle(fontSize: 12),
                      ),
                      leading: Radio<String>(
                        value: 'graduate',
                        groupValue: _terminalAction,
                        activeColor: Colors.orange,
                        onChanged: (val) =>
                            setState(() => _terminalAction = val!),
                      ),
                      onTap: () => setState(() => _terminalAction = 'graduate'),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        "Create Next Class",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: const Text(
                        "Expand hierarchy",
                        style: TextStyle(fontSize: 12),
                      ),
                      leading: Radio<String>(
                        value: 'create_class',
                        groupValue: _terminalAction,
                        activeColor: Colors.orange,
                        onChanged: (val) =>
                            setState(() => _terminalAction = val!),
                      ),
                      onTap: () =>
                          setState(() => _terminalAction = 'create_class'),
                    ),

                    if (_terminalAction == 'create_class') ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: _newClassNameController,
                        textCapitalization: TextCapitalization.characters,
                        decoration: InputDecoration(
                          labelText: "Name of new class (e.g. SS 2)",
                          filled: true,
                          fillColor: isDark
                              ? Colors.white.withValues(alpha: 0.05)
                              : Colors.grey.shade100,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 25),
                    SizedBox(
                      width: double.infinity,
                      height: 55,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: primaryColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: _isAnalyzing ? null : _runUnifiedAnalytics,
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
                              ? "ANALYZING ENTIRE SCHOOL..."
                              : "GENERATE PIPELINE PREVIEW",
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              if (_classSummaries.isNotEmpty) ...[
                const SizedBox(height: 30),
                Container(height: 8, color: thickDividerColor),
                const SizedBox(height: 20),

                // STEP 2: ANALYTICS RESULTS
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      _buildMetricCard(
                        "PROMOTED",
                        "$_totalPromoted",
                        Colors.green,
                        isDark,
                      ),
                      const SizedBox(width: 8),
                      _buildMetricCard(
                        "RETAINED",
                        "$_totalRetained",
                        Colors.orange,
                        isDark,
                      ),
                      const SizedBox(width: 8),
                      _buildMetricCard(
                        "GRADUATING",
                        "$_totalGraduating",
                        Colors.purple,
                        isDark,
                      ),
                      const SizedBox(width: 8),
                      _buildMetricCard(
                        "DEBT LOCKED",
                        "₦${_totalDebtToLock.toStringAsFixed(0)}",
                        Colors.redAccent,
                        isDark,
                      ),
                    ],
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.redAccent.withValues(alpha: 0.3),
                      ),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 18,
                          color: Colors.redAccent,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            "The debt is calculated only for the current term (3rd term). This amount will be added as a negative value to the respective students’ perpetual wallets.",
                            style: TextStyle(
                              color: Colors.redAccent,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 30),

                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _classSummaries.length,
                  itemBuilder: (ctx, i) {
                    var sum = _classSummaries[i];
                    bool isGrad = sum['destination'] == 'GRADUATION';
                    return Column(
                      children: [
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 8,
                          ),
                          title: Row(
                            children: [
                              Text(
                                sum['class_name'],
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 8),
                                child: Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 16,
                                  color: Colors.grey,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: isGrad
                                      ? Colors.purple.withValues(alpha: 0.1)
                                      : primaryColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  sum['destination'],
                                  style: TextStyle(
                                    color: isGrad
                                        ? Colors.purple
                                        : primaryColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              "${sum['promoted']} Promoted • ${sum['retained']} Retained${isGrad ? " • ${sum['graduating']} Graduating" : ""}",
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(left: 24, right: 24),
                          child: Divider(
                            height: 1,
                            color: isDark
                                ? Colors.white10
                                : Colors.grey.shade200,
                          ),
                        ),
                      ],
                    );
                  },
                ),

                const SizedBox(height: 30),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: SizedBox(
                    width: double.infinity,
                    height: 60,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: _isExecuting ? null : _executeUnifiedTrigger,
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
                            : "EXECUTE SCHOOL-WIDE PROCEEDING",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ],
          ),
        ),
      ),
    );

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
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth > 800) {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: Container(
                  decoration: BoxDecoration(
                    color: bgColor,
                    border: Border.symmetric(
                      vertical: BorderSide(
                        color: isDark ? Colors.white10 : Colors.grey.shade200,
                      ),
                    ),
                  ),
                  child: mainContent,
                ),
              ),
            );
          } else {
            return mainContent;
          }
        },
      ),
    );
  }

  Widget _buildInfoField(
    String label,
    String value,
    bool isDark, {
    bool highlight = false,
    Color? color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: highlight ? color : Colors.grey.shade500,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: highlight ? color : (isDark ? Colors.white : Colors.black87),
          ),
        ),
      ],
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
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 9,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            FittedBox(
              child: Text(
                value,
                style: TextStyle(
                  color: color,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
