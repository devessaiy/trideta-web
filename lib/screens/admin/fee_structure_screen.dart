import 'package:trideta_v2/utils/auth_error_handler.dart';
import 'package:trideta_v2/widgets/trideta_loader.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FeeStructureScreen extends StatefulWidget {
  const FeeStructureScreen({super.key});

  @override
  State<FeeStructureScreen> createState() => _FeeStructureScreenState();
}

class _FeeStructureScreenState extends State<FeeStructureScreen>
    with AuthErrorHandler {
  final _supabase = Supabase.instance.client;

  String? _schoolId;

  // 🚨 NEW: Stores the complete class data with their asynchronous calendars
  List<Map<String, dynamic>> _schoolClassesData = [];

  bool _isLoading = true;
  String _userRole = 'bursar';

  // Anti-Clutter Dashboard Filters
  String _filterSession = "2025/2026";
  String _filterTerm = "1st Term";

  @override
  void initState() {
    super.initState();
    _loadSchoolConfiguration();
  }

  // 🚨 INFINITE SESSION GENERATOR
  List<String> _generateDynamicSessions() {
    int currentYear = DateTime.now().year;
    List<String> sessions = [];
    for (int y = 2023; y <= currentYear + 2; y++) {
      sessions.add("$y/${y + 1}");
    }
    return sessions;
  }

  Future<void> _loadSchoolConfiguration() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final profile = await _supabase
          .from('profiles')
          .select('school_id, role')
          .eq('id', user.id)
          .single();

      _schoolId = profile['school_id'];
      _userRole = profile['role']?.toString().toLowerCase() ?? 'bursar';

      if (_schoolId != null) {
        // Fetch global fallback
        final schoolData = await _supabase
            .from('schools')
            .select('current_session, current_term')
            .eq('id', _schoolId!)
            .maybeSingle();

        String globalSession = "2025/2026";
        String globalTerm = "1st Term";

        if (schoolData != null) {
          globalSession = schoolData['current_session'] ?? "2025/2026";
          globalTerm = schoolData['current_term'] ?? "1st Term";

          _filterSession = globalSession;
          _filterTerm = globalTerm;

          final dynamicSessions = _generateDynamicSessions();
          if (!dynamicSessions.contains(_filterSession)) {
            _filterSession = dynamicSessions.last;
          }
        }

        // Fetch classes and their asynchronous overrides
        final classesData = await _supabase
            .from('classes')
            .select('id, name, override_session, override_term')
            .eq('school_id', _schoolId!)
            .order('list_order', ascending: true);

        if (mounted) {
          setState(() {
            _schoolClassesData = List<Map<String, dynamic>>.from(classesData)
                .map((c) {
                  return {
                    'id': c['id'].toString(),
                    'name': c['name'].toString(),
                    'current_session': c['override_session'] ?? globalSession,
                    'current_term': c['override_term'] ?? globalTerm,
                  };
                })
                .toList();

            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleRefresh() async {
    await _loadSchoolConfiguration();
  }

  // ===========================================================================
  // 🚨 SMART DELETION & REFUND ENGINE
  // ===========================================================================
  Future<void> _deleteFee(String id, String feeName) async {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    // 0 = Cancel, 1 = Force Delete, 2 = Refund & Delete
    int? action = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
            SizedBox(width: 10),
            Text(
              "Resolve & Delete Fee",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "You are about to delete '$feeName'. How would you like to handle students who have already paid this fee?",
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.black87,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),

            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.account_balance_wallet_rounded,
                  color: Colors.green,
                ),
              ),
              title: const Text(
                "Refund to Wallets",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: const Text(
                "Credit the paid amount to the students' perpetual wallets (clears debt or saves for future fees).",
                style: TextStyle(fontSize: 12),
              ),
              onTap: () => Navigator.pop(ctx, 2),
            ),
            const Divider(),

            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.delete_forever_rounded,
                  color: Colors.redAccent,
                ),
              ),
              title: const Text(
                "Force Delete (No Refund)",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: const Text(
                "Delete the fee and erase all linked payment records. No money is refunded.",
                style: TextStyle(fontSize: 12),
              ),
              onTap: () => Navigator.pop(ctx, 1),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 0),
            child: const Text(
              "CANCEL",
              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (action == null || action == 0) return;

    setState(() => _isLoading = true);

    try {
      if (action == 2) {
        // 🚨 REFUND LOGIC
        final txs = await _supabase
            .from('transactions')
            .select('student_id, amount')
            .eq('fee_id', id);

        if (txs.isNotEmpty) {
          Map<String, double> refunds = {};
          for (var tx in txs) {
            String sId = tx['student_id'].toString();
            double amt = (tx['amount'] ?? 0).toDouble();
            refunds[sId] = (refunds[sId] ?? 0) + amt;
          }

          for (String sId in refunds.keys) {
            final student = await _supabase
                .from('students')
                .select('wallet_balance')
                .eq('id', sId)
                .single();
            double currentBalance = (student['wallet_balance'] ?? 0).toDouble();
            double newBalance = currentBalance + refunds[sId]!;
            await _supabase
                .from('students')
                .update({'wallet_balance': newBalance})
                .eq('id', sId);
          }
        }
      }

      // Delete linked transactions to clear database constraints
      await _supabase.from('transactions').delete().eq('fee_id', id);
      await _supabase.from('fee_structures').delete().eq('id', id);

      if (mounted) {
        showSuccessDialog(
          "Fee Removed",
          action == 2
              ? "'$feeName' has been deleted and payments were safely credited to the students' wallets."
              : "'$feeName' has been force-deleted without refunds.",
        );
      }
    } catch (e) {
      if (mounted) {
        showAuthErrorDialog(
          "An error occurred while deleting the fee. Please try again.",
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC);
    Color cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    Color textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    Color primaryColor = Theme.of(context).primaryColor;

    // 🚨 RBAC ENFORCEMENT
    bool isAdmin = _userRole == 'admin';

    Widget mainContent = _isLoading
        ? Center(child: TridetaLoader(color: primaryColor))
        : RefreshIndicator(
            onRefresh: _handleRefresh,
            color: primaryColor,
            child: Column(
              children: [
                // Dashboard Filter Strip
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    color: cardColor,
                    border: Border(
                      bottom: BorderSide(
                        color: isDark ? Colors.white10 : Colors.grey.shade200,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _filterSession,
                          dropdownColor: cardColor,
                          decoration: InputDecoration(
                            labelText: "Session",
                            labelStyle: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade500,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          items: _generateDynamicSessions()
                              .map(
                                (e) => DropdownMenuItem(
                                  value: e,
                                  child: Text(
                                    e,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (val) =>
                              setState(() => _filterSession = val!),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _filterTerm,
                          dropdownColor: cardColor,
                          decoration: InputDecoration(
                            labelText: "Term",
                            labelStyle: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade500,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          items:
                              ["1st Term", "2nd Term", "3rd Term", "All Terms"]
                                  .map(
                                    (e) => DropdownMenuItem(
                                      value: e,
                                      child: Text(
                                        e,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                          onChanged: (val) =>
                              setState(() => _filterTerm = val!),
                        ),
                      ),
                    ],
                  ),
                ),

                // Streamed List
                Expanded(
                  child: StreamBuilder<List<Map<String, dynamic>>>(
                    stream: _filterTerm == "All Terms"
                        ? _supabase
                              .from('fee_structures')
                              .stream(primaryKey: ['id'])
                              .eq('school_id', _schoolId!)
                              .eq('academic_session', _filterSession)
                        : _supabase
                              .from('fee_structures')
                              .stream(primaryKey: ['id'])
                              .eq('school_id', _schoolId!)
                              .eq('academic_session', _filterSession)
                              .eq('academic_term', _filterTerm),
                    builder: (context, snapshot) {
                      if (snapshot.hasError)
                        return const Center(child: Text("Connection error."));
                      if (!snapshot.hasData)
                        return Center(
                          child: TridetaLoader(color: primaryColor),
                        );

                      final fees = snapshot.data!;

                      if (fees.isEmpty) {
                        return ListView(
                          children: [
                            SizedBox(
                              height: MediaQuery.of(context).size.height * 0.2,
                            ),
                            _buildEmptyState(isDark),
                          ],
                        );
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 20,
                        ),
                        itemCount: fees.length,
                        itemBuilder: (context, index) => _buildFeeRuleCard(
                          fees[index],
                          cardColor,
                          textColor,
                          isDark,
                          primaryColor,
                          isAdmin,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(
          isAdmin ? "Manage Fee Structure" : "View Fee Structure",
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
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
      floatingActionButton: isAdmin
          ? FloatingActionButton.extended(
              backgroundColor: primaryColor,
              elevation: 4,
              onPressed: () => _showAddFeeModal(primaryColor, null),
              icon: const Icon(Icons.add_task_rounded, color: Colors.white),
              label: const Text(
                "ADD NEW RULE",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildFeeRuleCard(
    Map<String, dynamic> rule,
    Color cardColor,
    Color textColor,
    bool isDark,
    Color primaryColor,
    bool isAdmin,
  ) {
    String displaySession = rule['academic_session'] ?? 'Unknown Session';
    String displayTerm = rule['academic_term'] ?? 'All Terms';

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.account_balance_wallet_rounded,
                    color: primaryColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        rule['fee_name'] ?? 'Fee Item',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                          color: textColor,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.history_edu_rounded,
                            size: 14,
                            color: Colors.grey.shade500,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            "$displaySession • $displayTerm",
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.green.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Text(
                    "₦${rule['amount']}",
                    style: TextStyle(
                      color: Colors.green.shade700,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),

          Divider(
            height: 1,
            color: isDark ? Colors.white10 : Colors.grey.shade100,
          ),

          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "TARGET DEMOGRAPHIC",
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: Colors.grey.shade400,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ...(rule['applicable_classes'] as List? ?? []).map(
                            (c) => _buildMiniChip(
                              c.toString(),
                              primaryColor,
                              isDark,
                            ),
                          ),
                          ...(rule['applicable_categories'] as List? ?? []).map(
                            (c) => _buildMiniChip(
                              c.toString(),
                              Colors.orange,
                              isDark,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (isAdmin) ...[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildActionButton(
                        Icons.edit_rounded,
                        primaryColor,
                        () => _showAddFeeModal(primaryColor, rule),
                      ),
                      const SizedBox(width: 8),
                      _buildActionButton(
                        Icons.delete_outline_rounded,
                        Colors.redAccent,
                        () => _deleteFee(
                          rule['id'].toString(),
                          rule['fee_name'] ?? 'Fee',
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      "READ ONLY",
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 20, color: color),
      ),
    );
  }

  Widget _buildMiniChip(String label, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  void _showAddFeeModal(Color primaryColor, Map<String, dynamic>? initialData) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: 600),
      builder: (context) => AddFeeForm(
        schoolId: _schoolId!,
        schoolClassesData: _schoolClassesData,
        primaryColor: primaryColor,
        initialData: initialData,
        onSuccess: (name, isEdit) {
          showSuccessDialog(
            isEdit ? "Fee Updated" : "Fee Added",
            isEdit
                ? "'$name' rule has been updated successfully."
                : "'$name' rule has been added to the structure.",
          );
        },
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
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.grey.shade100,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.account_balance_rounded,
              size: 60,
              color: isDark ? Colors.white24 : Colors.grey[400],
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            "No fee rules found for this Term.",
            style: TextStyle(
              color: Colors.grey,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// 🚨 ADD/EDIT FEE FORM (WITH REVERSE LOCK UI)
// ============================================================================
class AddFeeForm extends StatefulWidget {
  final String schoolId;
  final List<Map<String, dynamic>> schoolClassesData;
  final Function(String, bool) onSuccess;
  final Color primaryColor;
  final Map<String, dynamic>? initialData;

  const AddFeeForm({
    super.key,
    required this.schoolId,
    required this.schoolClassesData,
    required this.onSuccess,
    required this.primaryColor,
    this.initialData,
  });

  @override
  State<AddFeeForm> createState() => _AddFeeFormState();
}

class _AddFeeFormState extends State<AddFeeForm> with AuthErrorHandler {
  final _supabase = Supabase.instance.client;
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();

  List<String> _selectedClasses = [];
  final List<String> _allCategories = [
    "Regular",
    "Transfer",
    "Scholarship",
    "Special",
    "Staff Child",
    "Orphan",
  ];
  List<String> _selectedCategories = [];

  String _selectedSession = "2025/2026";
  String _selectedTerm = "1st Term";
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialData != null) {
      _titleController.text = widget.initialData!['fee_name'] ?? '';
      _amountController.text = widget.initialData!['amount']?.toString() ?? '';
      _selectedSession = widget.initialData!['academic_session'] ?? '2025/2026';
      _selectedTerm = widget.initialData!['academic_term'] ?? '1st Term';

      final dynamicSessions = _generateDynamicSessions();
      if (!dynamicSessions.contains(_selectedSession)) {
        _selectedSession = dynamicSessions.last;
      }

      List<dynamic> initialClasses =
          widget.initialData!['applicable_classes'] ?? [];
      _selectedClasses = initialClasses.map((e) => e.toString()).toList();

      List<dynamic> initialCats =
          widget.initialData!['applicable_categories'] ?? [];
      _selectedCategories = initialCats.map((e) => e.toString()).toList();
    } else {
      // Set defaults based on the first class's fallback (global session) if available
      if (widget.schoolClassesData.isNotEmpty) {
        _selectedSession = widget.schoolClassesData.first['current_session'];
        _selectedTerm = widget.schoolClassesData.first['current_term'];
      }
    }
  }

  List<String> _generateDynamicSessions() {
    int currentYear = DateTime.now().year;
    List<String> sessions = [];
    for (int y = 2023; y <= currentYear + 2; y++) {
      sessions.add("$y/${y + 1}");
    }
    return sessions;
  }

  Future<void> _saveFeeRule() async {
    if (_titleController.text.isEmpty ||
        _amountController.text.isEmpty ||
        _selectedClasses.isEmpty) {
      showAuthErrorDialog(
        "Please fill all fields and select at least one class.",
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final feeName = _titleController.text;

      List<String> applicableClassIds = [];
      for (String cName in _selectedClasses) {
        final cData = widget.schoolClassesData.firstWhere(
          (c) => c['name'] == cName,
          orElse: () => {},
        );
        if (cData.isNotEmpty && cData['id'] != null) {
          applicableClassIds.add(cData['id']);
        }
      }

      final payload = {
        'school_id': widget.schoolId,
        'fee_name': feeName,
        'amount': double.parse(_amountController.text),
        'applicable_classes': _selectedClasses,
        'applicable_class_ids': applicableClassIds,
        'applicable_categories': _selectedCategories,
        'academic_session': _selectedSession,
        'academic_term': _selectedTerm,
        'class_level': _selectedClasses.join(', '),
      };

      if (widget.initialData != null) {
        await _supabase
            .from('fee_structures')
            .update(payload)
            .eq('id', widget.initialData!['id']);
      } else {
        await _supabase.from('fee_structures').insert(payload);
      }

      if (mounted) {
        Navigator.pop(context);
        widget.onSuccess(feeName, widget.initialData != null);
      }
    } catch (e) {
      setState(() => _isSaving = false);
      showAuthErrorDialog("Ensure the amount is a valid number.");
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    Color pColor = widget.primaryColor;

    bool isEdit = widget.initialData != null;

    // 🚨 REVERSE LOCK LOGIC: Filter classes strictly by the selected Calendar
    List<Map<String, dynamic>> visibleClasses = widget.schoolClassesData.where((
      c,
    ) {
      // Failsafe: Always show already-selected classes so Admin doesn't accidentally wipe them
      if (_selectedClasses.contains(c['name'])) return true;

      if (c['current_session'] != _selectedSession) return false;
      if (_selectedTerm != 'All Terms' && c['current_term'] != _selectedTerm)
        return false;

      return true;
    }).toList();

    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        left: 24,
        right: 24,
        top: 20,
      ),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              isEdit ? "Edit Fee Rule" : "Create Fee Rule",
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 30),

            _buildFieldLabel("Basic Information", pColor),

            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedSession,
                    dropdownColor: cardColor,
                    decoration: _inputStyle(
                      "Session",
                      Icons.history_edu_rounded,
                      isDark,
                      pColor,
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
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (val) => setState(() => _selectedSession = val!),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedTerm,
                    dropdownColor: cardColor,
                    decoration: _inputStyle(
                      "Term",
                      Icons.calendar_month_rounded,
                      isDark,
                      pColor,
                    ),
                    items: ["1st Term", "2nd Term", "3rd Term", "All Terms"]
                        .map(
                          (e) => DropdownMenuItem(
                            value: e,
                            child: Text(
                              e,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (val) => setState(() => _selectedTerm = val!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _titleController,
              decoration: _inputStyle(
                "Fee Title (e.g. Tuition)",
                Icons.title_rounded,
                isDark,
                pColor,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              decoration: _inputStyle(
                "Amount",
                Icons.payments_rounded,
                isDark,
                pColor,
              ).copyWith(prefixText: "₦ "),
            ),

            const SizedBox(height: 30),
            _buildFieldLabel(
              "Target Students (Filtered by Target Calendar)",
              pColor,
            ),

            if (visibleClasses.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  "No classes are currently operating in $_selectedSession - $_selectedTerm. Please change the calendar above to assign this fee.",
                  style: TextStyle(
                    color: Colors.redAccent.shade100,
                    fontStyle: FontStyle.italic,
                    fontSize: 12,
                  ),
                ),
              )
            else
              _buildSelectionWrap(
                visibleClasses.map((c) => c['name'].toString()).toList(),
                _selectedClasses,
                pColor,
                isDark,
              ),

            const SizedBox(height: 24),
            _buildFieldLabel("Category Filtering", pColor),
            _buildSelectionWrap(
              _allCategories,
              _selectedCategories,
              Colors.orange,
              isDark,
            ),

            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: pColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: (_isSaving || visibleClasses.isEmpty)
                    ? null
                    : _saveFeeRule,
                child: _isSaving
                    ? const TridetaLoader(color: Colors.white)
                    : Text(
                        isEdit ? "UPDATE RULE" : "AUTHORIZE RULE",
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFieldLabel(String text, Color pColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 4),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: pColor,
          fontSize: 11,
          letterSpacing: 1.1,
        ),
      ),
    );
  }

  Widget _buildSelectionWrap(
    List<String> items,
    List<String> selectedList,
    Color activeColor,
    bool isDark,
  ) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: items.map((item) {
        bool isSelected = selectedList.contains(item);
        return FilterChip(
          label: Text(
            item,
            style: TextStyle(
              color: isSelected ? activeColor : Colors.grey.shade500,
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
            ),
          ),
          selected: isSelected,
          showCheckmark: false,
          selectedColor: activeColor.withValues(alpha: 0.1),
          backgroundColor: isDark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.grey.shade50,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: isSelected
                  ? activeColor.withValues(alpha: 0.5)
                  : (isDark ? Colors.white10 : Colors.grey.shade300),
            ),
          ),
          onSelected: (val) => setState(
            () => val ? selectedList.add(item) : selectedList.remove(item),
          ),
        );
      }).toList(),
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
    );
  }
}
