import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:trideta_v2/widgets/trideta_loader.dart';

class SchoolMasterDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> school;

  const SchoolMasterDetailsScreen({super.key, required this.school});

  @override
  State<SchoolMasterDetailsScreen> createState() => _SchoolMasterDetailsScreenState();
}

class _SchoolMasterDetailsScreenState extends State<SchoolMasterDetailsScreen> {
  final _supabase = Supabase.instance.client;
  final currencyFormat = NumberFormat.currency(symbol: '₦', decimalDigits: 0);

  bool _isLoading = true;
  bool _isActionInProgress = false;

  late Map<String, dynamic> _school;
  int _studentCount = 0;
  int _staffCount = 0;
  List<Map<String, dynamic>> _paymentHistory = [];
  List<Map<String, dynamic>> _auditLog = [];
  Map<String, Map<String, dynamic>> _tierInfo = {};
  List<int> _weeklyUsage = [0, 0, 0, 0, 0, 0, 0];

  @override
  void initState() {
    super.initState();
    _school = Map<String, dynamic>.from(widget.school);
    _fetchAll();
  }

  Future<void> _fetchAll() async {
    setState(() => _isLoading = true);
    try {
      final String sId = _school['id'].toString();

      final freshSchool = await _supabase.from('schools').select().eq('id', sId).single();

      final stdData = await _supabase.from('students').select('id').eq('school_id', sId);
      final staffData = await _supabase
          .from('profiles')
          .select('id')
          .eq('school_id', sId)
          .inFilter('role', ['teacher', 'bursar']);

      final payData = await _supabase
          .from('school_subscription_payments')
          .select()
          .eq('school_id', sId)
          .order('created_at', ascending: false);

      final auditData = await _supabase
          .from('subscription_audit_log')
          .select()
          .eq('school_id', sId)
          .order('created_at', ascending: false)
          .limit(50);

      final auditRows = List<Map<String, dynamic>>.from(auditData);
      final adminIds = auditRows.map((a) => a['admin_id']).whereType<String>().toSet().toList();
      Map<String, String> adminNames = {};
      if (adminIds.isNotEmpty) {
        final adminsData = await _supabase.from('profiles').select('id, full_name').inFilter('id', adminIds);
        for (var a in adminsData) {
          adminNames[a['id'].toString()] = a['full_name'] ?? 'Admin';
        }
      }
      final auditWithNames = auditRows.map((a) {
        final adminId = a['admin_id']?.toString();
        return {...a, '_admin_name': adminId == null ? 'System (Automated)' : (adminNames[adminId] ?? 'Admin')};
      }).toList();

      final tiersData = await _supabase.from('subscription_tiers').select();
      final tierMap = <String, Map<String, dynamic>>{
        for (var t in tiersData) t['tier'].toString(): Map<String, dynamic>.from(t),
      };

      final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7)).toIso8601String();
      final logsData = await _supabase
          .from('activity_logs')
          .select('created_at')
          .eq('school_id', sId)
          .gte('created_at', sevenDaysAgo);

      List<int> dailyCounts = [0, 0, 0, 0, 0, 0, 0];
      for (var row in logsData) {
        DateTime date = DateTime.parse(row['created_at']).toLocal();
        int dayIndex = (date.weekday - 1) % 7;
        dailyCounts[dayIndex]++;
      }

      if (mounted) {
        setState(() {
          _school = Map<String, dynamic>.from(freshSchool);
          _studentCount = stdData.length;
          _staffCount = staffData.length;
          _paymentHistory = List<Map<String, dynamic>>.from(payData);
          _auditLog = auditWithNames;
          _tierInfo = tierMap;
          _weeklyUsage = dailyCounts;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("School Details Fetch Error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── STATUS ACTIONS ──────────────────────────────────────────────

  Future<void> _confirmAndSetStatus(String newStatus, {required bool destructive}) async {
    final reasonController = TextEditingController();
    final label = {'active': 'Reactivate', 'paused_payment': 'Pause', 'terminated': 'Terminate'}[newStatus] ?? newStatus;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text("$label ${_school['name']}?"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (destructive)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  "This will immediately block the school from using protected modules. Their data is preserved.",
                  style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(labelText: "Reason (optional)", border: OutlineInputBorder()),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: destructive ? Colors.red : Theme.of(context).primaryColor),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(label),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isActionInProgress = true);
    try {
      await _supabase.rpc('set_school_status', params: {
        'p_school_id': _school['id'].toString(),
        'p_new_status': newStatus,
        'p_reason': reasonController.text.trim().isEmpty ? null : reasonController.text.trim(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("School status updated to ${newStatus.toUpperCase()}"), backgroundColor: Colors.green),
        );
      }
      await _fetchAll();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isActionInProgress = false);
    }
  }

  Future<void> _confirmAndSetFreeGranted(bool newValue) async {
    final reasonController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(newValue ? "Grant Free Access?" : "Revoke Free Access?"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              newValue
                  ? "This school will use the app without payment, regardless of tier or expiry, until you revoke it."
                  : "This school will go back to needing an active paid subscription based on its tier and expiry date.",
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(labelText: "Reason (optional)", border: OutlineInputBorder()),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Confirm")),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isActionInProgress = true);
    try {
      await _supabase.rpc('set_free_granted', params: {
        'p_school_id': _school['id'].toString(),
        'p_is_free_granted': newValue,
        'p_reason': reasonController.text.trim().isEmpty ? null : reasonController.text.trim(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(newValue ? "Free access granted" : "Free access revoked"), backgroundColor: Colors.green),
        );
      }
      await _fetchAll();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed: $e"), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isActionInProgress = false);
    }
  }

  // ── PAYMENT SHEET ───────────────────────────────────────────────

  void _showPaymentBottomSheet(Color primaryColor, bool isDark) {
    Color sheetColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    Color textColor = isDark ? Colors.white : Colors.black87;

    final amountController = TextEditingController();
    final referenceController = TextEditingController();
    final notesController = TextEditingController();
    String selectedCycle = 'termly';
    String selectedTier = 'tier_2';
    String selectedMethod = 'bank_transfer';
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) {
          return Container(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              left: 24,
              right: 24,
              top: 20,
            ),
            decoration: BoxDecoration(color: sheetColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(30))),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 5,
                      decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text("Record Payment", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: textColor)),
                  const SizedBox(height: 8),
                  Text(
                    "Logs the transaction, activates the school, and updates the subscription expiry date.",
                    style: TextStyle(fontSize: 13, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600, height: 1.4),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: amountController,
                    keyboardType: TextInputType.number,
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: primaryColor),
                    decoration: InputDecoration(
                      labelText: "Amount Received",
                      prefixText: "₦ ",
                      prefixStyle: TextStyle(color: primaryColor, fontWeight: FontWeight.bold, fontSize: 20),
                      filled: true,
                      fillColor: primaryColor.withValues(alpha: 0.05),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: selectedCycle,
                          dropdownColor: sheetColor,
                          decoration: _sheetFieldDecoration("Cycle", isDark),
                          items: const [
                            DropdownMenuItem(value: 'termly', child: Text("Termly")),
                            DropdownMenuItem(value: 'monthly', child: Text("Monthly")),
                            DropdownMenuItem(value: 'yearly', child: Text("Yearly")),
                          ],
                          onChanged: (val) => setSheetState(() => selectedCycle = val!),
                        ),
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: selectedTier,
                          dropdownColor: sheetColor,
                          decoration: _sheetFieldDecoration("Tier", isDark),
                          items: const [
                            DropdownMenuItem(value: 'tier_2', child: Text("Tier 2")),
                            DropdownMenuItem(value: 'tier_3', child: Text("Tier 3")),
                            DropdownMenuItem(value: 'tier_4', child: Text("Tier 4")),
                          ],
                          onChanged: (val) => setSheetState(() => selectedTier = val!),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 15),
                  DropdownButtonFormField<String>(
                    initialValue: selectedMethod,
                    dropdownColor: sheetColor,
                    decoration: _sheetFieldDecoration("Payment Method", isDark),
                    items: const [
                      DropdownMenuItem(value: 'bank_transfer', child: Text("Bank Transfer")),
                      DropdownMenuItem(value: 'cash', child: Text("Cash")),
                      DropdownMenuItem(value: 'pos', child: Text("POS")),
                      DropdownMenuItem(value: 'cheque', child: Text("Cheque")),
                      DropdownMenuItem(value: 'other', child: Text("Other")),
                    ],
                    onChanged: (val) => setSheetState(() => selectedMethod = val!),
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: referenceController,
                    decoration: _sheetFieldDecoration("Reference / Receipt No. (optional)", isDark),
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: notesController,
                    decoration: _sheetFieldDecoration("Notes (optional)", isDark),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 35),
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: primaryColor,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      ),
                      onPressed: isSaving
                          ? null
                          : () async {
                              final rawAmt = amountController.text.replaceAll(',', '').replaceAll(' ', '');
                              final amt = double.tryParse(rawAmt);
                              if (amt == null || amt <= 0) return;

                              setSheetState(() => isSaving = true);
                              try {
                                final sId = _school['id'].toString();
                                final now = DateTime.now();
                                final periodEnd = selectedCycle == 'yearly'
                                    ? now.add(const Duration(days: 365))
                                    : selectedCycle == 'monthly'
                                        ? DateTime(now.year, now.month + 1, now.day)
                                        : now.add(const Duration(days: 90));

                                // One atomic server-side call: records the payment,
                                // activates the school, sets the new expiry date,
                                // and writes the audit log entry.
                                await _supabase.rpc('record_manual_payment', params: {
                                  'p_school_id': sId,
                                  'p_amount': amt,
                                  'p_tier': selectedTier,
                                  'p_payment_cycle': selectedCycle,
                                  'p_period_start': now.toIso8601String().split('T')[0],
                                  'p_period_end': periodEnd.toIso8601String().split('T')[0],
                                  'p_payment_method': selectedMethod,
                                  'p_reference': referenceController.text.trim().isEmpty ? null : referenceController.text.trim(),
                                  'p_notes': notesController.text.trim().isEmpty ? null : notesController.text.trim(),
                                });

                                if (context.mounted) {
                                  Navigator.pop(ctx);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text("Payment securely recorded & school activated!"),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                  _fetchAll();
                                }
                              } catch (e) {
                                setSheetState(() => isSaving = false);
                                debugPrint(e.toString());
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(SnackBar(content: Text("Failed: $e"), backgroundColor: Colors.red));
                                }
                              }
                            },
                      icon: isSaving ? const SizedBox.shrink() : const Icon(Icons.check_circle_rounded),
                      label: isSaving
                          ? const TridetaLoader(color: Colors.white)
                          : const Text("AUTHORIZE PAYMENT", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  InputDecoration _sheetFieldDecoration(String label, bool isDark) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade100,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
    );
  }

  // ── BUILD ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC);
    final Color cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final Color textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final Color primaryColor = Theme.of(context).primaryColor;

    final String status = _school['subscription_status']?.toString() ?? 'active';
    final bool isActive = status == 'active';
    final bool isPaused = status == 'paused_payment';
    final bool isTerminated = status == 'terminated';
    final bool isFreeGranted = _school['is_free_granted'] == true;
    final String tier = (_school['subscription_tier'] ?? 'tier_1').toString();
    final tierMeta = _tierInfo[tier];

    Color statusColor = isActive ? Colors.green : (isPaused ? Colors.orange : Colors.red);
    String displayStatus = isActive ? 'ACTIVE' : (isPaused ? 'PAUSED (OWING)' : 'TERMINATED');

    String? expiryText;
    if (!isFreeGranted && tier != 'tier_1' && _school['subscription_expiry_date'] != null) {
      final expiry = DateTime.tryParse(_school['subscription_expiry_date']);
      if (expiry != null) {
        final daysLeft = expiry.difference(DateTime.now()).inDays;
        expiryText = daysLeft < 0
            ? "Expired ${-daysLeft} day${-daysLeft == 1 ? '' : 's'} ago"
            : daysLeft == 0
                ? "Expires today"
                : "$daysLeft day${daysLeft == 1 ? '' : 's'} remaining";
      }
    }

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text("Intelligence Hub", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: bgColor,
        foregroundColor: textColor,
        elevation: 0,
        centerTitle: true,
      ),
      body: _isLoading
          ? Center(child: TridetaLoader(color: primaryColor))
          : AbsorbPointer(
              absorbing: _isActionInProgress,
              child: Stack(
                children: [
                  SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ─── HEADER ───
                        Container(
                          width: double.infinity,
                          color: cardColor,
                          padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 24),
                          child: Column(
                            children: [
                              CircleAvatar(
                                radius: 45,
                                backgroundColor: primaryColor.withValues(alpha: 0.1),
                                backgroundImage: _school['logo_url'] != null ? NetworkImage(_school['logo_url']) : null,
                                child: _school['logo_url'] == null
                                    ? Icon(Icons.domain_rounded, size: 40, color: primaryColor)
                                    : null,
                              ),
                              const SizedBox(height: 16),
                              Text(_school['name'] ?? 'Unnamed School',
                                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: textColor)),
                              const SizedBox(height: 4),
                              Text(_school['acronym'] ?? '', style: TextStyle(color: Colors.grey.shade500)),
                            ],
                          ),
                        ),

                        // ─── SUBSCRIPTION STATUS CARD ───
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: cardColor,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: statusColor.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(displayStatus,
                                          style: TextStyle(color: statusColor, fontWeight: FontWeight.w900, fontSize: 12)),
                                    ),
                                    if (isFreeGranted)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        decoration: BoxDecoration(
                                            color: Colors.teal.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                                        child: const Text("FREE/GRANTED",
                                            style: TextStyle(color: Colors.teal, fontWeight: FontWeight.w900, fontSize: 12)),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  tierMeta != null
                                      ? "${tierMeta['label']} (${tier.toUpperCase()}) • ${currencyFormat.format(tierMeta['price_per_term'] ?? 0)}/term"
                                      : tier.toUpperCase(),
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: textColor),
                                ),
                                if (expiryText != null) ...[
                                  const SizedBox(height: 4),
                                  Text(expiryText,
                                      style: TextStyle(
                                        color: expiryText.contains('Expired') ? Colors.red : Colors.grey.shade500,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      )),
                                ],
                                const Divider(height: 28),

                                // Free/Granted toggle
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text("Free / Granted Access",
                                        style: TextStyle(fontWeight: FontWeight.w600, color: textColor, fontSize: 13)),
                                    Switch(
                                      value: isFreeGranted,
                                      activeThumbColor: Colors.teal,
                                      onChanged: (v) => _confirmAndSetFreeGranted(v),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),

                                // Status action buttons
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: [
                                    if (!isActive)
                                      _statusButton("Reactivate", Colors.green, Icons.check_circle_outline_rounded,
                                          () => _confirmAndSetStatus('active', destructive: false)),
                                    if (isActive)
                                      _statusButton("Pause", Colors.orange, Icons.pause_circle_outline_rounded,
                                          () => _confirmAndSetStatus('paused_payment', destructive: false)),
                                    if (!isTerminated)
                                      _statusButton("Terminate", Colors.red, Icons.block_rounded,
                                          () => _confirmAndSetStatus('terminated', destructive: true)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),

                        // ─── USAGE STATS ───
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Row(
                            children: [
                              Expanded(
                                  child: _buildMetricCard("Students", _studentCount.toString(), Icons.groups_rounded,
                                      Colors.blue, cardColor, textColor)),
                              const SizedBox(width: 16),
                              Expanded(
                                  child: _buildMetricCard("Active Staff", _staffCount.toString(), Icons.badge_rounded,
                                      Colors.purple, cardColor, textColor)),
                            ],
                          ),
                        ),

                        // ─── USAGE GRAPH ───
                        const SizedBox(height: 24),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: cardColor,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade200),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.insights_rounded, color: Colors.orange, size: 20),
                                    const SizedBox(width: 8),
                                    Text("WEEKLY ACTIVITY",
                                        style: TextStyle(
                                            color: Colors.grey.shade500, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.0)),
                                  ],
                                ),
                                const SizedBox(height: 24),
                                SizedBox(
                                  height: 100,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: List.generate(7, (index) {
                                      int maxUsage = _weeklyUsage.reduce((curr, next) => curr > next ? curr : next);
                                      if (maxUsage == 0) maxUsage = 1;
                                      double heightFactor = (_weeklyUsage[index] / maxUsage).clamp(0.1, 1.0);
                                      return Column(
                                        mainAxisAlignment: MainAxisAlignment.end,
                                        children: [
                                          Container(
                                            width: 18,
                                            height: 80 * heightFactor,
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(6),
                                              gradient: LinearGradient(
                                                colors: [primaryColor, primaryColor.withValues(alpha: 0.4)],
                                                begin: Alignment.topCenter,
                                                end: Alignment.bottomCenter,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(["M", "T", "W", "T", "F", "S", "S"][index],
                                              style: TextStyle(fontSize: 10, color: Colors.grey.shade500, fontWeight: FontWeight.bold)),
                                        ],
                                      );
                                    }),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // ─── PAYMENT HISTORY ───
                        const SizedBox(height: 30),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Text("FINANCIAL LEDGER",
                              style: TextStyle(color: Colors.grey.shade500, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.0)),
                        ),
                        const SizedBox(height: 10),
                        if (_paymentHistory.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(24),
                            child: Center(child: Text("No payment records found.", style: TextStyle(color: Colors.grey.shade500))),
                          )
                        else
                          Container(
                            color: cardColor,
                            child: ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _paymentHistory.length,
                              itemBuilder: (context, index) {
                                final payment = _paymentHistory[index];
                                DateTime date = DateTime.parse(payment['created_at']).toLocal();
                                final isPending = payment['status'] == 'pending';
                                final isFailed = payment['status'] == 'failed';
                                final provider = (payment['provider'] ?? 'manual').toString();

                                return Column(
                                  children: [
                                    ListTile(
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                                      leading: Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: (isFailed ? Colors.red : (isPending ? Colors.orange : Colors.green))
                                              .withValues(alpha: 0.1),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          isFailed ? Icons.close_rounded : (isPending ? Icons.hourglass_top_rounded : Icons.arrow_downward_rounded),
                                          color: isFailed ? Colors.red : (isPending ? Colors.orange : Colors.green),
                                          size: 20,
                                        ),
                                      ),
                                      title: Text(currencyFormat.format(payment['amount_paid'] ?? 0),
                                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: textColor)),
                                      subtitle: Text(
                                        "${(payment['tier_paid_for'] ?? '').toString().toUpperCase()} • ${payment['payment_cycle']} • ${provider.toUpperCase()}",
                                        style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontWeight: FontWeight.w600),
                                      ),
                                      trailing: Text(DateFormat('MMM dd, yyyy').format(date),
                                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade400)),
                                    ),
                                    if (index != _paymentHistory.length - 1)
                                      Padding(
                                        padding: const EdgeInsets.only(left: 80, right: 24),
                                        child: Divider(height: 1, color: isDark ? Colors.white10 : Colors.grey.shade200),
                                      ),
                                  ],
                                );
                              },
                            ),
                          ),

                        // ─── AUDIT / STATUS HISTORY ───
                        const SizedBox(height: 30),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Text("STATUS & AUDIT HISTORY",
                              style: TextStyle(color: Colors.grey.shade500, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.0)),
                        ),
                        const SizedBox(height: 10),
                        if (_auditLog.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(24),
                            child: Center(child: Text("No audit history yet.", style: TextStyle(color: Colors.grey.shade500))),
                          )
                        else
                          Container(
                            color: cardColor,
                            child: ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _auditLog.length,
                              itemBuilder: (context, index) {
                                final entry = _auditLog[index];
                                DateTime date = DateTime.parse(entry['created_at']).toLocal();
                                return Column(
                                  children: [
                                    ListTile(
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                                      leading: Icon(_iconForAction(entry['action']), color: Colors.grey.shade500, size: 20),
                                      title: Text(_formatAction(entry['action']),
                                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: textColor)),
                                      subtitle: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          if (entry['previous_value'] != null || entry['new_value'] != null)
                                            Text(
                                              "${entry['previous_value'] ?? '—'} → ${entry['new_value'] ?? '—'}",
                                              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                                            ),
                                          if (entry['reason'] != null && entry['reason'].toString().isNotEmpty)
                                            Text('"${entry['reason']}"',
                                                style: TextStyle(fontSize: 11, color: Colors.grey.shade400, fontStyle: FontStyle.italic)),
                                          Text("by ${entry['_admin_name']} • ${DateFormat('MMM dd, yyyy • hh:mm a').format(date)}",
                                              style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
                                        ],
                                      ),
                                      isThreeLine: true,
                                    ),
                                    if (index != _auditLog.length - 1)
                                      Padding(
                                        padding: const EdgeInsets.only(left: 60, right: 24),
                                        child: Divider(height: 1, color: isDark ? Colors.white10 : Colors.grey.shade200),
                                      ),
                                  ],
                                );
                              },
                            ),
                          ),

                        const SizedBox(height: 100),
                      ],
                    ),
                  ),
                  if (_isActionInProgress)
                    Container(
                      color: Colors.black.withValues(alpha: 0.2),
                      child: Center(child: TridetaLoader(color: primaryColor)),
                    ),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: primaryColor,
        elevation: 4,
        onPressed: () => _showPaymentBottomSheet(primaryColor, isDark),
        icon: const Icon(Icons.add_card_rounded, color: Colors.white),
        label: const Text("RECORD PAYMENT",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1)),
      ),
    );
  }

  Widget _statusButton(String label, Color color, IconData icon, VoidCallback onPressed) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withValues(alpha: 0.5)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
    );
  }

  IconData _iconForAction(String? action) {
    switch (action) {
      case 'status_change':
        return Icons.sync_alt_rounded;
      case 'manual_payment':
        return Icons.payments_rounded;
      case 'paystack_payment_verified':
        return Icons.verified_rounded;
      case 'free_grant':
        return Icons.card_giftcard_rounded;
      case 'free_revoke':
        return Icons.remove_circle_outline_rounded;
      case 'auto_pause_cap_exceeded':
        return Icons.groups_rounded;
      case 'auto_pause_expired':
        return Icons.timer_off_rounded;
      default:
        return Icons.history_rounded;
    }
  }

  String _formatAction(String? action) {
    switch (action) {
      case 'status_change':
        return 'Status Changed';
      case 'manual_payment':
        return 'Manual Payment Recorded';
      case 'paystack_payment_verified':
        return 'Paystack Payment Verified';
      case 'free_grant':
        return 'Free Access Granted';
      case 'free_revoke':
        return 'Free Access Revoked';
      case 'auto_pause_cap_exceeded':
        return 'Auto-Paused: Student Cap Exceeded';
      case 'auto_pause_expired':
        return 'Auto-Paused: Subscription Expired';
      default:
        return (action ?? 'Unknown Action').replaceAll('_', ' ').toUpperCase();
    }
  }

  Widget _buildMetricCard(String title, String count, IconData icon, Color color, Color cardColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 16),
          Text(count, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: textColor, letterSpacing: -0.5)),
          const SizedBox(height: 4),
          Text(title, style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
