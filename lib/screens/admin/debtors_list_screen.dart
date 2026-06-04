import 'package:trideta_v2/utils/auth_error_handler.dart';
import 'package:trideta_v2/widgets/trideta_loader.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

class DebtorsListScreen extends StatefulWidget {
  const DebtorsListScreen({super.key});

  @override
  State<DebtorsListScreen> createState() => _DebtorsListScreenState();
}

class _DebtorsListScreenState extends State<DebtorsListScreen>
    with AuthErrorHandler {
  final _supabase = Supabase.instance.client;

  bool _isLoading = true;
  List<Map<String, dynamic>> _debtors = [];

  // 🚨 ADDED TO HOLD OFFICIAL CLASSES
  List<String> _officialClasses = [];

  @override
  void initState() {
    super.initState();
    _fetchDebtors();
  }

  // ===========================================================================
  // 🚨 LOGIC ENGINE: STRICTLY UNTOUCHED
  // ===========================================================================
  Future<void> _fetchDebtors() async {
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

      String currentSession = schoolData['current_session'] ?? "";

      if (currentSession.isEmpty) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      // 1.5 🚨 FETCH OFFICIAL CLASSES FROM RELATIONAL TABLE
      final classesData = await _supabase
          .from('classes')
          .select('name')
          .eq('school_id', schoolId)
          .order('list_order', ascending: true);

      _officialClasses = classesData.map((c) => c['name'].toString()).toList();

      // 2. Get Fee Structure (NOW FETCHING id)
      final rawFeeData = await _supabase
          .from('fee_structures')
          .select(
            'id, fee_name, amount, applicable_classes, applicable_class_ids, applicable_categories, academic_session',
          )
          .eq('school_id', schoolId);

      List<Map<String, dynamic>> feeData = [];
      for (var fee in rawFeeData) {
        String feeSession = (fee['academic_session'] ?? '').toString();
        if (feeSession == currentSession || feeSession.isEmpty) {
          feeData.add(fee);
        }
      }

      // 3. Get Transactions (NOW FETCHING fee_id)
      final txData = await _supabase
          .from('transactions')
          .select('student_id, category, amount, academic_session, fee_id')
          .eq('school_id', schoolId);

      // 🚨 GROUP PAYMENTS NATIVELY BY fee_id
      Map<String, Map<String, double>> studentCategoryPayments = {};
      for (var tx in txData) {
        String txSession = (tx['academic_session'] ?? '').toString();

        if (txSession == currentSession || txSession.isEmpty) {
          String sId = tx['student_id'].toString();
          String txFeeId = (tx['fee_id'] ?? '').toString();
          String txCategory = (tx['category'] ?? '').toString();
          double amt = (tx['amount'] ?? 0).toDouble();

          // 🚨 HYBRID GROUPING: Uses UUID if available, falls back to text if the migration script missed it
          String paymentKey = txFeeId.isNotEmpty ? txFeeId : txCategory;

          studentCategoryPayments.putIfAbsent(sId, () => {});
          studentCategoryPayments[sId]![paymentKey] =
              (studentCategoryPayments[sId]![paymentKey] ?? 0) + amt;
        }
      }

      // 4. Get All Students & Calculate True Debt
      final studentsData = await _supabase
          .from('students')
          .select('*')
          .eq('school_id', schoolId);

      List<Map<String, dynamic>> tempDebtors = [];

      for (var student in studentsData) {
        String sId = student['id'].toString();
        String cClass = (student['class_level'] ?? '').toString();
        String sClassId = (student['class_id'] ?? '').toString();
        String cCategory = (student['category'] ?? '').toString();

        double totalStudentDebt = 0.0;

        for (var fee in feeData) {
          String feeId = fee['id'].toString();
          String feeName = fee['fee_name'].toString();
          double expectedAmt = (fee['amount'] ?? 0).toDouble();

          bool classMatch = false;

          // Match by UUID first
          final List<dynamic>? classIdsList = fee['applicable_class_ids'];
          if (classIdsList != null &&
              classIdsList.isNotEmpty &&
              sClassId.isNotEmpty) {
            classMatch = classIdsList.contains(sClassId);
          } else {
            classMatch = _doesItApply(
              fee['applicable_classes'],
              cClass,
              officialList: _officialClasses,
            );
          }

          bool categoryMatch = _doesItApply(
            fee['applicable_categories'],
            cCategory,
            isCategory: true,
          );

          if (classMatch && categoryMatch) {
            // 🚨 NATIVE UUID LOOKUP: Checks for payments under the UUID, falls back to text name lookup
            double paidAmt =
                (studentCategoryPayments[sId]?[feeId] ?? 0.0) +
                (studentCategoryPayments[sId]?[feeName] ?? 0.0);

            double remaining = expectedAmt - paidAmt;
            if (remaining > 0) {
              totalStudentDebt += remaining;
            }
          }
        }

        if (totalStudentDebt > 0) {
          tempDebtors.add({
            'id': sId,
            'name':
                '${student['first_name'] ?? ''} ${student['last_name'] ?? ''}'
                    .trim(),
            'class': cClass,
            'phone': student['parent_phone'] ?? 'No Phone Provided',
            'debt': totalStudentDebt,
          });
        }
      }

      // Sort debtors by who owes the most
      tempDebtors.sort((a, b) => b['debt'].compareTo(a['debt']));

      if (mounted) {
        setState(() {
          _debtors = tempDebtors;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Debtors Fetch Error: $e");
      if (mounted) {
        setState(() => _isLoading = false);
        showAuthErrorDialog(
          "Failed to load debtors. Please check your internet connection.",
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

  Future<void> _makePhoneCall(String phoneNumber) async {
    final cleanNumber = phoneNumber.replaceAll(RegExp(r'[^\d+]'), '');
    final Uri launchUri = Uri(scheme: 'tel', path: cleanNumber);
    try {
      if (await canLaunchUrl(launchUri)) {
        await launchUrl(launchUri);
      } else {
        if (mounted) {
          showAuthErrorDialog(
            "Could not launch phone dialer. Your device might not support direct calling.",
          );
        }
      }
    } catch (e) {
      if (mounted) {
        showAuthErrorDialog("Invalid phone number format.");
      }
    }
  }

  // ===========================================================================
  // 🚨 PREMIUM UI (REFINED)
  // ===========================================================================

  void _showContactPopup(
    Map<String, dynamic> debtor,
    NumberFormat f,
    Color primaryColor,
  ) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          contentPadding: const EdgeInsets.all(30),
          title: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.person_rounded,
                  color: Colors.redAccent,
                  size: 35,
                ),
              ),
              const SizedBox(height: 15),
              Text(
                debtor['name'],
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  "Owes: ${f.format(debtor['debt'])}",
                  style: const TextStyle(
                    color: Colors.redAccent,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 20,
                  horizontal: 16,
                ),
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: primaryColor.withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      "PARENT CONTACT",
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      debtor['phone'],
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: primaryColor,
                        letterSpacing: 1.0,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],
          ),
          actionsAlignment: MainAxisAlignment.center,
          actionsPadding: const EdgeInsets.only(
            bottom: 25,
            left: 20,
            right: 20,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                "Close",
                style: TextStyle(
                  color: Colors.grey,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.green.shade600,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: () {
                Navigator.pop(context);
                _makePhoneCall(debtor['phone']);
              },
              icon: const Icon(
                Icons.call_rounded,
                size: 20,
                color: Colors.white,
              ),
              label: const Text(
                "CALL NOW",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color primaryColor = Theme.of(context).primaryColor;
    Color bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC);
    Color textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final currencyFormat = NumberFormat.currency(symbol: '₦', decimalDigits: 0);

    // Calculate dynamic header stats
    double totalDebtAmount = _debtors.fold(
      0.0,
      (sum, item) => sum + (item['debt'] as double),
    );
    int totalDebtors = _debtors.length;

    Widget mainContent = _isLoading
        ? Center(child: TridetaLoader(color: primaryColor))
        : _debtors.isEmpty
        ? _buildEmptyState(isDark)
        : Column(
            children: [
              _buildSummaryHeader(
                totalDebtAmount,
                totalDebtors,
                currencyFormat,
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 10,
                  ),
                  itemCount: _debtors.length,
                  itemBuilder: (context, index) {
                    final debtor = _debtors[index];
                    return _buildDebtorCard(
                      debtor,
                      isDark,
                      currencyFormat,
                      primaryColor,
                    );
                  },
                ),
              ),
            ],
          );

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text(
          "Debtors List",
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

  Widget _buildSummaryHeader(double totalDebt, int count, NumberFormat f) {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 10, 24, 20),
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.redAccent.shade700, Colors.redAccent.shade400],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.redAccent.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
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
                const Row(
                  children: [
                    Icon(
                      Icons.warning_rounded,
                      color: Colors.white70,
                      size: 16,
                    ),
                    SizedBox(width: 8),
                    Text(
                      "TOTAL OUTSTANDING DEBT",
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                FittedBox(
                  child: Text(
                    f.format(totalDebt),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    "Across $count Students",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDebtorCard(
    Map<String, dynamic> debtor,
    bool isDark,
    NumberFormat f,
    Color primaryColor,
  ) {
    Color cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    Color textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
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
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showContactPopup(debtor, f, primaryColor),
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.person_off_rounded,
                    color: Colors.redAccent,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        debtor['name'],
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: textColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        debtor['class'],
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      f.format(debtor['debt']),
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: Colors.redAccent,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: primaryColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        "Contact",
                        style: TextStyle(
                          color: primaryColor,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle_rounded,
              size: 60,
              color: Colors.green,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            "No Debtors Found!",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            "All students have fully paid their fees\nfor the current session.",
            style: TextStyle(color: Colors.grey.shade500, height: 1.4),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
