import 'package:trideta_v2/utils/auth_error_handler.dart';
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

  // --- 🚨 IRONCLAD FINANCIAL MATH ENGINE WITH LEGACY SAFEGUARDS 🚨 ---
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

      // 1.5 🚨 FETCH OFFICIAL CLASSES FROM RELATIONAL TABLE 🚨
      final classesData = await _supabase
          .from('classes')
          .select('name')
          .eq('school_id', schoolId)
          .order('list_order', ascending: true);

      _officialClasses = classesData.map((c) => c['name'].toString()).toList();

      // 2. Get Fee Structure (SAFELY HANDLING LEGACY DATA)
      final rawFeeData = await _supabase
          .from('fee_structures')
          .select(
            'fee_name, amount, applicable_classes, applicable_categories, academic_session',
          )
          .eq('school_id', schoolId);

      List<Map<String, dynamic>> feeData = [];
      for (var fee in rawFeeData) {
        String feeSession = (fee['academic_session'] ?? '').toString();
        // 🚨 LEGACY SAFEGUARD: Accept current session OR empty (old data)
        if (feeSession == currentSession || feeSession.isEmpty) {
          feeData.add(fee);
        }
      }

      // 3. Get Transactions (SAFELY HANDLING LEGACY DATA)
      final txData = await _supabase
          .from('transactions')
          .select('student_id, category, amount, academic_session')
          .eq('school_id', schoolId);

      // Group payments by Student AND Category
      Map<String, Map<String, double>> studentCategoryPayments = {};
      for (var tx in txData) {
        String txSession = (tx['academic_session'] ?? '').toString();

        // 🚨 LEGACY SAFEGUARD: Only count matching sessions or legacy empty sessions
        if (txSession == currentSession || txSession.isEmpty) {
          String sId = tx['student_id'].toString();
          String category = (tx['category'] ?? '').toString();
          double amt = (tx['amount'] ?? 0).toDouble();

          studentCategoryPayments.putIfAbsent(sId, () => {});
          studentCategoryPayments[sId]![category] =
              (studentCategoryPayments[sId]![category] ?? 0) + amt;
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
        String cCategory = (student['category'] ?? '').toString();

        double totalStudentDebt = 0.0;

        // 🚨 SQUASHED PHANTOM CREDIT BUG: Check debt item by item!
        for (var fee in feeData) {
          String feeName = fee['fee_name'].toString();
          double expectedAmt = (fee['amount'] ?? 0).toDouble();

          // 🚨 Passing _officialClasses to _doesItApply for dynamic 'All' resolution
          bool classMatch = _doesItApply(
            fee['applicable_classes'],
            cClass,
            officialList: _officialClasses,
          );
          bool categoryMatch = _doesItApply(
            fee['applicable_categories'],
            cCategory,
            isCategory: true,
          );

          if (classMatch && categoryMatch) {
            double paidAmt = studentCategoryPayments[sId]?[feeName] ?? 0.0;
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

  // --- THE BUILT-IN TRANSLATOR ---
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

  // --- THE SMART MATCHER ---
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

    if (cleanStudentData.isEmpty || cleanStudentData == 'notfound')
      return false;
    if (columnData == null) return true;

    String colStr = isCategory
        ? columnData.toString().replaceAll(' ', '').toLowerCase()
        : _standardizeClass(columnData.toString());

    // 🚨 If 'all', instantly approve
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

  // --- AUTOMATIC DIALER LOGIC ---
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

  // --- NEW CENTERED POPUP DIALOG ---
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
            borderRadius: BorderRadius.circular(20),
          ),
          contentPadding: const EdgeInsets.all(25),
          title: Column(
            children: [
              CircleAvatar(
                radius: 35,
                backgroundColor: Colors.redAccent.withOpacity(0.1),
                child: const Icon(
                  Icons.person,
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
              const SizedBox(height: 5),
              Text(
                "Owes: ${f.format(debtor['debt'])}",
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
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
                  vertical: 15,
                  horizontal: 10,
                ),
                decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.05), // 🚨 Dynamic color
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(
                    color: primaryColor.withOpacity(0.2),
                  ), // 🚨 Dynamic color
                ),
                child: Column(
                  children: [
                    const Text(
                      "PARENT CONTACT",
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 5),
                    SelectableText(
                      debtor['phone'],
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: primaryColor, // 🚨 Dynamic color
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
            bottom: 20,
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
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                elevation: 0,
              ),
              onPressed: () {
                Navigator.pop(context); // Close the dialog first
                _makePhoneCall(debtor['phone']); // Then launch the dialer
              },
              icon: const Icon(Icons.call, size: 20),
              label: const Text(
                "Call Now",
                style: TextStyle(fontWeight: FontWeight.bold),
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
    final currencyFormat = NumberFormat.currency(symbol: '₦', decimalDigits: 2);

    // 🚨 DYNAMIC COLOR INJECTION
    Color primaryColor = Theme.of(context).primaryColor;
    Color bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text(
          "Debtors List",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.redAccent, // Kept red for urgency!
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      // 🚨 SHAPE-SHIFTER: LayoutBuilder
      body: LayoutBuilder(
        builder: (context, constraints) {
          Widget mainContent = _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.redAccent),
                )
              : _debtors.isEmpty
              ? _buildEmptyState()
              : ListView.separated(
                  padding: const EdgeInsets.all(20),
                  itemCount: _debtors.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 15),
                  itemBuilder: (context, index) {
                    final debtor = _debtors[index];
                    return _buildDebtorCard(
                      debtor,
                      isDark,
                      currencyFormat,
                      primaryColor,
                    );
                  },
                );

          if (constraints.maxWidth > 800) {
            // 💻 DESKTOP LAYOUT (Constrained Center Column)
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

  Widget _buildDebtorCard(
    Map<String, dynamic> debtor,
    bool isDark,
    NumberFormat f,
    Color primaryColor,
  ) {
    return InkWell(
      onTap: () => _showContactPopup(debtor, f, primaryColor),
      borderRadius: BorderRadius.circular(15),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: isDark ? Colors.white10 : Colors.grey.shade200,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: Colors.redAccent.withOpacity(0.1),
              child: const Icon(Icons.warning_rounded, color: Colors.redAccent),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    debtor['name'],
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    debtor['class'],
                    style: const TextStyle(color: Colors.grey, fontSize: 13),
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
                const Text(
                  "Tap to Contact",
                  style: TextStyle(color: Colors.grey, fontSize: 10),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 80,
            color: Colors.green.withOpacity(0.5),
          ),
          const SizedBox(height: 20),
          const Text(
            "No Debtors Found!",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          const Text(
            "All students have fully paid their fees for the current session.",
            style: TextStyle(color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
