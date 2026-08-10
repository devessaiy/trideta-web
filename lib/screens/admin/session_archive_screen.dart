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
  bool _isAdvancing = false;

  String? _schoolId;

  List<Map<String, dynamic>> _allClasses = [];
  List<String> _classesToAdvance = [];

  final Set<String> _downloadedLedgers = {};

  String? _selectedArchiveClassId;
  late String _selectedArchiveSession;
  late String _selectedArchiveTerm;

  late String _newSession;
  String _newTerm = "2nd Term";

  @override
  void initState() {
    super.initState();
    final dynamicSessions = _generateDynamicSessions();
    _selectedArchiveSession = dynamicSessions.contains("2025/2026")
        ? "2025/2026"
        : dynamicSessions.first;
    _newSession = dynamicSessions.contains("2025/2026")
        ? "2025/2026"
        : dynamicSessions.first;
    _selectedArchiveTerm = "1st Term";
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
          .select('id, name, override_session, override_term')
          .eq('school_id', _schoolId!)
          .order('list_order', ascending: true);

      if (mounted) {
        setState(() {
          _allClasses = List<Map<String, dynamic>>.from(classesData).map((c) {
            return {
              'id': c['id'],
              'name': c['name'],
              'current_session': c['override_session'] ?? globalSession,
              'current_term': c['override_term'] ?? globalTerm,
            };
          }).toList();

          if (_allClasses.isNotEmpty) {
            _selectedArchiveClassId = _allClasses.first['id'].toString();
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        showAuthErrorDialog(
          "Failed to fetch school structure. Please check connection.",
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

  Future<void> _generateClassArchive() async {
    if (_selectedArchiveClassId == null) return;

    setState(() => _isGenerating = true);
    try {
      final selectedClassName = _allClasses.firstWhere(
        (c) => c['id'].toString() == _selectedArchiveClassId,
      )['name'];

      final studentsData = await _supabase
          .from('students')
          .select('id, first_name, middle_name, last_name, wallet_balance')
          .eq('class_id', _selectedArchiveClassId!);

      if (studentsData.isEmpty) {
        showAuthErrorDialog("No students found in $selectedClassName.");
        setState(() => _isGenerating = false);
        return;
      }

      final studentIds = studentsData.map((s) => s['id']).toList();

      final txData = await _supabase
          .from('transactions')
          .select(
            'student_name, created_at, receipt_no, category, payment_method, amount',
          )
          .eq('academic_session', _selectedArchiveSession)
          .eq('academic_term', _selectedArchiveTerm)
          .inFilter('student_id', studentIds)
          .order('created_at', ascending: false);

      StringBuffer csvContent = StringBuffer();

      csvContent.writeln("=== PERPETUAL WALLET & DEBT SUMMARY ===");
      csvContent.writeln(
        "Student Name,Current Wallet Balance (Negative = Debt)",
      );

      for (var student in studentsData) {
        String fName = student['first_name']?.toString() ?? '';
        String mName = student['middle_name']?.toString() ?? '';
        String lName = student['last_name']?.toString() ?? '';
        String cleanName = [
          fName,
          mName,
          lName,
        ].where((s) => s.trim().isNotEmpty).join(' ');

        String nameStr = '"$cleanName"';
        double balance = (student['wallet_balance'] ?? 0).toDouble();
        csvContent.writeln("$nameStr,$balance");
      }

      csvContent.writeln(
        "\n\n=== $_selectedArchiveSession ($_selectedArchiveTerm) TRANSACTION HISTORY ===",
      );
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
        name: 'Ledger_${safeName}_${safeSession}_$safeTerm',
        bytes: bytes,
        fileExtension: 'csv',
        mimeType: MimeType.csv,
      );

      if (mounted) {
        setState(() {
          String uniqueLedgerKey =
              "${_selectedArchiveClassId}_${_selectedArchiveSession}_$_selectedArchiveTerm";
          _downloadedLedgers.add(uniqueLedgerKey);
        });
        showSuccessDialog(
          "Ledger Downloaded",
          "The financial record and debtor list for $selectedClassName has been saved. If this matches their current calendar, their advancement checkbox is now unlocked.",
        );
      }
    } catch (e) {
      showAuthErrorDialog("Failed to generate CSV: $e");
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  // ===========================================================================
  // 🚨 ATOMIC RPC ADVANCEMENT ENGINE
  // ===========================================================================
  Future<void> _advanceClassCalendars() async {
    if (_classesToAdvance.isEmpty) {
      showAuthErrorDialog("Please select at least one class to advance.");
      return;
    }

    bool confirm =
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF1E1E1E)
                : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.orange),
                SizedBox(width: 10),
                Text(
                  "Advance & Tally Debts?",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            content: Text(
              "You are about to advance ${_classesToAdvance.length} class(es) to $_newSession ($_newTerm).\n\nThe system will instantly calculate all unpaid fees for their current term and securely lock the debt into their Perpetual Wallets via an atomic transaction. Do you wish to proceed?",
              style: const TextStyle(height: 1.4),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text(
                  "Cancel",
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.orange,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(
                  "Yes, Advance",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirm) return;

    setState(() => _isAdvancing = true);
    try {
      // Fetch all required data into RAM (Fast & Safe)
      final allFeesRes = await _supabase
          .from('fee_structures')
          .select()
          .eq('school_id', _schoolId!);
      final allFees = List<Map<String, dynamic>>.from(allFeesRes);

      List<Map<String, dynamic>> walletPayload = []; // The master payload

      for (String classId in _classesToAdvance) {
        final classInfo = _allClasses.firstWhere(
          (c) => c['id'].toString() == classId,
        );
        final oldSession = classInfo['current_session'] ?? 'Unknown';
        final oldTerm = classInfo['current_term'] ?? 'Unknown';
        final className = classInfo['name'] ?? 'Unknown';

        final students = await _supabase
            .from('students')
            .select('id, category')
            .eq('class_id', classId);
        if (students.isEmpty) continue;

        final classFees = allFees.where((fee) {
          if (fee['academic_session'] != oldSession) return false;
          if (fee['academic_term'] != oldTerm &&
              fee['academic_term'] != 'All Terms')
            return false;

          bool classMatch = false;
          final List<dynamic>? classIdsList = fee['applicable_class_ids'];
          if (classIdsList != null && classIdsList.isNotEmpty) {
            classMatch = classIdsList.contains(classId);
          } else {
            classMatch = _doesItApply(fee['applicable_classes'], className);
          }
          return classMatch;
        }).toList();

        final studentIds = students.map((s) => s['id']).toList();
        final txData = await _supabase
            .from('transactions')
            .select('student_id, fee_id, category, amount')
            .eq('academic_session', oldSession)
            .eq('academic_term', oldTerm)
            .inFilter('student_id', studentIds);

        // Calculate debts inside the device's RAM
        for (var student in students) {
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

          if (totalUnpaid > 0) {
            // Bundle the exact debt calculation into the payload
            walletPayload.add({
              'student_id': student['id'],
              'unpaid_amount': totalUnpaid,
            });
          }
        }
      }

      // 🚨 ATOMIC FIRE: Execute everything securely in exactly ONE database request
      await _supabase.rpc(
        'bulk_advance_financials',
        params: {
          'p_school_id': _schoolId,
          'p_wallet_payload': walletPayload,
          'p_class_ids': _classesToAdvance,
          'p_new_session': _newSession,
          'p_new_term': _newTerm,
        },
      );

      if (mounted) {
        setState(() {
          _downloadedLedgers.clear();
          _classesToAdvance.clear();
        });

        await _fetchInitialData();

        showSuccessDialog(
          "Calendars Advanced",
          "The selected classes are now operating in $_newSession ($_newTerm). All unpaid debts have been locked securely.",
        );
      }
    } catch (e) {
      if (mounted)
        showAuthErrorDialog("Failed to advance calendars. Check connection.");
    } finally {
      if (mounted) setState(() => _isAdvancing = false);
    }
  }

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
          "Ledger & Calendar Mgmt",
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
            constraints: const BoxConstraints(maxWidth: 700),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: primaryColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.account_balance_wallet_rounded,
                        color: primaryColor,
                        size: 30,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Perpetual Ledger Active",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: primaryColor,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "Student debts and credits are tracked perpetually via their Wallets. Advancing a session resets the dashboard, but balances remain securely stored.",
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? Colors.white70 : Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),

                _buildSectionHeader(
                  "STEP 1: DOWNLOAD CLASS LEDGER",
                  Icons.download_rounded,
                  primaryColor,
                ),
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
                        "Export Records & Debtors",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Select a class, session, and term to download their complete ledger, including current Wallet balances (debt).",
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade500,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 20),

                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        value: _selectedArchiveClassId,
                        dropdownColor: cardColor,
                        decoration: _inputStyle("Select Class", isDark),
                        items: _allClasses
                            .map(
                              (c) => DropdownMenuItem<String>(
                                value: c['id'].toString(),
                                child: Text(
                                  c['name'].toString(),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (val) =>
                            setState(() => _selectedArchiveClassId = val),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              isExpanded: true,
                              value: _selectedArchiveSession,
                              dropdownColor: cardColor,
                              decoration: _inputStyle("Session", isDark),
                              items: _generateDynamicSessions()
                                  .map(
                                    (e) => DropdownMenuItem(
                                      value: e,
                                      child: Text(
                                        e,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
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
                              value: _selectedArchiveTerm,
                              dropdownColor: cardColor,
                              decoration: _inputStyle("Term", isDark),
                              items: ['1st Term', '2nd Term', '3rd Term']
                                  .map(
                                    (e) => DropdownMenuItem(
                                      value: e,
                                      child: Text(
                                        e,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
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
                      const SizedBox(height: 20),

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
                                ? "GENERATING LEDGER..."
                                : "DOWNLOAD LEDGER REPORT",
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),

                _buildSectionHeader(
                  "STEP 2: ADVANCE ASYNC CALENDARS",
                  Icons.lock_clock_rounded,
                  Colors.orange,
                ),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.orange.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Asynchronous Advancement",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.orange,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Select which specific classes to advance. You must download a class's current ledger (Step 1) before its checkbox unlocks.",
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade500,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 20),

                      Container(
                        height: 200,
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.02)
                              : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark
                                ? Colors.white10
                                : Colors.grey.shade200,
                          ),
                        ),
                        child: ListView.builder(
                          itemCount: _allClasses.length,
                          itemBuilder: (ctx, i) {
                            final c = _allClasses[i];
                            final id = c['id'].toString();
                            final name = c['name'].toString();
                            final currSession =
                                c['current_session'] ?? 'Unknown';
                            final currTerm = c['current_term'] ?? 'Unknown';

                            final ledgerKey = "${id}_${currSession}_$currTerm";
                            final isUnlocked = _downloadedLedgers.contains(
                              ledgerKey,
                            );

                            return CheckboxListTile(
                              activeColor: Colors.orange,
                              title: Text(
                                name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Text(
                                isUnlocked
                                    ? "Currently in $currSession • $currTerm\n✅ Ledger Downloaded & Unlocked"
                                    : "Currently in $currSession • $currTerm\n🔒 Download Ledger to unlock",
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isUnlocked
                                      ? Colors.green
                                      : Colors.redAccent,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              value: _classesToAdvance.contains(id),
                              onChanged: isUnlocked
                                  ? (bool? selected) {
                                      setState(() {
                                        if (selected == true) {
                                          _classesToAdvance.add(id);
                                        } else {
                                          _classesToAdvance.remove(id);
                                        }
                                      });
                                    }
                                  : null,
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 20),

                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              isExpanded: true,
                              value: _newSession,
                              dropdownColor: cardColor,
                              decoration: _inputStyle("Target Session", isDark),
                              items: _generateDynamicSessions()
                                  .map(
                                    (e) => DropdownMenuItem(
                                      value: e,
                                      child: Text(
                                        e,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (val) =>
                                  setState(() => _newSession = val!),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              isExpanded: true,
                              value: _newTerm,
                              dropdownColor: cardColor,
                              decoration: _inputStyle("Target Term", isDark),
                              items: ['1st Term', '2nd Term', '3rd Term']
                                  .map(
                                    (e) => DropdownMenuItem(
                                      value: e,
                                      child: Text(
                                        e,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (val) =>
                                  setState(() => _newTerm = val!),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      SizedBox(
                        width: double.infinity,
                        height: 55,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: _classesToAdvance.isNotEmpty
                                ? Colors.orange
                                : Colors.grey.shade400,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed:
                              (_classesToAdvance.isNotEmpty && !_isAdvancing)
                              ? _advanceClassCalendars
                              : null,
                          icon: _isAdvancing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(
                                  Icons.arrow_forward_rounded,
                                  color: _classesToAdvance.isNotEmpty
                                      ? Colors.white
                                      : Colors.white54,
                                ),
                          label: Text(
                            _classesToAdvance.isNotEmpty
                                ? "ADVANCE ${_classesToAdvance.length} CLASS(ES)"
                                : "LOCKED (SELECT CLASSES ABOVE)",
                            style: TextStyle(
                              color: _classesToAdvance.isNotEmpty
                                  ? Colors.white
                                  : Colors.white54,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 11,
              color: color,
              letterSpacing: 1.2,
            ),
          ),
        ],
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
