import 'package:trideta_v2/utils/auth_error_handler.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

import 'fee_structure_screen.dart';
import 'receipt_history_screen.dart';
import 'record_payment_screen.dart';
import 'debtors_list_screen.dart';

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

  // 🚨 ADDED TO HOLD OFFICIAL CLASSES
  List<String> _officialClasses = [];

  @override
  void initState() {
    super.initState();
    _fetchFinanceData();
  }

  // --- 🚨 IRONCLAD FINANCIAL MATH ENGINE WITH LEGACY SAFEGUARDS 🚨 ---
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

      // 1. FETCH ACTIVE SESSION FIRST
      final schoolData = await _supabase
          .from('schools')
          .select('current_session')
          .eq('id', schoolId)
          .single();

      _currentSession = schoolData['current_session'] ?? "";

      // 1.5 🚨 FETCH OFFICIAL CLASSES FROM RELATIONAL TABLE 🚨
      final classesData = await _supabase
          .from('classes')
          .select('name')
          .eq('school_id', schoolId)
          .order('list_order', ascending: true);

      _officialClasses = classesData.map((c) => c['name'].toString()).toList();

      // 2. FETCH FEE STRUCTURE (SAFELY HANDLING LEGACY DATA)
      final rawFeeData = await _supabase
          .from('fee_structures')
          .select(
            'fee_name, amount, applicable_classes, applicable_categories, academic_session',
          )
          .eq('school_id', schoolId);

      // Filter fees locally to protect old records
      List<Map<String, dynamic>> feeData = [];
      for (var fee in rawFeeData) {
        String feeSession = (fee['academic_session'] ?? '').toString();
        // 🚨 LEGACY SAFEGUARD: Accept current session OR empty (old data)
        if (feeSession == _currentSession || feeSession.isEmpty) {
          feeData.add(fee);
        }
      }

      if (feeData.isNotEmpty) {
        _activeSessionLabel = _currentSession.toUpperCase();
      }

      // 3. FETCH TRANSACTIONS (SAFELY HANDLING LEGACY DATA)
      final txData = await _supabase
          .from('transactions')
          .select('student_id, category, amount, academic_session')
          .eq('school_id', schoolId);

      // Group payments by Student AND Category: { "Student_A_ID": { "Tuition": 50000, "Books": 10000 } }
      Map<String, Map<String, double>> studentCategoryPayments = {};
      double totalCollected = 0.0;
      int validInvoiceCount = 0;

      for (var tx in txData) {
        String txSession = (tx['academic_session'] ?? '').toString();

        // 🚨 LEGACY SAFEGUARD: Only count matching sessions or legacy empty sessions
        if (txSession == _currentSession || txSession.isEmpty) {
          String sId = tx['student_id'].toString();
          String category = (tx['category'] ?? '').toString();
          double amt = (tx['amount'] ?? 0).toDouble();

          studentCategoryPayments.putIfAbsent(sId, () => {});
          studentCategoryPayments[sId]![category] =
              (studentCategoryPayments[sId]![category] ?? 0) + amt;

          totalCollected += amt;
          validInvoiceCount++;
        }
      }

      // 4. FETCH STUDENTS & CALCULATE TRUE INDIVIDUAL DEBT
      final studentsData = await _supabase
          .from('students')
          .select('*')
          .eq('school_id', schoolId);

      double totalDebt = 0.0;

      for (var student in studentsData) {
        String sId = student['id'].toString();
        String sClass = (student['class_level'] ?? '').toString();
        String sCategory = (student['category'] ?? '').toString();

        double studentDebt = 0.0;

        // 🚨 SQUASHED PHANTOM CREDIT BUG: Check debt item by item!
        for (var fee in feeData) {
          String feeName = fee['fee_name'].toString();
          double expectedAmt = (fee['amount'] ?? 0).toDouble();

          // 🚨 Passing _officialClasses to _doesItApply for dynamic 'All' resolution
          bool classMatch = _doesItApply(
            fee['applicable_classes'],
            sClass,
            officialList: _officialClasses,
          );
          bool categoryMatch = _doesItApply(
            fee['applicable_categories'],
            sCategory,
            isCategory: true,
          );

          if (classMatch && categoryMatch) {
            double paidAmt = studentCategoryPayments[sId]?[feeName] ?? 0.0;
            double remaining = expectedAmt - paidAmt;
            if (remaining > 0) {
              studentDebt += remaining;
            }
          }
        }

        totalDebt += studentDebt;
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

  // --- THE BUILT-IN TRANSLATOR & MATCHER ---
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

  // 🚨 ADDED optional officialList parameter
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

    String colStr = isCategory
        ? columnData.toString().replaceAll(' ', '').toLowerCase()
        : _standardizeClass(columnData.toString());

    // 🚨 If 'all', instantly approve
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

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC);
    final currencyFormat = NumberFormat.currency(symbol: '₦', decimalDigits: 2);

    Color primaryColor = Theme.of(context).primaryColor;

    // 🚨 EXTRACTED MAIN CONTENT FOR LAYOUT BUILDER
    Widget mainContent = RefreshIndicator(
      onRefresh: _fetchFinanceData,
      color: primaryColor,
      child: _isLoading
          ? Center(child: CircularProgressIndicator(color: primaryColor))
          : SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildFinanceSnapshot(isDark, currencyFormat, primaryColor),
                  const SizedBox(height: 30),
                  if (!_isFeesActivated) _buildSetupWarning(),
                  Text(
                    "ADMINISTRATIVE ACTIONS",
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: primaryColor.withOpacity(0.8),
                      fontSize: 12,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 15),
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    crossAxisSpacing: 15,
                    mainAxisSpacing: 15,
                    childAspectRatio: 1.1,
                    children: [
                      _buildActionCard(
                        context,
                        title: "Record Fee",
                        subtitle: _isFeesActivated
                            ? "Post payments"
                            : "Setup needed",
                        icon: Icons.account_balance_wallet_rounded,
                        color: Colors.green,
                        isLocked: !_isFeesActivated,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const RecordPaymentScreen(),
                          ),
                        ).then((_) => _fetchFinanceData()),
                      ),
                      _buildActionCard(
                        context,
                        title: "Fee Structure",
                        subtitle: "Manage pricing",
                        icon: Icons.settings_applications_rounded,
                        color: Colors.orange,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const FeeStructureScreen(),
                          ),
                        ).then((_) => _fetchFinanceData()),
                      ),
                      _buildActionCard(
                        context,
                        title: "History",
                        subtitle: "Receipt logs",
                        icon: Icons.receipt_long_rounded,
                        color: Colors.blue,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ReceiptHistoryScreen(),
                          ),
                        ),
                      ),
                      _buildActionCard(
                        context,
                        title: "Debtors List",
                        subtitle: "Track balances",
                        icon: Icons.person_search_rounded,
                        color: Colors.redAccent,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const DebtorsListScreen(),
                          ),
                        ),
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
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      // 🚨 SHAPE-SHIFTER: LayoutBuilder
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth > 800) {
            // 💻 DESKTOP LAYOUT (Constrained center column)
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
            // 📱 MOBILE LAYOUT
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
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [primaryColor, primaryColor.withOpacity(0.8)],
        ),
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
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
                Icons.download_rounded,
                color: Colors.white54,
                size: 18,
              ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            child: Text(
              f.format(_rawCollected),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.w900,
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
                Icons.description_rounded,
              ),
            ],
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

  Widget _buildActionCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    bool isLocked = false,
  }) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade100,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isLocked ? null : onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isLocked
                        ? Colors.grey.withOpacity(0.1)
                        : color.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isLocked ? Icons.lock_outline : icon,
                    color: isLocked ? Colors.grey : color,
                    size: 28,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.grey, fontSize: 10),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSetupWarning() {
    return Container(
      margin: const EdgeInsets.only(bottom: 25),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.orange.withOpacity(0.2)),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline_rounded, color: Colors.orange),
          SizedBox(width: 15),
          Expanded(
            child: Text(
              "Bursary inactive. Add items to the Fee Structure to begin.",
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
