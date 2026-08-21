import 'package:trideta_v2/utils/auth_error_handler.dart';
import 'package:trideta_v2/widgets/trideta_loader.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

import 'fee_structure_screen.dart';
import 'receipt_history_screen.dart';
import 'record_payment_screen.dart';
import 'debtors_list_screen.dart';
import 'session_archive_screen.dart' show SessionArchiveScreen;

class FinanceCentreScreen extends StatefulWidget {
  const FinanceCentreScreen({super.key});

  @override
  State<FinanceCentreScreen> createState() => _FinanceCentreScreenState();
}

class _FinanceCentreScreenState extends State<FinanceCentreScreen>
    with AuthErrorHandler {
  final _supabase = Supabase.instance.client;

  bool _isFeesActivated = false;
  bool _isLoading = true;

  double _rawCollected = 0.0;
  double _rawDebt = 0.0;
  int _invoiceCount = 0;
  String _activeSessionLabel = "CURRENT TERM";

  String _currentSession = "";
  String _currentTerm = "1st Term";

  List<String> _officialClasses = [];

  @override
  void initState() {
    super.initState();
    _fetchFinanceData();
  }

  // ===========================================================================
  // 🚨 STRICT GLOBAL LOGIC ENGINE (CURRENT TERM ONLY)
  // ===========================================================================
  Future<void> _fetchFinanceData() async {
    setState(() => _isLoading = true);
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final profile = await _supabase
          .from('profiles')
          .select('school_id')
          .eq('id', user.id)
          .single();
      final schoolId = profile['school_id'];

      // 1. FETCH GLOBAL ACTIVE SESSION AND TERM
      final schoolData = await _supabase
          .from('schools')
          .select('current_session, current_term')
          .eq('id', schoolId)
          .single();

      _currentSession = schoolData['current_session'] ?? "";
      _currentTerm = schoolData['current_term'] ?? "1st Term";

      // Fetch official classes
      final classesData = await _supabase
          .from('classes')
          .select('name')
          .eq('school_id', schoolId)
          .order('list_order', ascending: true);

      _officialClasses = classesData.map((c) => c['name'].toString()).toList();

      // 2. FETCH FEE STRUCTURE (STRICTLY FILTERED BY ACTIVE TIMELINE)
      final rawFeeData = await _supabase
          .from('fee_structures')
          .select(
            'id, fee_name, amount, applicable_classes, applicable_class_ids, applicable_categories, academic_session, academic_term',
          )
          .eq('school_id', schoolId);

      List<Map<String, dynamic>> feeData = [];
      for (var fee in rawFeeData) {
        String feeSession = (fee['academic_session'] ?? '').toString();
        String feeTerm = (fee['academic_term'] ?? 'All Terms').toString();

        if ((feeSession == _currentSession || feeSession.isEmpty) &&
            (feeTerm == _currentTerm || feeTerm == 'All Terms')) {
          feeData.add(fee);
        }
      }

      if (feeData.isNotEmpty) {
        _activeSessionLabel = "$_currentSession • $_currentTerm".toUpperCase();
      }

      // 3. FETCH TRANSACTIONS (STRICTLY FILTERED BY ACTIVE TIMELINE)
      final txData = await _supabase
          .from('transactions')
          .select(
            'student_id, category, amount, academic_session, academic_term, fee_id',
          )
          .eq('school_id', schoolId);

      Map<String, Map<String, double>> studentCategoryPayments = {};
      double totalCollected = 0.0;
      int validInvoiceCount = 0;

      for (var tx in txData) {
        String txSession = (tx['academic_session'] ?? '').toString();
        String txTerm = (tx['academic_term'] ?? 'All Terms').toString();

        if ((txSession == _currentSession || txSession.isEmpty) &&
            (txTerm == _currentTerm ||
                txTerm == 'All Terms' ||
                _currentTerm == 'All Terms')) {
          String sId = tx['student_id'].toString();
          String txFeeId = (tx['fee_id'] ?? '').toString();
          String txCategory = (tx['category'] ?? '').toString();
          double amt = (tx['amount'] ?? 0).toDouble();

          String paymentKey = txFeeId.isNotEmpty ? txFeeId : txCategory;

          studentCategoryPayments.putIfAbsent(sId, () => {});
          studentCategoryPayments[sId]![paymentKey] =
              (studentCategoryPayments[sId]![paymentKey] ?? 0) + amt;

          totalCollected += amt;
          validInvoiceCount++;
        }
      }

      // 4. FETCH ACTIVE STUDENTS & CALCULATE TRUE INDIVIDUAL DEBT
      final studentsData = await _supabase
          .from('students')
          .select('id, class_level, class_id, category, wallet_balance')
          .eq('school_id', schoolId)
          .eq('is_active', true);

      double totalDebt = 0.0;

      for (var student in studentsData) {
        String sId = student['id'].toString();
        String sClass = (student['class_level'] ?? '').toString();
        String sClassId = (student['class_id'] ?? '').toString();
        String sCategory = (student['category'] ?? '').toString();
        double walletBalance = (student['wallet_balance'] ?? 0).toDouble();

        double activeStudentDebt = 0.0;

        for (var fee in feeData) {
          String feeId = fee['id'].toString();
          String feeName = fee['fee_name'].toString();
          double expectedAmt = (fee['amount'] ?? 0).toDouble();

          bool classMatch = false;

          final dynamic rawClassIds = fee['applicable_class_ids'];
          List<dynamic> classIdsList = [];
          
          if (rawClassIds is String && rawClassIds.startsWith('[')) {
             try {
                 classIdsList = jsonDecode(rawClassIds);
             } catch(e) {}
          } else if (rawClassIds is List) {
             classIdsList = rawClassIds;
          }

          if (classIdsList.isNotEmpty && sClassId.isNotEmpty) {
            classMatch = classIdsList.contains(sClassId);
          } else {
            classMatch = _doesItApply(
              fee['applicable_classes'],
              sClass,
              officialList: _officialClasses,
            );
          }

          bool categoryMatch = _doesItApply(
            fee['applicable_categories'],
            sCategory,
            isCategory: true,
          );

          if (classMatch && categoryMatch) {
            double paidAmt =
                (studentCategoryPayments[sId]?[feeId] ?? 0.0) +
                (studentCategoryPayments[sId]?[feeName] ?? 0.0);

            double remaining = expectedAmt - paidAmt;
            if (remaining > 0) {
              activeStudentDebt += remaining;
            }
          }
        }

        // 🚨 FLAWLESS MATH: Use Wallet ONLY as a credit buffer. 
        // If the wallet is negative (past debt), it is treated as 0.0 so we strictly calculate CURRENT term debt.
        double availableCredit = walletBalance > 0 ? walletBalance : 0.0;
        double finalTrueDebt = activeStudentDebt - availableCredit;

        if (finalTrueDebt > 0) {
          totalDebt += finalTrueDebt;
        }
      }

      if (mounted) {
        setState(() {
          _isFeesActivated = feeData.isNotEmpty;
          _rawCollected = totalCollected;
          _rawDebt = totalDebt; 
          _invoiceCount = validInvoiceCount;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Finance Fetch Error: $e");
      if (mounted) {
        setState(() => _isLoading = false);
        showAuthErrorDialog(
          "We couldn't sync your financial data. Please check your connection.",
        );
      }
    }
  }

  String _standardizeClass(String val) {
    String v = val.replaceAll(' ', '').toLowerCase();
    v = v.replaceAll('one', '1').replaceAll('two', '2').replaceAll('three', '3');
    v = v.replaceAll('four', '4').replaceAll('five', '5').replaceAll('six', '6');
    v = v.replaceAll('seven', '7').replaceAll('eight', '8').replaceAll('nine', '9');
    return v;
  }

  bool _doesItApply(
    dynamic columnData,
    String studentData, {
    bool isCategory = false,
    List<String>? officialList,
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

    String colStr = isCategory
        ? columnData.toString().replaceAll(' ', '').toLowerCase()
        : _standardizeClass(columnData.toString());

    if (colStr.isEmpty ||
        colStr == 'all' ||
        colStr == '[]' ||
        colStr == '["all"]') {
      return true;
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

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC);
    Color textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final currencyFormat = NumberFormat.currency(symbol: '₦', decimalDigits: 2);

    Color primaryColor = Theme.of(context).primaryColor;

    Widget mainContent = RefreshIndicator(
      onRefresh: _fetchFinanceData,
      color: primaryColor,
      child: _isLoading
          ? Center(child: TridetaLoader(color: primaryColor))
          : SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: _buildFinanceSnapshot(
                      isDark,
                      currencyFormat,
                      primaryColor,
                    ),
                  ),
                  const SizedBox(height: 30),

                  if (!_isFeesActivated) _buildSetupWarning(isDark),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      "FINANCIAL OPERATIONS",
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Colors.grey.shade500,
                        fontSize: 12,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 15),

                  Column(
                    children: [
                      _buildActionTile(
                        context,
                        title: "Record Fee",
                        subtitle: _isFeesActivated
                            ? "Post payments"
                            : "Setup needed",
                        icon: Icons.account_balance_wallet_rounded,
                        color: Colors.green.shade600,
                        isLocked: !_isFeesActivated,
                        isDark: isDark,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const RecordPaymentScreen(),
                          ),
                        ).then((_) => _fetchFinanceData()),
                      ),
                      _buildActionTile(
                        context,
                        title: "Fee Structure",
                        subtitle: "Manage pricing",
                        icon: Icons.settings_applications_rounded,
                        color: Colors.orange.shade600,
                        isDark: isDark,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const FeeStructureScreen(),
                          ),
                        ).then((_) => _fetchFinanceData()),
                      ),
                      _buildActionTile(
                        context,
                        title: "History",
                        subtitle: "Receipt logs",
                        icon: Icons.receipt_long_rounded,
                        color: Colors.blue.shade600,
                        isDark: isDark,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ReceiptHistoryScreen(),
                          ),
                        ),
                      ),
                      _buildActionTile(
                        context,
                        title: "Debtors List",
                        subtitle: "Track balances",
                        icon: Icons.person_search_rounded,
                        color: Colors.redAccent,
                        isDark: isDark,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const DebtorsListScreen(),
                          ),
                        ),
                      ),
                      _buildActionTile(
                        context,
                        title: "Financial Archive",
                        subtitle: "Download financial records",
                        icon: Icons.archive_rounded,
                        color: Colors.deepPurple,
                        isDark: isDark,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SessionArchiveScreen(),
                          ),
                        ).then((_) => _fetchFinanceData()),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text(
          "Finance Centre",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: bgColor,
        foregroundColor: textColor,
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
                    border: Border(
                      left: BorderSide(
                        color: isDark ? Colors.white10 : Colors.grey.shade200,
                        width: 1,
                      ),
                      right: BorderSide(
                        color: isDark ? Colors.white10 : Colors.grey.shade200,
                        width: 1,
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

  Widget _buildFinanceSnapshot(
    bool isDark,
    NumberFormat f,
    Color primaryColor,
  ) {
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [primaryColor.withValues(alpha: 0.85), primaryColor],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -30,
            top: -30,
            child: CircleAvatar(
              radius: 70,
              backgroundColor: Colors.white.withValues(alpha: 0.1),
            ),
          ),
          Positioned(
            left: -20,
            bottom: -40,
            child: CircleAvatar(
              radius: 60,
              backgroundColor: Colors.white.withValues(alpha: 0.05),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "TOTAL COLLECTED ($_activeSessionLabel)",
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const Icon(
                      Icons.account_balance_rounded,
                      color: Colors.white54,
                      size: 18,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                FittedBox(
                  child: Text(
                    f.format(_rawCollected),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
                const SizedBox(height: 25),
                Row(
                  children: [
                    _snapshotMiniItem(
                      "Outstanding",
                      f.format(_rawDebt),
                      Icons.arrow_downward_rounded,
                    ),
                    const SizedBox(width: 30),
                    _snapshotMiniItem(
                      "Transactions",
                      _invoiceCount.toString(),
                      Icons.receipt_long_rounded,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _snapshotMiniItem(String label, String val, IconData icon) {
    return Expanded(
      child: Row(
        children: [
          Icon(icon, color: Colors.white54, size: 16),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  val,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionTile(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    bool isLocked = false,
    required bool isDark,
  }) {
    Color textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);

    return InkWell(
      onTap: isLocked ? null : onTap,
      child: Column(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 8,
            ),
            leading: CircleAvatar(
              radius: 24,
              backgroundColor: isLocked
                  ? Colors.grey.withValues(alpha: 0.1)
                  : color.withValues(alpha: 0.12),
              child: Icon(
                isLocked ? Icons.lock_outline_rounded : icon,
                color: isLocked ? Colors.grey : color,
                size: 24,
              ),
            ),
            title: Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: textColor,
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                subtitle,
                style: TextStyle(
                  color: isDark ? Colors.white70 : Colors.grey.shade500,
                  fontSize: 13,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            trailing: Icon(
              Icons.chevron_right_rounded,
              size: 24,
              color: Colors.grey.shade400,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 88, right: 24),
            child: Divider(
              height: 1,
              color: isDark ? Colors.white10 : Colors.grey.shade200,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSetupWarning(bool isDark) {
    return Column(
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 8,
          ),
          leading: CircleAvatar(
            radius: 24,
            backgroundColor: Colors.orange.withValues(alpha: 0.1),
            child: const Icon(
              Icons.info_outline_rounded,
              color: Colors.orange,
              size: 24,
            ),
          ),
          title: const Text(
            "Setup Required",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              "Bursary inactive. Add items to the Fee Structure to begin receiving payments.",
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white70 : Colors.grey.shade600,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 88, right: 24),
          child: Divider(
            height: 1,
            color: isDark ? Colors.white10 : Colors.grey.shade200,
          ),
        ),
        const SizedBox(height: 15),
      ],
    );
  }
}