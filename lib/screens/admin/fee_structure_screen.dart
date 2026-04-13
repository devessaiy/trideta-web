import 'package:trideta_v2/utils/auth_error_handler.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// 🚨 UPDATED ABSOLUTE IMPORT

class FeeStructureScreen extends StatefulWidget {
  const FeeStructureScreen({super.key});

  @override
  State<FeeStructureScreen> createState() => _FeeStructureScreenState();
}

class _FeeStructureScreenState extends State<FeeStructureScreen>
    with AuthErrorHandler {
  final _supabase = Supabase.instance.client;

  String? _schoolId;
  List<String> _schoolClasses = [];
  bool _isLoading = true;

  // 🚨 NEW: RBAC TRACKER
  String _userRole = 'bursar'; // Default to bursar (lowest privilege)

  @override
  void initState() {
    super.initState();
    _loadSchoolConfiguration();
  }

  // 🚨 FETCHING ROLE AND SCHOOL CONFIGURATION
  Future<void> _loadSchoolConfiguration() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      // Fetch School ID and Role
      final profile = await _supabase
          .from('profiles')
          .select('school_id, role')
          .eq('id', user.id)
          .single();

      _schoolId = profile['school_id'];
      _userRole = profile['role']?.toString().toLowerCase() ?? 'bursar';

      if (_schoolId != null) {
        final classesData = await _supabase
            .from('classes')
            .select('name')
            .eq('school_id', _schoolId!)
            .order('list_order', ascending: true);

        if (mounted) {
          setState(() {
            _schoolClasses = classesData
                .map((c) => c['name'].toString())
                .toList();
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- REFRESH LOGIC ---
  Future<void> _handleRefresh() async {
    await _loadSchoolConfiguration();
  }

  Future<void> _deleteFee(String id, String feeName) async {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    bool confirm =
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Row(
              children: [
                Icon(Icons.delete_sweep_rounded, color: Colors.red),
                SizedBox(width: 10),
                Text("Remove Fee?"),
              ],
            ),
            content: Text(
              "Are you sure you want to remove '$feeName'? This will stop billing new students for this item.",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text(
                  "CANCEL",
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(
                  "DELETE",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirm) return;

    try {
      await _supabase.from('fee_structures').delete().eq('id', id);
      if (mounted) {
        showSuccessDialog(
          "Fee Removed",
          "The fee rule '$feeName' has been deleted.",
        );
      }
    } catch (e) {
      showAuthErrorDialog(
        "Could not delete fee. It might be linked to existing transactions.",
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC);
    Color cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    Color textColor = isDark ? Colors.white : Colors.black87;

    Color primaryColor = Theme.of(context).primaryColor;

    // 🚨 CHECK IF USER IS ADMIN
    bool isAdmin = _userRole == 'admin';

    // 🚨 MAIN CONTENT EXTRACTED FOR LAYOUT BUILDER
    Widget mainContent = _isLoading
        ? Center(child: CircularProgressIndicator(color: primaryColor))
        : RefreshIndicator(
            onRefresh: _handleRefresh,
            color: primaryColor,
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _supabase
                  .from('fee_structures')
                  .stream(primaryKey: ['id'])
                  .eq('school_id', _schoolId!),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(child: Text("Connection error."));
                }
                if (!snapshot.hasData) {
                  return Center(
                    child: CircularProgressIndicator(color: primaryColor),
                  );
                }
                final fees = snapshot.data!;
                if (fees.isEmpty) {
                  return ListView(
                    children: [
                      SizedBox(
                        height: MediaQuery.of(context).size.height * 0.3,
                      ),
                      _buildEmptyState(isDark),
                    ],
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: fees.length,
                  itemBuilder: (context, index) => _buildFeeRuleCard(
                    fees[index],
                    cardColor,
                    textColor,
                    isDark,
                    primaryColor,
                    isAdmin, // 🚨 Pass Admin status down
                  ),
                );
              },
            ),
          );

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(
          isAdmin
              ? "Manage Fee Structure"
              : "View Fee Structure", // Dynamic Title
          style: const TextStyle(fontWeight: FontWeight.bold),
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
      // 🚨 ONLY ADMIN CAN ADD NEW FEES
      floatingActionButton: isAdmin
          ? FloatingActionButton.extended(
              backgroundColor: primaryColor,
              onPressed: () => _showAddFeeModal(primaryColor, null),
              icon: const Icon(Icons.add_task_rounded, color: Colors.white),
              label: const Text(
                "ADD NEW RULE",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          : null, // Hides button if Bursar
    );
  }

  Widget _buildFeeRuleCard(
    Map<String, dynamic> rule,
    Color cardColor,
    Color textColor,
    bool isDark,
    Color primaryColor,
    bool isAdmin, // 🚨 Receives Admin Status
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade100,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    rule['fee_name'] ?? 'Fee',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                      color: textColor,
                    ),
                  ),
                ),
                Text(
                  "₦${rule['amount']}",
                  style: TextStyle(
                    color: Colors.greenAccent.shade700,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  Icons.calendar_today_rounded,
                  size: 12,
                  color: Colors.grey[500],
                ),
                const SizedBox(width: 6),
                Text(
                  rule['academic_session'] ?? 'All Sessions',
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),

                // 🚨 ONLY ADMIN SEES EDIT/DELETE ICONS
                if (isAdmin) ...[
                  IconButton(
                    onPressed: () => _showAddFeeModal(primaryColor, rule),
                    icon: Icon(
                      Icons.edit_rounded,
                      color: Colors.blue.withOpacity(0.7),
                      size: 22,
                    ),
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.only(right: 15),
                  ),
                  IconButton(
                    onPressed: () => _deleteFee(
                      rule['id'].toString(),
                      rule['fee_name'] ?? 'Fee',
                    ),
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      color: Colors.red.withOpacity(0.7),
                      size: 22,
                    ),
                    constraints: const BoxConstraints(),
                    padding: EdgeInsets.zero,
                  ),
                ] else ...[
                  // 🚨 Visual indicator for Bursar that it's view-only
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: const Text(
                      "Read Only",
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const Divider(height: 25),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ...(rule['applicable_classes'] as List? ?? []).map(
                  (c) => _buildMiniChip(c.toString(), primaryColor, isDark),
                ),
                ...(rule['applicable_categories'] as List? ?? []).map(
                  (c) => _buildChip(c.toString(), Colors.orange, isDark),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniChip(String label, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withOpacity(0.2)),
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

  Widget _buildChip(String label, Color color, bool isDark) {
    return _buildMiniChip(label, color, isDark);
  }

  void _showAddFeeModal(Color primaryColor, Map<String, dynamic>? initialData) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(
        maxWidth: 600,
      ), // 🚨 WEB/DESKTOP WIDTH CONSTRAINT
      builder: (context) => AddFeeForm(
        schoolId: _schoolId!,
        availableClasses: _schoolClasses,
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
          Icon(
            Icons.account_balance_rounded,
            size: 80,
            color: isDark ? Colors.white10 : Colors.grey[200],
          ),
          const SizedBox(height: 15),
          const Text(
            "No fee rules defined yet.",
            style: TextStyle(color: Colors.grey, fontSize: 16),
          ),
        ],
      ),
    );
  }
}

// --- ADD/EDIT FEE FORM ---

class AddFeeForm extends StatefulWidget {
  final String schoolId;
  final List<String> availableClasses;
  final Function(String, bool) onSuccess;
  final Color primaryColor;
  final Map<String, dynamic>? initialData;

  const AddFeeForm({
    super.key,
    required this.schoolId,
    required this.availableClasses,
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
  final List<String> _allCategories = ["Regular", "Transfer", "Scholarship"];
  List<String> _selectedCategories = [];

  String _selectedSession = "2025/2026";
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialData != null) {
      _titleController.text = widget.initialData!['fee_name'] ?? '';
      _amountController.text = widget.initialData!['amount']?.toString() ?? '';
      _selectedSession = widget.initialData!['academic_session'] ?? '2025/2026';

      List<dynamic> initialClasses =
          widget.initialData!['applicable_classes'] ?? [];
      _selectedClasses = initialClasses.map((e) => e.toString()).toList();

      List<dynamic> initialCats =
          widget.initialData!['applicable_categories'] ?? [];
      _selectedCategories = initialCats.map((e) => e.toString()).toList();
    }
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
      final payload = {
        'school_id': widget.schoolId,
        'fee_name': feeName,
        'amount': double.parse(_amountController.text),
        'applicable_classes': _selectedClasses,
        'applicable_categories': _selectedCategories,
        'academic_session': _selectedSession,
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

    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        left: 20,
        right: 20,
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
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              isEdit ? "Edit Fee Rule" : "Create Fee Rule",
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 25),

            _buildFieldLabel("Basic Information", pColor),
            DropdownButtonFormField<String>(
              initialValue: _selectedSession,
              dropdownColor: cardColor,
              decoration: _inputStyle(
                "Academic Session",
                Icons.history_edu_rounded,
                isDark,
                pColor,
              ),
              items: [
                "2024/2025",
                "2025/2026",
                "2026/2027",
              ].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
              onChanged: (val) => setState(() => _selectedSession = val!),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: _titleController,
              decoration: _inputStyle(
                "Fee Title (e.g. Tuition)",
                Icons.title_rounded,
                isDark,
                pColor,
              ),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              decoration: _inputStyle(
                "Amount (₦)",
                Icons.payments_rounded,
                isDark,
                pColor,
              ),
            ),

            const SizedBox(height: 25),
            _buildFieldLabel("Target Students", pColor),
            _buildSelectionWrap(
              widget.availableClasses,
              _selectedClasses,
              pColor,
            ),

            const SizedBox(height: 20),
            _buildFieldLabel("Category Filtering", pColor),
            _buildSelectionWrap(
              _allCategories,
              _selectedCategories,
              Colors.orange,
            ),

            const SizedBox(height: 35),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: pColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                onPressed: _isSaving ? null : _saveFeeRule,
                child: _isSaving
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(
                        isEdit ? "UPDATE RULE" : "AUTHORIZE RULE",
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
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
      padding: const EdgeInsets.only(bottom: 8),
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
  ) {
    return Wrap(
      spacing: 8,
      runSpacing: 0,
      children: items.map((item) {
        bool isSelected = selectedList.contains(item);
        return FilterChip(
          label: Text(
            item,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.grey[600],
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          selected: isSelected,
          showCheckmark: false,
          selectedColor: activeColor,
          backgroundColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
              color: isSelected ? activeColor : Colors.grey.shade300,
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
      fillColor: isDark ? Colors.white.withOpacity(0.03) : Colors.grey[50],
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide.none,
      ),
    );
  }
}
