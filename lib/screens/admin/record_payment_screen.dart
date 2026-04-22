import 'package:trideta_v2/utils/auth_error_handler.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

import 'package:trideta_v2/screens/admin/receipt_view_screen.dart';

class RecordPaymentScreen extends StatefulWidget {
  const RecordPaymentScreen({super.key});

  @override
  State<RecordPaymentScreen> createState() => _RecordPaymentScreenState();
}

class _RecordPaymentScreenState extends State<RecordPaymentScreen>
    with AuthErrorHandler {
  final _supabase = Supabase.instance.client;

  bool _isLoading = true;
  bool _hasFees = false;
  String? _schoolId;
  String _currentSession = "";

  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  Map<String, dynamic>? _selectedStudent;
  double _outstandingBalance = 0.0;

  final _amountController = TextEditingController();
  List<Map<String, dynamic>> _allFeeRules = [];
  List<Map<String, dynamic>> _availableFeeOptions = [];

  String? _selectedCategory;
  String _paymentMethod = "Cash";
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  Future<void> _initializeData() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final profile = await _supabase
          .from('profiles')
          .select('school_id')
          .eq('id', user.id)
          .single();
      _schoolId = profile['school_id'];

      // Fetch School Session
      final schoolData = await _supabase
          .from('schools')
          .select('current_session')
          .eq('id', _schoolId!)
          .single();
      _currentSession = schoolData['current_session'] ?? "";

      // Fetch ALL Fee Structures (We filter locally to protect legacy data)
      final rawFeeData = await _supabase
          .from('fee_structures')
          .select()
          .eq('school_id', _schoolId!);

      List<Map<String, dynamic>> validFees = [];
      for (var fee in rawFeeData) {
        String feeSession = (fee['academic_session'] ?? '').toString();
        // 🚨 LEGACY SAFEGUARD: Accept current session OR empty (old data)
        if (feeSession == _currentSession || feeSession.isEmpty) {
          validFees.add(fee);
        }
      }

      if (mounted) {
        setState(() {
          _hasFees = validFees.isNotEmpty;
          if (_hasFees) {
            _allFeeRules = validFees;
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      showAuthErrorDialog(
        "Failed to load school financial data. Please check your connection.",
      );
    }
  }

  void _autoFillAmount(String categoryName) {
    try {
      final option = _availableFeeOptions.firstWhere(
        (f) => f['name'] == categoryName,
      );
      setState(() {
        _amountController.text = option['remaining'].toStringAsFixed(0);
      });
    } catch (e) {
      debugPrint("Auto-fill error: $e");
    }
  }

  // --- 🚨 BULLETPROOF MATH WITH LEGACY SAFEGUARDS 🚨 ---
  Future<void> _syncStudentFinancials(Map<String, dynamic> student) async {
    try {
      // 1. Get student's specific class & category
      final studentData = await _supabase
          .from('students')
          .select('class_level, category')
          .eq('id', student['id'])
          .single();

      String sClass = (studentData['class_level'] ?? '').toString();
      String sCategory = (studentData['category'] ?? '').toString();

      // 2. Filter Fee Structures that APPLY to this student
      List<Map<String, dynamic>> applicableFees = [];
      for (var rule in _allFeeRules) {
        bool classMatch = _doesItApply(rule['applicable_classes'], sClass);
        bool categoryMatch = _doesItApply(
          rule['applicable_categories'],
          sCategory,
          isCategory: true,
        );

        if (classMatch && categoryMatch) {
          applicableFees.add(rule);
        }
      }

      // 3. Get student's transactions
      final txData = await _supabase
          .from('transactions')
          .select('category, amount, academic_session')
          .eq('student_id', student['id'])
          .eq('school_id', _schoolId!);

      // Group payments by Fee Category (Safely handling legacy data)
      Map<String, double> paidPerCategory = {};
      for (var tx in txData) {
        String txSession = (tx['academic_session'] ?? '').toString();

        // 🚨 LEGACY SAFEGUARD: Only count matching sessions or legacy empty sessions
        if (txSession == _currentSession || txSession.isEmpty) {
          String feeName = tx['category'].toString();
          double amt = (tx['amount'] ?? 0).toDouble();
          paidPerCategory[feeName] = (paidPerCategory[feeName] ?? 0.0) + amt;
        }
      }

      // 4. Calculate true remaining balances (Itemized Math)
      List<Map<String, dynamic>> options = [];
      double totalDebt = 0.0;

      for (var fee in applicableFees) {
        String feeName = fee['fee_name'];
        double expected = (fee['amount'] ?? 0).toDouble();
        double paid = paidPerCategory[feeName] ?? 0.0;
        double remaining = expected - paid;

        if (remaining > 0) {
          options.add({
            'name': feeName,
            'display': '$feeName (Owes ₦${remaining.toStringAsFixed(0)})',
            'remaining': remaining,
          });
          totalDebt += remaining;
        }
      }

      if (mounted) {
        setState(() {
          _availableFeeOptions = options;
          _selectedCategory = options.isNotEmpty ? options.first['name'] : null;
          if (_selectedCategory != null) _autoFillAmount(_selectedCategory!);
          _outstandingBalance = totalDebt;
        });
      }
    } catch (e) {
      debugPrint("Financial Sync error: $e");
    }
  }

  // --- THE SMART MATCHER WIDGETS ---
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

  Future<void> _searchStudent(String query) async {
    if (query.isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    final res = await _supabase
        .from('students')
        .select('id, first_name, last_name, admission_no, class_level')
        .eq('school_id', _schoolId!)
        .or(
          'first_name.ilike.%$query%,last_name.ilike.%$query%,admission_no.ilike.%$query%',
        )
        .limit(5);
    setState(() => _searchResults = List<Map<String, dynamic>>.from(res));
  }

  void _onStudentSelected(Map<String, dynamic> student) {
    FocusScope.of(context).unfocus();
    _searchController.text = "${student['first_name']} ${student['last_name']}";
    setState(() {
      _selectedStudent = student;
      _searchResults = [];
    });
    _syncStudentFinancials(student);
  }

  Future<void> _processPayment() async {
    if (_selectedStudent == null ||
        _selectedCategory == null ||
        _amountController.text.isEmpty) {
      return;
    }

    double inputAmount = double.tryParse(_amountController.text) ?? 0.0;
    if (inputAmount <= 0) {
      showAuthErrorDialog("Please enter a valid payment amount.");
      return;
    }

    setState(() => _isProcessing = true);
    try {
      // 🚨 Ensure we attach the current session to the transaction!
      final txnData = await _supabase
          .from('transactions')
          .insert({
            'school_id': _schoolId,
            'student_id': _selectedStudent!['id'],
            'student_name':
                "${_selectedStudent!['first_name']} ${_selectedStudent!['last_name']}",
            'amount': inputAmount,
            'category': _selectedCategory,
            'title': _selectedCategory,
            'payment_method': _paymentMethod,
            'academic_session': _currentSession, // Saves to current term
            'receipt_no':
                "REC-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}",
          })
          .select()
          .single();

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ReceiptViewScreen(transactionData: txnData),
          ),
        );
      }
    } catch (e) {
      setState(() => _isProcessing = false);
      showAuthErrorDialog(
        "Payment processing failed. Please check your connection and try again.",
      );
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
        body: Center(child: CircularProgressIndicator(color: primaryColor)),
      );
    }

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text(
          "Record Payment",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildLabel("SEARCH STUDENT", isDark),
            TextField(
              controller: _searchController,
              onChanged: _searchStudent,
              decoration: _inputStyle(
                "Type name...",
                Icons.person_search_rounded,
                isDark,
                primaryColor,
              ),
            ),

            if (_searchResults.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 8),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: const [
                    BoxShadow(color: Colors.black12, blurRadius: 10),
                  ],
                ),
                child: Column(
                  children: _searchResults
                      .map(
                        (s) => ListTile(
                          title: Text("${s['first_name']} ${s['last_name']}"),
                          subtitle: Text(s['class_level']),
                          onTap: () => _onStudentSelected(s),
                        ),
                      )
                      .toList(),
                ),
              ),

            if (_selectedStudent != null) ...[
              const SizedBox(height: 25),
              _buildBalanceCard(primaryColor),
              const SizedBox(height: 25),
              _buildLabel("PAYMENT INFO", isDark),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: _selectedCategory,
                      isExpanded: true,
                      decoration: _inputStyle(
                        "Payment Purpose",
                        Icons.list_alt_rounded,
                        isDark,
                        primaryColor,
                      ),
                      items: _availableFeeOptions
                          .map(
                            (e) => DropdownMenuItem<String>(
                              value: e['name'],
                              child: Text(
                                e['display'],
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (val) {
                        setState(() => _selectedCategory = val);
                        if (val != null) _autoFillAmount(val);
                      },
                      disabledHint: const Text(
                        "All fees for this term are fully paid! 🎉",
                        style: TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 15),
                    TextField(
                      controller: _amountController,
                      keyboardType: TextInputType.number,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: primaryColor,
                      ),
                      decoration: _inputStyle(
                        "Amount",
                        Icons.payments_rounded,
                        isDark,
                        primaryColor,
                      ).copyWith(prefixText: "₦ "),
                    ),
                    const SizedBox(height: 15),
                    DropdownButtonFormField<String>(
                      initialValue: _paymentMethod,
                      decoration: _inputStyle(
                        "Method",
                        Icons.account_balance_rounded,
                        isDark,
                        primaryColor,
                      ),
                      items: ["Cash", "Bank Transfer", "POS"]
                          .map(
                            (e) => DropdownMenuItem(value: e, child: Text(e)),
                          )
                          .toList(),
                      onChanged: (val) => setState(() => _paymentMethod = val!),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  onPressed: (_isProcessing || _selectedCategory == null)
                      ? null
                      : _processPayment,
                  icon: const Icon(
                    Icons.check_circle_outline,
                    color: Colors.white,
                  ),
                  label: Text(
                    _selectedCategory == null
                        ? "FEES COMPLETED"
                        : "PROCESS PAYMENT",
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(String t, bool d) => Padding(
    padding: const EdgeInsets.only(bottom: 8, left: 4),
    child: Text(
      t,
      style: TextStyle(
        fontWeight: FontWeight.w800,
        fontSize: 10,
        color: d ? Colors.white54 : Colors.grey,
      ),
    ),
  );

  Widget _buildBalanceCard(Color primaryColor) {
    final f = NumberFormat.currency(symbol: '₦');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [primaryColor, primaryColor.withOpacity(0.7)],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Text(
            _selectedStudent!['first_name'].toString().toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 15),
          const Text(
            "OUTSTANDING BALANCE",
            style: TextStyle(
              color: Colors.white60,
              fontSize: 9,
              letterSpacing: 1,
            ),
          ),
          FittedBox(
            child: Text(
              f.format(_outstandingBalance),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 35,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputStyle(
    String l,
    IconData i,
    bool d,
    Color primaryColor,
  ) => InputDecoration(
    labelText: l,
    prefixIcon: Icon(i, color: primaryColor),
    filled: true,
    fillColor: d ? Colors.white.withOpacity(0.03) : Colors.grey[50],
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(15),
      borderSide: BorderSide.none,
    ),
  );
}
