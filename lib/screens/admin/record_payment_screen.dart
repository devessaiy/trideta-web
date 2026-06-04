import 'package:trideta_v2/utils/auth_error_handler.dart';
import 'package:trideta_v2/widgets/trideta_loader.dart';
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

  // 🚨 NEW: State to hold active classes for the Browse Grid
  List<Map<String, dynamic>> _activeClasses = [];

  String? _selectedCategory;
  String _paymentMethod = "Cash";
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  // ===========================================================================
  // 🚨 LOGIC ENGINE: STRICTLY UNTOUCHED (Only added lightweight class fetch)
  // ===========================================================================
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

      // Fetch ALL Fee Structures
      final rawFeeData = await _supabase
          .from('fee_structures')
          .select()
          .eq('school_id', _schoolId!);

      List<Map<String, dynamic>> validFees = [];
      for (var fee in rawFeeData) {
        String feeSession = (fee['academic_session'] ?? '').toString();
        if (feeSession == _currentSession || feeSession.isEmpty) {
          validFees.add(fee);
        }
      }

      // 🚨 NEW: Fetch active classes to populate the Browse Grid
      final classesData = await _supabase
          .from('classes')
          .select('id, name')
          .eq('school_id', _schoolId!)
          .order('list_order', ascending: true);

      if (mounted) {
        setState(() {
          _activeClasses = List<Map<String, dynamic>>.from(classesData);
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

  Future<void> _syncStudentFinancials(Map<String, dynamic> student) async {
    try {
      final studentData = await _supabase
          .from('students')
          .select('class_level, class_id, category')
          .eq('id', student['id'])
          .single();

      String sClass = (studentData['class_level'] ?? '').toString();
      String sClassId = (studentData['class_id'] ?? '').toString();
      String sCategory = (studentData['category'] ?? '').toString();

      List<Map<String, dynamic>> applicableFees = [];
      for (var rule in _allFeeRules) {
        bool classMatch = false;
        final List<dynamic>? classIdsList = rule['applicable_class_ids'];

        if (classIdsList != null &&
            classIdsList.isNotEmpty &&
            sClassId.isNotEmpty) {
          classMatch = classIdsList.contains(sClassId);
        } else {
          classMatch = _doesItApply(rule['applicable_classes'], sClass);
        }

        bool categoryMatch = _doesItApply(
          rule['applicable_categories'],
          sCategory,
          isCategory: true,
        );

        if (classMatch && categoryMatch) {
          applicableFees.add(rule);
        }
      }

      final txData = await _supabase
          .from('transactions')
          .select('category, amount, academic_session, fee_id')
          .eq('student_id', student['id'])
          .eq('school_id', _schoolId!);

      List<Map<String, dynamic>> options = [];
      double totalDebt = 0.0;

      for (var fee in applicableFees) {
        String feeId = fee['id'].toString();
        String feeName = fee['fee_name'].toString();
        double expectedAmt = (fee['amount'] ?? 0).toDouble();

        double paidAmt = 0.0;
        for (var tx in txData) {
          String txSession = (tx['academic_session'] ?? '').toString();

          if (txSession == _currentSession || txSession.isEmpty) {
            String txFeeId = (tx['fee_id'] ?? '').toString();
            String txCategory = (tx['category'] ?? '').toString();

            if (txFeeId.isNotEmpty && txFeeId == feeId) {
              paidAmt += (tx['amount'] ?? 0).toDouble();
            } else if (txFeeId.isEmpty && txCategory == feeName) {
              paidAmt += (tx['amount'] ?? 0).toDouble();
            }
          }
        }

        double remaining = expectedAmt - paidAmt;

        if (remaining > 0) {
          options.add({
            'fee_id': feeId,
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
    _searchController.clear();
    setState(() {
      _selectedStudent = student;
      _searchResults = [];
    });
    _syncStudentFinancials(student);
  }

  void _clearSelectedStudent() {
    setState(() {
      _selectedStudent = null;
      _outstandingBalance = 0.0;
      _availableFeeOptions = [];
      _selectedCategory = null;
      _amountController.clear();
    });
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

    final selectedFeeOption = _availableFeeOptions.firstWhere(
      (opt) => opt['name'] == _selectedCategory,
    );
    String targetFeeId = selectedFeeOption['fee_id'];

    setState(() => _isProcessing = true);
    try {
      final txnData = await _supabase
          .from('transactions')
          .insert({
            'school_id': _schoolId,
            'student_id': _selectedStudent!['id'],
            'fee_id': targetFeeId,
            'student_name':
                "${_selectedStudent!['first_name']} ${_selectedStudent!['last_name']}",
            'amount': inputAmount,
            'category': _selectedCategory,
            'title': _selectedCategory,
            'payment_method': _paymentMethod,
            'academic_session': _currentSession,
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

  // ===========================================================================
  // 🚨 PREMIUM UI & ROSTER BOTTOM SHEET
  // ===========================================================================

  void _showClassRoster(
    Map<String, dynamic> schoolClass,
    Color primaryColor,
    bool isDark,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: 600),
      builder: (ctx) => _ClassRosterSheet(
        schoolClass: schoolClass,
        schoolId: _schoolId!,
        primaryColor: primaryColor,
        isDark: isDark,
        onStudentSelected: (student) {
          Navigator.pop(ctx);
          _onStudentSelected(student);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC);
    Color cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    Color textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    Color primaryColor = Theme.of(context).primaryColor;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: bgColor,
        body: Center(child: TridetaLoader(color: primaryColor)),
      );
    }

    Widget mainContent = SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── STATE 1: NO STUDENT SELECTED (Search or Browse) ───
          if (_selectedStudent == null) ...[
            _buildLabel("SEARCH STUDENT", isDark, primaryColor),
            TextField(
              controller: _searchController,
              onChanged: _searchStudent,
              style: TextStyle(fontWeight: FontWeight.bold, color: textColor),
              decoration: _inputStyle(
                "Type name or admission number...",
                Icons.person_search_rounded,
                isDark,
                primaryColor,
              ),
            ),

            if (_searchResults.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 12),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isDark ? Colors.white10 : Colors.grey.shade200,
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Column(
                    children: _searchResults.map((s) {
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 8,
                        ),
                        leading: CircleAvatar(
                          backgroundColor: primaryColor.withValues(alpha: 0.1),
                          child: Text(
                            s['first_name'][0].toUpperCase(),
                            style: TextStyle(
                              color: primaryColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(
                          "${s['first_name']} ${s['last_name']}",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                        ),
                        subtitle: Text(
                          s['class_level'],
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 12,
                          ),
                        ),
                        trailing: Icon(
                          Icons.chevron_right_rounded,
                          color: Colors.grey.shade300,
                        ),
                        onTap: () => _onStudentSelected(s),
                      );
                    }).toList(),
                  ),
                ),
              ),

            // Browse By Class Grid
            if (_searchController.text.isEmpty &&
                _activeClasses.isNotEmpty) ...[
              const SizedBox(height: 35),
              _buildLabel("OR BROWSE BY CLASS", isDark, primaryColor),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 2.2,
                ),
                itemCount: _activeClasses.length,
                itemBuilder: (ctx, i) {
                  final c = _activeClasses[i];
                  return InkWell(
                    onTap: () => _showClassRoster(c, primaryColor, isDark),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isDark ? Colors.white10 : Colors.grey.shade200,
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.02),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.class_rounded,
                            color: primaryColor.withValues(alpha: 0.7),
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              c['name'],
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: textColor,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ],

          // ─── STATE 2: STUDENT SELECTED (Payment Form) ───
          if (_selectedStudent != null) ...[
            _buildBalanceCard(primaryColor, isDark),
            const SizedBox(height: 35),

            _buildLabel("PAYMENT DETAILS", isDark, primaryColor),
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
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _selectedCategory,
                    isExpanded: true,
                    dropdownColor: isDark
                        ? const Color(0xFF2C2C2C)
                        : Colors.white,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: textColor,
                      fontSize: 14,
                    ),
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
                            child: Text(e['display']),
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
                  const SizedBox(height: 20),

                  TextField(
                    controller: _amountController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Colors.green,
                    ),
                    decoration: _inputStyle(
                      "Amount",
                      Icons.payments_rounded,
                      isDark,
                      Colors.green,
                    ).copyWith(prefixText: "₦ "),
                  ),
                  const SizedBox(height: 20),

                  DropdownButtonFormField<String>(
                    initialValue: _paymentMethod,
                    dropdownColor: isDark
                        ? const Color(0xFF2C2C2C)
                        : Colors.white,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: textColor,
                      fontSize: 14,
                    ),
                    decoration: _inputStyle(
                      "Payment Method",
                      Icons.account_balance_rounded,
                      isDark,
                      primaryColor,
                    ),
                    items: ["Cash", "Bank Transfer", "POS"]
                        .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                        .toList(),
                    onChanged: (val) => setState(() => _paymentMethod = val!),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 35),

            SizedBox(
              width: double.infinity,
              height: 60,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.green.shade600,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                onPressed: (_isProcessing || _selectedCategory == null)
                    ? null
                    : _processPayment,
                icon: _isProcessing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: TridetaLoader(color: Colors.white),
                      )
                    : const Icon(
                        Icons.check_circle_rounded,
                        color: Colors.white,
                      ),
                label: Text(
                  _selectedCategory == null
                      ? "FEES COMPLETED"
                      : "PROCESS PAYMENT",
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ],
      ),
    );

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text(
          "Record Payment",
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

  Widget _buildLabel(String t, bool isDark, Color pColor) => Padding(
    padding: const EdgeInsets.only(bottom: 12, left: 4),
    child: Text(
      t,
      style: TextStyle(
        fontWeight: FontWeight.w900,
        fontSize: 11,
        color: pColor.withValues(alpha: 0.8),
        letterSpacing: 1.2,
      ),
    ),
  );

  Widget _buildBalanceCard(Color primaryColor, bool isDark) {
    final f = NumberFormat.currency(symbol: '₦', decimalDigits: 0);
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
        boxShadow: [
          BoxShadow(
            color: primaryColor.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.2),
          width: 1.5,
        ),
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
            padding: const EdgeInsets.all(30),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.person_rounded,
                      color: Colors.white70,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _selectedStudent!['first_name']
                            .toString()
                            .toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          letterSpacing: 1.0,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // 🚨 NEW: Quick Change Button
                    InkWell(
                      onTap: _clearSelectedStudent,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          children: [
                            Text(
                              "Change",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(width: 4),
                            Icon(
                              Icons.sync_rounded,
                              color: Colors.white,
                              size: 12,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 25),
                const Text(
                  "OUTSTANDING BALANCE",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 5),
                FittedBox(
                  child: Text(
                    f.format(_outstandingBalance),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 40,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1.0,
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

  InputDecoration _inputStyle(
    String label,
    IconData icon,
    bool isDark,
    Color pColor,
  ) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: Colors.grey.shade500, fontSize: 14),
      prefixIcon: Icon(icon, color: pColor, size: 20),
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
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: pColor.withValues(alpha: 0.5), width: 2),
      ),
    );
  }
}

// ============================================================================
// 🚨 NEW: CLASS ROSTER BOTTOM SHEET
// ============================================================================
class _ClassRosterSheet extends StatefulWidget {
  final Map<String, dynamic> schoolClass;
  final String schoolId;
  final Color primaryColor;
  final bool isDark;
  final Function(Map<String, dynamic>) onStudentSelected;

  const _ClassRosterSheet({
    required this.schoolClass,
    required this.schoolId,
    required this.primaryColor,
    required this.isDark,
    required this.onStudentSelected,
  });

  @override
  State<_ClassRosterSheet> createState() => _ClassRosterSheetState();
}

class _ClassRosterSheetState extends State<_ClassRosterSheet> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _students = [];

  @override
  void initState() {
    super.initState();
    _fetchStudents();
  }

  Future<void> _fetchStudents() async {
    final res = await Supabase.instance.client
        .from('students')
        .select(
          'id, first_name, last_name, admission_no, class_level, class_id, category',
        )
        .eq('class_id', widget.schoolClass['id'])
        .order('first_name');

    if (mounted) {
      setState(() {
        _students = List<Map<String, dynamic>>.from(res);
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    Color cardColor = widget.isDark ? const Color(0xFF1E1E1E) : Colors.white;
    Color textColor = widget.isDark ? Colors.white : const Color(0xFF1A1A2E);

    return Container(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: widget.isDark
            ? const Color(0xFF121212)
            : const Color(0xFFF8FAFC),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 20),
          Container(
            width: 40,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            "${widget.schoolClass['name']} Roster",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
          const SizedBox(height: 20),

          Flexible(
            child: _isLoading
                ? Padding(
                    padding: const EdgeInsets.all(40),
                    child: TridetaLoader(color: widget.primaryColor),
                  )
                : _students.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(40),
                    child: Text(
                      "No students found in this class.",
                      style: TextStyle(color: Colors.grey.shade500),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 10,
                    ),
                    itemCount: _students.length,
                    itemBuilder: (ctx, i) {
                      final s = _students[i];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: widget.isDark
                                ? Colors.white10
                                : Colors.grey.shade200,
                            width: 1.5,
                          ),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 8,
                          ),
                          leading: CircleAvatar(
                            backgroundColor: widget.primaryColor.withValues(
                              alpha: 0.1,
                            ),
                            child: Text(
                              s['first_name'][0].toUpperCase(),
                              style: TextStyle(
                                color: widget.primaryColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          title: Text(
                            "${s['first_name']} ${s['last_name']}",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: textColor,
                            ),
                          ),
                          subtitle: Text(
                            s['admission_no'] ?? 'NO ID',
                            style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 12,
                            ),
                          ),
                          trailing: Icon(
                            Icons.arrow_forward_ios_rounded,
                            color: widget.primaryColor,
                            size: 16,
                          ),
                          onTap: () => widget.onStudentSelected(s),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
