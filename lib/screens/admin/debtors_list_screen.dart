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

  List<String> _officialClasses = [];

  bool _isFeesActivated = false;
  String _activeSessionLabel = "CURRENT TERM";

  @override
  void initState() {
    super.initState();
    _fetchDebtors();
  }

  // ===========================================================================
  // 🚨 LOGIC ENGINE: UPGRADED & BULLETPROOFED (CURRENT TERM ONLY)
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

      // 1. FETCH ACTIVE SESSION & TERM
      final schoolData = await _supabase
          .from('schools')
          .select('current_session, current_term')
          .eq('id', schoolId)
          .single();

      String currentSession = schoolData['current_session'] ?? "";
      String currentTerm = schoolData['current_term'] ?? "";
      String sessionLabel = "CURRENT TERM";

      if (currentSession.isNotEmpty) {
        sessionLabel = "$currentSession • $currentTerm".toUpperCase();
      } else {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      // 1.5 FETCH OFFICIAL CLASSES FROM RELATIONAL TABLE
      final classesData = await _supabase
          .from('classes')
          .select('name')
          .eq('school_id', schoolId)
          .order('list_order', ascending: true);

      _officialClasses = classesData.map((c) => c['name'].toString()).toList();

      // 2. Get Fee Structure (STRICTLY FILTERED BY ACTIVE TIMELINE)
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

        if ((feeSession == currentSession || feeSession.isEmpty) &&
            (feeTerm == currentTerm || feeTerm == 'All Terms')) {
          feeData.add(fee);
        }
      }

      // 3. Get Transactions (STRICTLY FILTERED BY ACTIVE TIMELINE)
      final txData = await _supabase
          .from('transactions')
          .select(
            'student_id, category, amount, academic_session, academic_term, fee_id',
          )
          .eq('school_id', schoolId);

      Map<String, Map<String, double>> studentCategoryPayments = {};
      for (var tx in txData) {
        String txSession = (tx['academic_session'] ?? '').toString();
        String txTerm = (tx['academic_term'] ?? 'All Terms').toString();

        if ((txSession == currentSession || txSession.isEmpty) &&
            (txTerm == currentTerm || txTerm == 'All Terms')) {
          String sId = tx['student_id'].toString();
          String txFeeId = (tx['fee_id'] ?? '').toString();
          String txCategory = (tx['category'] ?? '').toString();
          double amt = (tx['amount'] ?? 0).toDouble();

          String paymentKey = txFeeId.isNotEmpty ? txFeeId : txCategory;

          studentCategoryPayments.putIfAbsent(sId, () => {});
          studentCategoryPayments[sId]![paymentKey] =
              (studentCategoryPayments[sId]![paymentKey] ?? 0) + amt;
        }
      }

      // 4. Get All Active Students & Calculate True Debt
      final studentsData = await _supabase
          .from('students')
          .select(
            'id, first_name, last_name, class_level, class_id, category, parent_phone, wallet_balance',
          )
          .eq('school_id', schoolId)
          .eq('is_active', true);

      List<Map<String, dynamic>> tempDebtors = [];

      for (var student in studentsData) {
        String sId = student['id'].toString();
        String cClass = (student['class_level'] ?? '').toString();
        String sClassId = (student['class_id'] ?? '').toString();
        String cCategory = (student['category'] ?? '').toString();
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
            } catch (e) {}
          } else if (rawClassIds is List) {
            classIdsList = rawClassIds;
          }

          if (classIdsList.isNotEmpty && sClassId.isNotEmpty) {
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
        double availableCredit = walletBalance > 0 ? walletBalance : 0.0;
        double finalTrueDebt = activeStudentDebt - availableCredit;

        if (finalTrueDebt > 0) {
          tempDebtors.add({
            'id': sId,
            'name':
                '${student['first_name'] ?? ''} ${student['last_name'] ?? ''}'
                    .trim(),
            'class': cClass,
            'phone': student['parent_phone'] ?? 'No Phone Provided',
            'debt': finalTrueDebt,
          });
        }
      }

      tempDebtors.sort((a, b) => b['debt'].compareTo(a['debt']));

      if (mounted) {
        setState(() {
          _debtors = tempDebtors;
          _isFeesActivated = feeData.isNotEmpty;
          _activeSessionLabel = sessionLabel;
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
    if (cleanStudentData.isEmpty || cleanStudentData == 'notfound')
      return false;
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
  // 🚨 PREMIUM UI (REFINED & STICKY)
  // ===========================================================================

  void _showContactPopup(
    Map<String, dynamic> debtor,
    NumberFormat f,
    Color primaryColor,
  ) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color modalColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: modalColor,
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

    double totalDebtAmount = _debtors.fold(
      0.0,
      (sum, item) => sum + (item['debt'] as double),
    );
    int totalDebtors = _debtors.length;

    // 🚨 UI FIX: Rebuilt entirely as a CustomScrollView for Sticky Header integration
    Widget mainContent = _isLoading
        ? Center(child: TridetaLoader(color: primaryColor))
        : RefreshIndicator(
            onRefresh: _fetchDebtors,
            color: primaryColor,
            child: _debtors.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(
                        height: MediaQuery.of(context).size.height * 0.7,
                        child: _buildEmptyState(isDark),
                      ),
                    ],
                  )
                : CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      // ─── 1. SLIM STICKY HEADER ───
                      SliverPersistentHeader(
                        pinned: true,
                        delegate: _StickyDebtHeaderDelegate(
                          totalDebt: totalDebtAmount,
                          count: totalDebtors,
                          sessionLabel: _activeSessionLabel,
                          f: currencyFormat,
                          bgColor: bgColor,
                        ),
                      ),
                      // ─── 2. EDGE-TO-EDGE DEBTORS LIST ───
                      SliverPadding(
                        padding: const EdgeInsets.only(bottom: 50),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate((
                            context,
                            index,
                          ) {
                            final debtor = _debtors[index];
                            return _buildDebtorCard(
                              debtor,
                              isDark,
                              currencyFormat,
                              primaryColor,
                            );
                          }, childCount: _debtors.length),
                        ),
                      ),
                    ],
                  ),
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

  Widget _buildDebtorCard(
    Map<String, dynamic> debtor,
    bool isDark,
    NumberFormat f,
    Color primaryColor,
  ) {
    Color textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);

    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _showContactPopup(debtor, f, primaryColor),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 8,
              ),
              leading: CircleAvatar(
                radius: 24,
                backgroundColor: Colors.redAccent.withValues(alpha: 0.1),
                child: const Icon(
                  Icons.person_off_rounded,
                  color: Colors.redAccent,
                  size: 24,
                ),
              ),
              title: Text(
                debtor['name'],
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: textColor,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  debtor['class'],
                  style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              trailing: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
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
                  const SizedBox(height: 4),
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
      ],
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
              color: _isFeesActivated
                  ? Colors.green.withValues(alpha: 0.1)
                  : Colors.orange.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _isFeesActivated
                  ? Icons.check_circle_rounded
                  : Icons.info_outline_rounded,
              size: 60,
              color: _isFeesActivated ? Colors.green : Colors.orange,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            _isFeesActivated ? "No Debtors Found!" : "Setup Required",
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              _isFeesActivated
                  ? "All students have fully paid their school fees\nfor the current term."
                  : "Fee structure hasn't been added for the current term, please add a fee structure to see debtors.",
              style: TextStyle(color: Colors.grey.shade500, height: 1.4),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// 🚨 SLIM STICKY HEADER DELEGATE
// ===========================================================================
class _StickyDebtHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double totalDebt;
  final int count;
  final String sessionLabel;
  final NumberFormat f;
  final Color bgColor;

  _StickyDebtHeaderDelegate({
    required this.totalDebt,
    required this.count,
    required this.sessionLabel,
    required this.f,
    required this.bgColor,
  });

  @override
  double get minExtent => 100.0;

  @override
  double get maxExtent => 100.0;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      color: bgColor,
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      child: Container(
        width: double.infinity,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.redAccent.shade700, Colors.redAccent.shade400],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            if (overlapsContent)
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              right: -20,
              top: -20,
              child: CircleAvatar(
                radius: 50,
                backgroundColor: Colors.white.withValues(alpha: 0.1),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.warning_rounded,
                              color: Colors.white70,
                              size: 14,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              "OUTSTANDING DEBT",
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        FittedBox(
                          child: Text(
                            f.format(totalDebt),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          sessionLabel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "$count Students",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _StickyDebtHeaderDelegate oldDelegate) {
    return totalDebt != oldDelegate.totalDebt ||
        count != oldDelegate.count ||
        sessionLabel != oldDelegate.sessionLabel ||
        bgColor != oldDelegate.bgColor;
  }
}
