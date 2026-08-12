import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:file_saver/file_saver.dart';

import 'package:trideta_v2/utils/auth_error_handler.dart';
import 'package:trideta_v2/widgets/trideta_loader.dart';

class SessionArchiveScreen extends StatefulWidget {
  const SessionArchiveScreen({super.key});

  @override
  State<SessionArchiveScreen> createState() => _SessionArchiveScreenState();
}

class _SessionArchiveScreenState extends State<SessionArchiveScreen>
    with AuthErrorHandler {
  final _supabase = Supabase.instance.client;

  bool _isLoading = true;
  bool _isGenerating = false;

  String? _schoolId;

  List<Map<String, dynamic>> _allClasses = [];

  String? _selectedArchiveClassId;
  late String _selectedArchiveSession;
  late String _selectedArchiveTerm;

  @override
  void initState() {
    super.initState();
    final dynamicSessions = _generateDynamicSessions();
    _selectedArchiveSession = dynamicSessions.contains("2026/2027")
        ? "2026/2027"
        : dynamicSessions.first;
    _selectedArchiveTerm = "3rd Term";
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

      final classesData = await _supabase
          .from('classes')
          .select('id, name')
          .eq('school_id', _schoolId!)
          .order('list_order', ascending: true);

      if (mounted) {
        setState(() {
          _allClasses = List<Map<String, dynamic>>.from(classesData).map((c) {
            return {'id': c['id'].toString(), 'name': c['name'].toString()};
          }).toList();

          if (_allClasses.isNotEmpty) {
            _selectedArchiveClassId = _allClasses.first['id'];
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        showAuthErrorDialog(
          "Failed to load school data. Please check your connection.",
        );
      }
    }
  }

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

    String colStr = isCategory
        ? columnData.toString().replaceAll(' ', '').toLowerCase()
        : _standardizeClass(columnData.toString());
    if (colStr.isEmpty ||
        colStr == 'all' ||
        colStr == '[]' ||
        colStr == '["all"]') {
      return true;
    }

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

    try {
      List<dynamic> targetList = jsonDecode(columnData.toString());
      for (var item in targetList) {
        String cleanItem = isCategory
            ? item.toString().replaceAll(' ', '').toLowerCase()
            : _standardizeClass(item.toString());
        if (cleanItem == 'all' || cleanItem == cleanStudentData) return true;
      }
      return false;
    } catch (e) {
      return colStr.contains(cleanStudentData);
    }
  }

  // ===========================================================================
  // 🚨 SMART FINANCIAL CSV GENERATOR
  // ===========================================================================
  Future<void> _generateClassArchive() async {
    if (_selectedArchiveClassId == null) return;

    setState(() => _isGenerating = true);
    try {
      final selectedClass = _allClasses.firstWhere(
        (c) => c['id'].toString() == _selectedArchiveClassId,
      );
      final selectedClassName = selectedClass['name'];

      // 1. Fetch Students
      final studentsData = await _supabase
          .from('students')
          .select(
            'id, first_name, middle_name, last_name, category, wallet_balance',
          )
          .eq('class_id', _selectedArchiveClassId!);

      if (studentsData.isEmpty) {
        showAuthErrorDialog("No students found in $selectedClassName.");
        setState(() => _isGenerating = false);
        return;
      }
      final studentIds = studentsData.map((s) => s['id']).toList();

      // 2. Fetch Fee Structures
      final allFeesRes = await _supabase
          .from('fee_structures')
          .select()
          .eq('school_id', _schoolId!);
      final allFees = List<Map<String, dynamic>>.from(allFeesRes);

      final classFees = allFees.where((fee) {
        if (fee['academic_session'] != _selectedArchiveSession) return false;
        if (fee['academic_term'] != _selectedArchiveTerm &&
            fee['academic_term'] != 'All Terms') {
          return false;
        }

        bool classMatch = false;
        final List<dynamic>? classIdsList = fee['applicable_class_ids'];
        if (classIdsList != null && classIdsList.isNotEmpty) {
          classMatch = classIdsList.contains(_selectedArchiveClassId);
        } else {
          classMatch = _doesItApply(
            fee['applicable_classes'],
            selectedClassName,
          );
        }
        return classMatch;
      }).toList();

      // 3. Fetch Transactions
      final txData = await _supabase
          .from('transactions')
          .select(
            'student_id, student_name, created_at, receipt_no, category, payment_method, amount, fee_id',
          )
          .eq('academic_session', _selectedArchiveSession)
          .eq('academic_term', _selectedArchiveTerm)
          .inFilter('student_id', studentIds)
          .order('created_at', ascending: false);

      // --- CALCULATE TRUE FINANCIAL STATUS ---
      double totalClassExpected = 0.0;
      double totalClassPaid = 0.0;
      double totalClassOutstanding = 0.0;

      List<Map<String, dynamic>> studentFinancials = [];

      for (var student in studentsData) {
        String sId = student['id'].toString();
        String sCategory = (student['category'] ?? '').toString();
        double walletBalance = (student['wallet_balance'] ?? 0).toDouble();

        double availableCredit = walletBalance > 0 ? walletBalance : 0.0;
        double pastArrears = walletBalance < 0 ? walletBalance.abs() : 0.0;

        double studentExpected = pastArrears;
        double studentPaid = 0.0;
        double studentOutstanding = pastArrears;

        for (var fee in classFees) {
          if (_doesItApply(
            fee['applicable_categories'],
            sCategory,
            isCategory: true,
          )) {
            String feeId = fee['id'].toString();
            String feeName = fee['fee_name'].toString();
            double expectedAmt = (fee['amount'] ?? 0).toDouble();

            studentExpected += expectedAmt;

            double paidAmt = 0.0;
            for (var tx in txData) {
              if (tx['student_id'] == sId) {
                if (tx['fee_id'] == feeId || tx['category'] == feeName) {
                  paidAmt += (tx['amount'] ?? 0).toDouble();
                }
              }
            }

            studentPaid += paidAmt;

            double remaining = expectedAmt - paidAmt;
            if (remaining > 0) {
              if (availableCredit >= remaining) {
                availableCredit -= remaining;
                remaining = 0;
              } else if (availableCredit > 0) {
                remaining -= availableCredit;
                availableCredit = 0;
              }
              studentOutstanding += remaining;
            }
          }
        }

        totalClassExpected += studentExpected;
        totalClassPaid += studentPaid;
        totalClassOutstanding += studentOutstanding;

        String fName = student['first_name']?.toString() ?? '';
        String mName = student['middle_name']?.toString() ?? '';
        String lName = student['last_name']?.toString() ?? '';
        String cleanName = [
          fName,
          mName,
          lName,
        ].where((s) => s.trim().isNotEmpty).join(' ');

        studentFinancials.add({
          'name': '"$cleanName"',
          'wallet': walletBalance,
          'expected': studentExpected,
          'paid': studentPaid,
          'outstanding': studentOutstanding,
        });
      }

      // --- GENERATE CSV ---
      StringBuffer csvContent = StringBuffer();

      csvContent.writeln("=== CLASS FINANCIAL SUMMARY ===");
      csvContent.writeln("Class:, $selectedClassName");
      csvContent.writeln("Session:, $_selectedArchiveSession");
      csvContent.writeln("Term:, $_selectedArchiveTerm");
      csvContent.writeln("");
      csvContent.writeln("Total Expected Revenue:, NGN $totalClassExpected");
      csvContent.writeln("Total Collected:, NGN $totalClassPaid");
      csvContent.writeln("Total Outstanding Debt:, NGN $totalClassOutstanding");

      csvContent.writeln("\n\n=== STUDENT FINANCIAL STATUS ROSTER ===");
      csvContent.writeln(
        "Student Name,Wallet Balance (Past),Term Fees Expected,Term Fees Paid,CURRENT OUTSTANDING DEBT",
      );

      for (var s in studentFinancials) {
        csvContent.writeln(
          "${s['name']},${s['wallet']},${s['expected']},${s['paid']},${s['outstanding']}",
        );
      }

      csvContent.writeln("\n\n=== TRANSACTION HISTORY (LEDGER) ===");
      csvContent.writeln(
        "Date,Receipt No,Student Name,Payment Purpose,Payment Method,Amount",
      );

      for (var tx in txData) {
        DateTime date = DateTime.parse(tx['created_at']).toLocal();
        String formattedDate = DateFormat('yyyy-MM-dd HH:mm').format(date);
        String sName = '"${tx['student_name']}"';
        String category = '"${tx['category']}"';
        String method = '"${tx['payment_method']}"';
        String amount = tx['amount'].toString();
        String receipt = tx['receipt_no'].toString();

        csvContent.writeln(
          "$formattedDate,$receipt,$sName,$category,$method,$amount",
        );
      }

      final Uint8List bytes = utf8.encode(csvContent.toString());
      String safeName = selectedClassName.replaceAll(' ', '_');
      String safeSession = _selectedArchiveSession.replaceAll('/', '-');
      String safeTerm = _selectedArchiveTerm.replaceAll(' ', '_');

      await FileSaver.instance.saveFile(
        name: 'Financial_Report_${safeName}_${safeSession}_$safeTerm',
        bytes: bytes,
        fileExtension: 'csv',
        mimeType: MimeType.csv,
      );

      if (mounted) {
        showSuccessDialog(
          "Report Downloaded",
          "The comprehensive financial report for $selectedClassName has been downloaded. It includes total debt summaries, individual student balances, and full transaction logs.",
        );
      }
    } catch (e) {
      showAuthErrorDialog("Failed to generate CSV: $e");
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
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

    if (_allClasses.isEmpty) {
      return Scaffold(
        backgroundColor: bgColor,
        appBar: AppBar(
          title: const Text(
            "Financial Archives",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          backgroundColor: bgColor,
          foregroundColor: isDark ? Colors.white : const Color(0xFF1A1A2E),
          elevation: 0,
        ),
        body: const Center(
          child: Text(
            "No classes configured. Please set up your school structure first.",
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text(
          "Financial Archives",
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
            constraints: const BoxConstraints(maxWidth: 800),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: isDark ? Colors.white10 : Colors.grey.shade200,
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.02),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.download_rounded,
                            color: Colors.blueAccent,
                          ),
                          SizedBox(width: 10),
                          Text(
                            "Download Financial Report (CSV)",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 15),
                      Text(
                        "Select a class, session, and term below. This will download a spreadsheet containing the total expected revenue, an individual breakdown of student debts/credits, and a complete transaction history.",
                        style: TextStyle(
                          color: isDark ? Colors.white70 : Colors.black87,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 25),

                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              isExpanded: true,
                              initialValue: _selectedArchiveSession,
                              dropdownColor: cardColor,
                              decoration: _inputStyle(
                                "Session",
                                Icons.history_edu_rounded,
                                isDark,
                                primaryColor,
                              ),
                              items: _generateDynamicSessions()
                                  .map(
                                    (e) => DropdownMenuItem(
                                      value: e,
                                      child: Text(
                                        e,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (val) => setState(
                                () => _selectedArchiveSession = val!,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              isExpanded: true,
                              initialValue: _selectedArchiveTerm,
                              dropdownColor: cardColor,
                              decoration: _inputStyle(
                                "Term",
                                Icons.calendar_month_rounded,
                                isDark,
                                primaryColor,
                              ),
                              items:
                                  [
                                        "1st Term",
                                        "2nd Term",
                                        "3rd Term",
                                        "All Terms",
                                      ]
                                      .map(
                                        (e) => DropdownMenuItem(
                                          value: e,
                                          child: Text(
                                            e,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      )
                                      .toList(),
                              onChanged: (val) =>
                                  setState(() => _selectedArchiveTerm = val!),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: _selectedArchiveClassId,
                        dropdownColor: cardColor,
                        decoration: _inputStyle(
                          "Target Class",
                          Icons.class_rounded,
                          isDark,
                          primaryColor,
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
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (val) =>
                            setState(() => _selectedArchiveClassId = val),
                      ),
                      const SizedBox(height: 25),

                      SizedBox(
                        width: double.infinity,
                        height: 55,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.blueAccent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed: _isGenerating
                              ? null
                              : _generateClassArchive,
                          icon: _isGenerating
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.download_rounded),
                          label: Text(
                            _isGenerating
                                ? "GENERATING CSV..."
                                : "DOWNLOAD REPORT",
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputStyle(
    String label,
    IconData icon,
    bool isDark,
    Color pColor,
  ) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: Colors.grey.shade500, fontSize: 13),
      prefixIcon: Icon(icon, color: pColor, size: 18),
      filled: true,
      fillColor: isDark
          ? Colors.white.withValues(alpha: 0.03)
          : Colors.grey.shade50,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
        ),
      ),
    );
  }
}
