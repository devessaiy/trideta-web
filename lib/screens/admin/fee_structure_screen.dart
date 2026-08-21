import 'dart:convert';
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

  // Stores the complete class data mapped to the Global Calendar
  List<Map<String, dynamic>> _schoolClassesData = [];

  // 🚨 ENGINE SWAP: State variables for Fees (No Streams)
  List<Map<String, dynamic>> _fees = [];
  bool _isLoading = true;
  bool _hasError = false;
  String _userRole = 'bursar';

  // Anti-Clutter Dashboard Filters
  String _filterSession = "2025/2026";
  String _filterTerm = "1st Term";

  @override
  void initState() {
    super.initState();
    _loadSchoolConfiguration();
  }

  List<String> _generateDynamicSessions() {
    int currentYear = DateTime.now().year;
    List<String> sessions = [];
    for (int y = 2023; y <= currentYear + 10; y++) {
      sessions.add("$y/${y + 1}");
    }
    if (!sessions.contains(_filterSession) && _filterSession.isNotEmpty) {
      sessions.add(_filterSession);
      sessions.sort();
    }
    return sessions;
  }

  Future<void> _loadSchoolConfiguration() async {
    if (mounted) setState(() => _isLoading = true);
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
        }

        final classesData = await _supabase
            .from('classes')
            .select('id, name')
            .eq('school_id', _schoolId!)
            .order('list_order', ascending: true);

        if (mounted) {
          setState(() {
            _schoolClassesData = List<Map<String, dynamic>>.from(classesData)
                .map((c) {
                  return {
                    'id': c['id'].toString(),
                    'name': c['name'].toString(),
                    'current_session': globalSession,
                    'current_term': globalTerm,
                  };
                })
                .toList();
          });
        }

        await _fetchFees(); // 🚨 Fetch the fees using the new standard fetch call
      }
    } catch (e) {
      if (mounted)
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
    }
  }

  // 🚨 STABLE FETCH ENGINE FOR FEES
  Future<void> _fetchFees() async {
    if (_schoolId == null) return;
    try {
      final query = _supabase
          .from('fee_structures')
          .select()
          .eq('school_id', _schoolId!)
          .eq('academic_session', _filterSession);

      // Apply term filter unless it is 'All Terms'
      final rawFees = _filterTerm == "All Terms"
          ? await query
          : await query.eq('academic_term', _filterTerm);

      if (mounted) {
        setState(() {
          _fees = List<Map<String, dynamic>>.from(rawFees);
          _isLoading = false;
          _hasError = false;
        });
      }
    } catch (e) {
      debugPrint("Fees Fetch Error: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  Future<void> _handleRefresh() async {
    await _loadSchoolConfiguration();
  }

  // ===========================================================================
  // 🚨 SMART DELETION & WALLET REFUND ENGINE (UNTOUCHED)
  // ===========================================================================
  Future<void> _deleteFee(String id, String feeName) async {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;

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

      await _supabase.from('transactions').delete().eq('fee_id', id);
      await _supabase.from('fee_structures').delete().eq('id', id);

      if (mounted) {
        showSuccessDialog(
          "Fee Removed",
          action == 2
              ? "'$feeName' has been deleted and payments were safely credited to the students' wallets."
              : "'$feeName' has been force-deleted without refunds.",
        );
        _fetchFees(); // Refresh after delete
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
    Color textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    Color primaryColor = Theme.of(context).primaryColor;

    bool isAdmin = _userRole == 'admin';

    Widget mainContent = RefreshIndicator(
      onRefresh: _handleRefresh,
      color: primaryColor,
      child: _isLoading && _fees.isEmpty
          ? Center(child: TridetaLoader(color: primaryColor))
          : _hasError && _fees.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.5,
                  child: const Center(child: Text("Connection error.")),
                ),
              ],
            )
          : _fees.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.4,
                  child: _buildEmptyState(isDark),
                ),
              ],
            )
          : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(
                vertical: 8,
                horizontal: 0,
              ), // Removed horizontal padding for edge-to-edge
              itemCount: _fees.length,
              itemBuilder: (context, index) => _CollapsibleFeeRuleTile(
                rule: _fees[index],
                textColor: textColor,
                isDark: isDark,
                primaryColor: primaryColor,
                isAdmin: isAdmin,
                onEdit: (rule) => _showAddFeeModal(primaryColor, rule),
                onDelete: (id, name) => _deleteFee(id, name),
              ),
            ),
    );

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(
          isAdmin ? "Fee Structure" : "View Fee Structure",
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
          ? FloatingActionButton(
              backgroundColor: primaryColor,
              elevation: 4,
              onPressed: () => _showAddFeeModal(primaryColor, null),
              child: const Icon(
                Icons.add_rounded,
                color: Colors.white,
                size: 28,
              ),
            )
          : null,
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
          _fetchFees(); // Refresh list after saving
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
            "No fee rules found.",
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

// 🚨 UI FIX: Rebuilt rule tile as a Stateful Collapsible Component
class _CollapsibleFeeRuleTile extends StatefulWidget {
  final Map<String, dynamic> rule;
  final Color textColor;
  final bool isDark;
  final Color primaryColor;
  final bool isAdmin;
  final Function(Map<String, dynamic>) onEdit;
  final Function(String, String) onDelete;

  const _CollapsibleFeeRuleTile({
    required this.rule,
    required this.textColor,
    required this.isDark,
    required this.primaryColor,
    required this.isAdmin,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<_CollapsibleFeeRuleTile> createState() =>
      _CollapsibleFeeRuleTileState();
}

class _CollapsibleFeeRuleTileState extends State<_CollapsibleFeeRuleTile> {
  bool _isExpanded = false;

  Widget _buildMiniChip(String label, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    String displaySession =
        widget.rule['academic_session'] ?? 'Unknown Session';
    String displayTerm = widget.rule['academic_term'] ?? 'All Terms';

    List<dynamic> parsedClasses = [];
    List<dynamic> parsedCategories = [];

    try {
      parsedClasses = widget.rule['applicable_classes'] is String
          ? jsonDecode(widget.rule['applicable_classes'])
          : (widget.rule['applicable_classes'] ?? []);

      parsedCategories = widget.rule['applicable_categories'] is String
          ? jsonDecode(widget.rule['applicable_categories'])
          : (widget.rule['applicable_categories'] ?? []);
    } catch (e) {
      // Fallback
    }

    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              setState(() => _isExpanded = !_isExpanded);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: widget.primaryColor.withValues(
                      alpha: 0.12,
                    ),
                    child: Icon(
                      Icons.account_balance_wallet_rounded,
                      color: widget.primaryColor,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                widget.rule['fee_name'] ?? 'Fee Item',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                  color: widget.textColor,
                                  letterSpacing: -0.5,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              "₦${widget.rule['amount']}",
                              style: TextStyle(
                                color: Colors.green.shade600,
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Text(
                              "$displaySession • $displayTerm",
                              style: TextStyle(
                                color: widget.isDark
                                    ? Colors.white54
                                    : Colors.grey.shade600,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            Icon(
                              _isExpanded
                                  ? Icons.keyboard_arrow_up_rounded
                                  : Icons.keyboard_arrow_down_rounded,
                              color: Colors.grey.shade400,
                            ),
                          ],
                        ),
                        AnimatedCrossFade(
                          duration: const Duration(milliseconds: 300),
                          crossFadeState: _isExpanded
                              ? CrossFadeState.showSecond
                              : CrossFadeState.showFirst,
                          firstChild: const SizedBox(
                            width: double.infinity,
                            height: 0,
                          ),
                          secondChild: Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                ...parsedClasses.map(
                                  (c) => _buildMiniChip(
                                    c.toString(),
                                    widget.primaryColor,
                                    widget.isDark,
                                  ),
                                ),
                                ...parsedCategories.map(
                                  (c) => _buildMiniChip(
                                    c.toString(),
                                    Colors.orange,
                                    widget.isDark,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.isAdmin) ...[
                    const SizedBox(width: 8),
                    PopupMenuButton<String>(
                      icon: Icon(
                        Icons.more_vert_rounded,
                        color: Colors.grey.shade400,
                      ),
                      onSelected: (val) {
                        if (val == 'edit') {
                          widget.onEdit(widget.rule);
                        } else if (val == 'delete') {
                          widget.onDelete(
                            widget.rule['id'].toString(),
                            widget.rule['fee_name'] ?? 'Fee',
                          );
                        }
                      },
                      itemBuilder: (ctx) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(Icons.edit_rounded, size: 18),
                              SizedBox(width: 10),
                              Text("Edit"),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(
                                Icons.delete_outline_rounded,
                                size: 18,
                                color: Colors.red,
                              ),
                              SizedBox(width: 10),
                              Text(
                                "Delete",
                                style: TextStyle(color: Colors.red),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 88, right: 24),
          child: Divider(
            height: 1,
            color: widget.isDark ? Colors.white10 : Colors.grey.shade200,
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// 🚨 ADD/EDIT FEE FORM (UNTOUCHED)
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

      try {
        var rawClasses = widget.initialData!['applicable_classes'];
        List<dynamic> initialClasses = rawClasses is String
            ? jsonDecode(rawClasses)
            : (rawClasses ?? []);
        _selectedClasses = initialClasses.map((e) => e.toString()).toList();

        var rawCats = widget.initialData!['applicable_categories'];
        List<dynamic> initialCats = rawCats is String
            ? jsonDecode(rawCats)
            : (rawCats ?? []);
        _selectedCategories = initialCats.map((e) => e.toString()).toList();
      } catch (e) {
        // Fallback
      }
    } else {
      if (widget.schoolClassesData.isNotEmpty) {
        _selectedSession = widget.schoolClassesData.first['current_session'];
        _selectedTerm = widget.schoolClassesData.first['current_term'];
      }
    }
  }

  List<String> _generateDynamicSessions() {
    int currentYear = DateTime.now().year;
    List<String> sessions = [];
    for (int y = 2023; y <= currentYear + 10; y++) {
      sessions.add("$y/${y + 1}");
    }
    if (!sessions.contains(_selectedSession) && _selectedSession.isNotEmpty) {
      sessions.add(_selectedSession);
      sessions.sort();
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

      String rawAmount = _amountController.text
          .replaceAll(',', '')
          .replaceAll(' ', '');
      double? parsedAmount = double.tryParse(rawAmount);

      if (parsedAmount == null) {
        setState(() => _isSaving = false);
        showAuthErrorDialog(
          "Please enter a valid number for the amount (e.g. 50000).",
        );
        return;
      }

      List<String> applicableClassIds = [];

      for (String cName in _selectedClasses) {
        for (var cData in widget.schoolClassesData) {
          if (cData['name'] == cName && cData['id'] != null) {
            applicableClassIds.add(cData['id'].toString());
            break;
          }
        }
      }

      final payload = {
        'school_id': widget.schoolId,
        'fee_name': feeName,
        'amount': parsedAmount,
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
      showAuthErrorDialog("Failed to save fee: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color modalColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    Color pColor = widget.primaryColor;

    bool isEdit = widget.initialData != null;

    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        left: 24,
        right: 24,
        top: 20,
      ),
      decoration: BoxDecoration(
        color: modalColor,
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
                    dropdownColor: modalColor,
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
                    dropdownColor: modalColor,
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
            _buildFieldLabel("Target Students", pColor),

            _buildSelectionWrap(
              widget.schoolClassesData
                  .map((c) => c['name'].toString())
                  .toList(),
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
                onPressed: _isSaving ? null : _saveFeeRule,
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
              : Colors.grey.shade100,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide.none,
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
      labelStyle: TextStyle(color: Colors.grey.shade500, fontSize: 14),
      prefixIcon: Icon(icon, color: pColor, size: 20),
      filled: true,
      fillColor: isDark
          ? Colors.white.withValues(alpha: 0.05)
          : Colors.grey.shade100,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: pColor.withValues(alpha: 0.5), width: 2),
      ),
    );
  }
}
