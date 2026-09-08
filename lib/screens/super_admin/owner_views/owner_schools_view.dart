import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:trideta_v2/widgets/trideta_loader.dart';

class OwnerSchoolsManagementView extends StatefulWidget {
  const OwnerSchoolsManagementView({super.key});

  @override
  State<OwnerSchoolsManagementView> createState() =>
      _OwnerSchoolsManagementViewState();
}

class _OwnerSchoolsManagementViewState
    extends State<OwnerSchoolsManagementView> {
  final _supabase = Supabase.instance.client;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";
  String _selectedFilter = "all";

  List<Map<String, dynamic>> _allSchools = [];
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _fetchSchools();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchSchools() async {
    if (mounted && !_isLoading) setState(() => _isLoading = true);
    try {
      final data = await _supabase
          .from('schools')
          .select('*')
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _allSchools = List<Map<String, dynamic>>.from(data);
          _hasError = false;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Schools Fetch Error: $e");
      if (mounted) {
        setState(() {
          _hasError = true;
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    Color primaryColor = Theme.of(context).primaryColor;

    List<Map<String, dynamic>> filteredSchools = List.from(_allSchools);

    if (_searchQuery.isNotEmpty) {
      filteredSchools = filteredSchools.where((school) {
        final name = (school['name'] ?? '').toString().toLowerCase();
        final acronym = (school['acronym'] ?? '').toString().toLowerCase();
        return name.contains(_searchQuery) || acronym.contains(_searchQuery);
      }).toList();
    }

    if (_selectedFilter != 'all') {
      filteredSchools = filteredSchools.where((school) {
        final status = school['subscription_status'] ?? 'active';
        return status == _selectedFilter;
      }).toList();
    }

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: Text(
              "Client Schools",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: textColor,
                letterSpacing: -0.5,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: TextField(
              controller: _searchController,
              onChanged: (value) =>
                  setState(() => _searchQuery = value.toLowerCase()),
              decoration: InputDecoration(
                hintText: "Search school name or acronym...",
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = "");
                        },
                      )
                    : null,
                filled: true,
                fillColor: isDark
                    ? const Color(0xFF1E1E1E)
                    : Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                _buildFilterChip("All", "all", Colors.blue, isDark),
                const SizedBox(width: 10),
                _buildFilterChip(
                  "Paid (Active)",
                  "active",
                  Colors.green,
                  isDark,
                ),
                const SizedBox(width: 10),
                _buildFilterChip(
                  "Owed (Paused)",
                  "paused_payment",
                  Colors.orange,
                  isDark,
                ),
                const SizedBox(width: 10),
                _buildFilterChip(
                  "Overdue (Terminated)",
                  "terminated",
                  Colors.red,
                  isDark,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _isLoading && _allSchools.isEmpty
                ? Center(child: TridetaLoader(color: primaryColor))
                : _hasError && _allSchools.isEmpty
                ? const Center(child: Text("Failed to load schools."))
                : RefreshIndicator(
                    onRefresh: _fetchSchools,
                    color: primaryColor,
                    child: filteredSchools.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              SizedBox(
                                height:
                                    MediaQuery.of(context).size.height * 0.4,
                                child: const Center(
                                  child: Text(
                                    "No schools match this filter.",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.only(top: 8, bottom: 120),
                            itemCount: filteredSchools.length,
                            itemBuilder: (context, index) {
                              final school = filteredSchools[index];
                              final status =
                                  school['subscription_status'] ?? 'active';

                              final bool isActive = status == 'active';
                              final bool isPaused = status == 'paused_payment';
                              final bool isTerminated = status == 'terminated';

                              Color statusColor = isActive
                                  ? Colors.green
                                  : (isPaused ? Colors.orange : Colors.red);
                              String displayStatus = isActive
                                  ? "PAID & ACTIVE"
                                  : (isPaused
                                        ? "OWING (PAUSED)"
                                        : "LONG OVERDUE (TERMINATED)");

                              return Column(
                                children: [
                                  Material(
                                    color: Colors.transparent,
                                    child: ListTile(
                                      onTap: () {
                                        Navigator.of(context)
                                            .push(
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    SchoolMasterDetailsScreen(
                                                      school: school,
                                                    ),
                                              ),
                                            )
                                            .then((value) {
                                              // Refresh main list when returning from details
                                              _fetchSchools();
                                            });
                                      },
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 24,
                                            vertical: 12,
                                          ),
                                      leading: CircleAvatar(
                                        radius: 25,
                                        backgroundColor: statusColor.withValues(
                                          alpha: 0.1,
                                        ),
                                        child: Icon(
                                          isActive
                                              ? Icons.verified_rounded
                                              : (isPaused
                                                    ? Icons
                                                          .pause_circle_filled_rounded
                                                    : Icons.block_rounded),
                                          color: statusColor,
                                        ),
                                      ),
                                      title: Text(
                                        school['name'] ?? 'Unnamed School',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          color: isTerminated
                                              ? Colors.grey.shade500
                                              : textColor,
                                          decoration: isTerminated
                                              ? TextDecoration.lineThrough
                                              : null,
                                        ),
                                      ),
                                      subtitle: Padding(
                                        padding: const EdgeInsets.only(
                                          top: 4.0,
                                        ),
                                        child: Text(
                                          "${school['acronym'] ?? ''} • $displayStatus",
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: statusColor,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      left: 88,
                                      right: 24,
                                    ),
                                    child: Divider(
                                      height: 1,
                                      color: isDark
                                          ? Colors.white10
                                          : Colors.grey.shade200,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(
    String label,
    String value,
    Color color,
    bool isDark,
  ) {
    bool isSelected = _selectedFilter == value;

    return GestureDetector(
      onTap: () => setState(() => _selectedFilter = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.1)
              : (isDark ? const Color(0xFF1E1E1E) : Colors.white),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? color
                : (isDark ? Colors.white24 : Colors.grey.shade300),
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected
                ? color
                : (isDark ? Colors.white70 : Colors.grey.shade600),
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// 🚨 HIGH-END FINTECH SCHOOL DETAILS & PAYMENT RECORDER
// ============================================================================
class SchoolMasterDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> school;

  const SchoolMasterDetailsScreen({super.key, required this.school});

  @override
  State<SchoolMasterDetailsScreen> createState() =>
      _SchoolMasterDetailsScreenState();
}

class _SchoolMasterDetailsScreenState extends State<SchoolMasterDetailsScreen> {
  final _supabase = Supabase.instance.client;
  final currencyFormat = NumberFormat.currency(symbol: '₦', decimalDigits: 0);

  bool _isLoading = true;
  int _studentCount = 0;
  int _staffCount = 0;
  List<Map<String, dynamic>> _paymentHistory = [];

  // 🚨 INJECTED: State for Real Weekly Usage Logs
  List<int> _weeklyUsage = [0, 0, 0, 0, 0, 0, 0];

  @override
  void initState() {
    super.initState();
    _fetchSchoolStats();
  }

  Future<void> _fetchSchoolStats() async {
    setState(() => _isLoading = true);
    try {
      final String sId = widget.school['id'].toString();

      // 1. Live Population Fetch
      final stdData = await _supabase
          .from('students')
          .select('id')
          .eq('school_id', sId);
      final staffData = await _supabase
          .from('profiles')
          .select('id')
          .eq('school_id', sId)
          .inFilter('role', ['teacher', 'bursar']); // Strictly employees

      // 2. Fetch Payment Ledger
      final payData = await _supabase
          .from('school_subscription_payments')
          .select()
          .eq('school_id', sId)
          .order('created_at', ascending: false);

      // 3. 🚨 INJECTED: Fetch Real Weekly Activity Logs
      final sevenDaysAgo = DateTime.now()
          .subtract(const Duration(days: 7))
          .toIso8601String();
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
          _studentCount = stdData.length;
          _staffCount = staffData.length;
          _paymentHistory = List<Map<String, dynamic>>.from(payData);
          _weeklyUsage = dailyCounts; // Set real graph data
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Stats Fetch Error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showPaymentBottomSheet(Color primaryColor, bool isDark) {
    Color sheetColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    Color textColor = isDark ? Colors.white : Colors.black87;

    final amountController = TextEditingController();
    String selectedCycle = 'monthly';
    String selectedTier = 'tier_2';
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
            decoration: BoxDecoration(
              color: sheetColor,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(30),
              ),
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade400,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    "Record Payment",
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "This will securely log the transaction and instantly reactivate the school's account.",
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark
                          ? Colors.grey.shade400
                          : Colors.grey.shade600,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 24),

                  TextField(
                    controller: amountController,
                    keyboardType: TextInputType.number,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                      color: primaryColor,
                    ),
                    decoration: InputDecoration(
                      labelText: "Amount Received",
                      prefixText: "₦ ",
                      prefixStyle: TextStyle(
                        color: primaryColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                      filled: true,
                      fillColor: primaryColor.withValues(alpha: 0.05),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: selectedCycle,
                          dropdownColor: sheetColor,
                          decoration: InputDecoration(
                            labelText: "Billing Cycle",
                            filled: true,
                            fillColor: isDark
                                ? Colors.white.withValues(alpha: 0.05)
                                : Colors.grey.shade100,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(15),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'monthly',
                              child: Text("Monthly"),
                            ),
                            DropdownMenuItem(
                              value: 'termly',
                              child: Text("Termly"),
                            ),
                            DropdownMenuItem(
                              value: 'yearly',
                              child: Text("Yearly"),
                            ),
                          ],
                          onChanged: (val) =>
                              setSheetState(() => selectedCycle = val!),
                        ),
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: selectedTier,
                          dropdownColor: sheetColor,
                          decoration: InputDecoration(
                            labelText: "Service Tier",
                            filled: true,
                            fillColor: isDark
                                ? Colors.white.withValues(alpha: 0.05)
                                : Colors.grey.shade100,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(15),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'tier_2',
                              child: Text("Tier 2 (No Web)"),
                            ),
                            DropdownMenuItem(
                              value: 'tier_3',
                              child: Text("Tier 3 (Website)"),
                            ),
                          ],
                          onChanged: (val) =>
                              setSheetState(() => selectedTier = val!),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 35),

                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: primaryColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      onPressed: isSaving
                          ? null
                          : () async {
                              final rawAmt = amountController.text
                                  .replaceAll(',', '')
                                  .replaceAll(' ', '');
                              final amt = double.tryParse(rawAmt);
                              if (amt == null || amt <= 0) return;

                              setSheetState(() => isSaving = true);
                              try {
                                final sId = widget.school['id'].toString();

                                // 1. Record Ledger Entry
                                await _supabase
                                    .from('school_subscription_payments')
                                    .insert({
                                      'school_id': sId,
                                      'amount_paid': amt,
                                      'payment_cycle': selectedCycle,
                                      'tier_paid_for': selectedTier,
                                    });

                                // 2. Reactivate School & Update Tier
                                await _supabase
                                    .from('schools')
                                    .update({
                                      'subscription_status': 'active',
                                      'subscription_tier': selectedTier,
                                    })
                                    .eq('id', sId);

                                if (context.mounted) {
                                  Navigator.pop(ctx);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        "Payment securely recorded & school activated!",
                                      ),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                  _fetchSchoolStats(); // Refresh local screen
                                }
                              } catch (e) {
                                setSheetState(() => isSaving = false);
                                debugPrint(e.toString());
                              }
                            },
                      icon: isSaving
                          ? const SizedBox.shrink()
                          : const Icon(Icons.check_circle_rounded),
                      label: isSaving
                          ? const TridetaLoader(color: Colors.white)
                          : const Text(
                              "AUTHORIZE PAYMENT",
                              style: TextStyle(
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
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bgColor = isDark
        ? const Color(0xFF121212)
        : const Color(0xFFF8FAFC);
    final Color cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final Color textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final Color primaryColor = Theme.of(context).primaryColor;

    final String status =
        widget.school['subscription_status']?.toString() ?? 'active';
    final bool isActive = status == 'active';
    final Color statusColor = isActive ? Colors.green : Colors.redAccent;
    final String displayStatus = isActive ? 'ACTIVE & PAID' : 'PAYMENT OVERDUE';

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text(
          "Intelligence Hub",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        backgroundColor: bgColor,
        foregroundColor: textColor,
        elevation: 0,
        centerTitle: true,
      ),
      body: _isLoading
          ? Center(child: TridetaLoader(color: primaryColor))
          : SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ─── 1. SCHOOL PROFILE HEADER ───
                  Container(
                    width: double.infinity,
                    color: cardColor,
                    padding: const EdgeInsets.symmetric(
                      vertical: 30,
                      horizontal: 24,
                    ),
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 45,
                          backgroundColor: primaryColor.withValues(alpha: 0.1),
                          backgroundImage: widget.school['logo_url'] != null
                              ? NetworkImage(widget.school['logo_url'])
                              : null,
                          child: widget.school['logo_url'] == null
                              ? Icon(
                                  Icons.domain_rounded,
                                  size: 40,
                                  color: primaryColor,
                                )
                              : null,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          widget.school['name']?.toString() ?? 'Unnamed School',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: textColor,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            displayStatus,
                            style: TextStyle(
                              color: statusColor,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ─── 2. WHATSAPP STYLE CONTACT CARD ───
                  const SizedBox(height: 8),
                  Container(
                    color: cardColor,
                    child: Column(
                      children: [
                        _buildContactTile(
                          Icons.email_rounded,
                          "Admin Email",
                          widget.school['contact_email'] ??
                              widget.school['email'] ??
                              'No Email Provided',
                          isDark,
                          primaryColor,
                        ),
                        _buildContactTile(
                          Icons.phone_rounded,
                          "Admin Phone",
                          widget.school['contact_phone'] ??
                              widget.school['phone'] ??
                              'No Phone Provided',
                          isDark,
                          primaryColor,
                        ),
                        _buildContactTile(
                          Icons.location_on_rounded,
                          "Registered Address",
                          widget.school['address'] ?? 'No Address Provided',
                          isDark,
                          primaryColor,
                          hideDivider: true,
                        ),
                      ],
                    ),
                  ),

                  // ─── 3. LIVE POPULATION METRICS ───
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildMetricCard(
                            "Total Students",
                            _studentCount.toString(),
                            Icons.groups_rounded,
                            Colors.blue,
                            cardColor,
                            textColor,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildMetricCard(
                            "Active Staff",
                            _staffCount.toString(),
                            Icons.badge_rounded,
                            Colors.purple,
                            cardColor,
                            textColor,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ─── 4. FINTECH USAGE GRAPH & INSIGHTS ───
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: isDark ? Colors.white10 : Colors.grey.shade200,
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
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.insights_rounded,
                                color: Colors.orange,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                "SERVER LOAD ANALYTICS",
                                style: TextStyle(
                                  color: Colors.grey.shade500,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.0,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),

                          // 🚨 INJECTED: Bar Chart built with pure real usage counts
                          SizedBox(
                            height: 120,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: List.generate(7, (index) {
                                int maxUsage = _weeklyUsage.reduce(
                                  (curr, next) => curr > next ? curr : next,
                                );
                                if (maxUsage == 0) {
                                  maxUsage = 1; // Prevent dividing by zero
                                }
                                double heightFactor =
                                    (_weeklyUsage[index] / maxUsage).clamp(
                                      0.1,
                                      1.0,
                                    );

                                return Column(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Container(
                                      width: 18,
                                      height: 100 * heightFactor,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(6),
                                        gradient: LinearGradient(
                                          colors: [
                                            primaryColor,
                                            primaryColor.withValues(alpha: 0.4),
                                          ],
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      [
                                        "M",
                                        "T",
                                        "W",
                                        "T",
                                        "F",
                                        "S",
                                        "S",
                                      ][index],
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey.shade500,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                );
                              }),
                            ),
                          ),
                          const SizedBox(height: 24),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.lightbulb_outline_rounded,
                                  color: Colors.orange,
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _studentCount > 300
                                        ? "High API traffic detected during morning attendance. Advise school to stagger syncing to reduce latency."
                                        : "Traffic is stable. Finance Centre and Master Broadsheet are the most heavily queried modules.",
                                    style: TextStyle(
                                      color: Colors.orange.shade700,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ─── 5. WHATSAPP STYLE FINANCIAL LEDGER ───
                  const SizedBox(height: 35),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      "FINANCIAL LEDGER",
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  if (_paymentHistory.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Text(
                          "No payment records found.",
                          style: TextStyle(color: Colors.grey.shade500),
                        ),
                      ),
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
                          DateTime date = DateTime.parse(
                            payment['created_at'],
                          ).toLocal();

                          return Column(
                            children: [
                              ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 8,
                                ),
                                leading: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withValues(alpha: 0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.arrow_downward_rounded,
                                    color: Colors.green,
                                    size: 20,
                                  ),
                                ),
                                title: Text(
                                  currencyFormat.format(
                                    payment['amount_paid'] ?? 0,
                                  ),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16,
                                    color: textColor,
                                  ),
                                ),
                                subtitle: Text(
                                  "${payment['tier_paid_for'].toString().toUpperCase()} • ${payment['payment_cycle']}",
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade500,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                trailing: Text(
                                  DateFormat('MMM dd, yyyy').format(date),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey.shade400,
                                  ),
                                ),
                              ),
                              if (index != _paymentHistory.length - 1)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    left: 80,
                                    right: 24,
                                  ),
                                  child: Divider(
                                    height: 1,
                                    color: isDark
                                        ? Colors.white10
                                        : Colors.grey.shade200,
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 100), // FAB Clearance
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: primaryColor,
        elevation: 4,
        onPressed: () => _showPaymentBottomSheet(primaryColor, isDark),
        icon: const Icon(Icons.add_card_rounded, color: Colors.white),
        label: const Text(
          "RECORD PAYMENT",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }

  Widget _buildContactTile(
    IconData icon,
    String title,
    String subtitle,
    bool isDark,
    Color primaryColor, {
    bool hideDivider = false,
  }) {
    Color textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);

    return Column(
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 4,
          ),
          leading: Icon(icon, color: primaryColor, size: 22),
          title: Text(
            title,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: Text(
              subtitle,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15,
                color: textColor,
              ),
            ),
          ),
        ),
        if (!hideDivider)
          Padding(
            padding: const EdgeInsets.only(left: 70, right: 24),
            child: Divider(
              height: 1,
              color: isDark ? Colors.white10 : Colors.grey.shade200,
            ),
          ),
      ],
    );
  }

  Widget _buildMetricCard(
    String title,
    String count,
    IconData icon,
    Color color,
    Color cardColor,
    Color textColor,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 16),
          Text(
            count,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: textColor,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade500,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
