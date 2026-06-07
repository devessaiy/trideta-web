import 'package:trideta_v2/utils/auth_error_handler.dart';
import 'package:trideta_v2/widgets/trideta_loader.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

// 🚨 IMPORT THE EXTRACTED MODULAR RECEIPT VIEW
import 'package:trideta_v2/screens/admin/admin_receipt_detail_view.dart';

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen>
    with SingleTickerProviderStateMixin, AuthErrorHandler {
  late TabController _tabController;
  final _supabase = Supabase.instance.client;

  String? _schoolId;
  String _currentSession = "";
  bool _isLoading = true;

  // Financial Health Variables
  double _collectionPercentage = 0.0;
  double _totalExpectedFees = 0.0;
  bool _isSendingDebtorAlert = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() => setState(() {}));
    _initData();
  }

  Future<void> _handleRefresh() async {
    await _initData();
    if (mounted) {
      showSuccessDialog("Sync Complete", "Data synchronized successfully!");
    }
  }

  // ===========================================================================
  // 🚨 LOGIC ENGINE: STRICTLY UNTOUCHED
  // ===========================================================================
  Future<void> _initData() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user != null) {
        final profile = await _supabase
            .from('profiles')
            .select('school_id')
            .eq('id', user.id)
            .single();
        _schoolId = profile['school_id'];
        final school = await _supabase
            .from('schools')
            .select('current_session')
            .eq('id', _schoolId!)
            .single();
        _currentSession = school['current_session'] ?? "";
        await _checkFinancialHealth();
      }
    } catch (e) {
      debugPrint("Init Error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _checkFinancialHealth() async {
    if (_schoolId == null || _currentSession.isEmpty) return;
    try {
      final feeData = await _supabase
          .from('fee_structures')
          .select('amount, applicable_classes, applicable_categories')
          .eq('school_id', _schoolId!)
          .eq('academic_session', _currentSession);
      final studentsData = await _supabase
          .from('students')
          .select('*')
          .eq('school_id', _schoolId!);
      double totalExpected = 0.0;

      for (var student in studentsData) {
        String sClass =
            (student['class_level'] ?? student['current_class'] ?? '')
                .toString();
        String sCategory = (student['category'] ?? '').toString();
        for (var fee in feeData) {
          if (_doesItApply(fee['applicable_classes'], sClass) &&
              _doesItApply(
                fee['applicable_categories'],
                sCategory,
                isCategory: true,
              )) {
            totalExpected += (fee['amount'] ?? 0).toDouble();
          }
        }
      }

      final transactions = await _supabase
          .from('transactions')
          .select('*')
          .eq('school_id', _schoolId!);
      double totalCollected = 0.0;

      for (var tx in transactions) {
        String txSession = (tx['academic_session'] ?? '').toString();
        if (txSession == _currentSession || txSession.isEmpty) {
          totalCollected += (tx['amount'] ?? 0).toDouble();
        }
      }

      if (mounted) {
        setState(() {
          _totalExpectedFees = totalExpected;
          if (totalExpected > 0) {
            _collectionPercentage = (totalCollected / totalExpected) * 100;
          } else {
            _collectionPercentage = 0.0;
          }
        });
      }
    } catch (e) {
      debugPrint("Health Check Error: $e");
    }
  }

  bool _doesItApply(
    dynamic columnData,
    String studentData, {
    bool isCategory = false,
  }) {
    String cleanStudentData = isCategory
        ? studentData.replaceAll(' ', '').toLowerCase()
        : _standardizeClass(studentData);
    if (isCategory && cleanStudentData.isEmpty) cleanStudentData = 'regular';
    if (cleanStudentData.isEmpty) return false;
    if (columnData == null) return true;
    String colStr = isCategory
        ? columnData.toString().replaceAll(' ', '').toLowerCase()
        : _standardizeClass(columnData.toString());
    return colStr.isEmpty ||
        colStr == 'all' ||
        colStr == '[]' ||
        colStr.contains(cleanStudentData);
  }

  String _standardizeClass(String val) {
    return val
        .replaceAll(' ', '')
        .toLowerCase()
        .replaceAll('one', '1')
        .replaceAll('two', '2')
        .replaceAll('three', '3')
        .replaceAll('four', '4')
        .replaceAll('five', '5')
        .replaceAll('six', '6');
  }

  Future<void> _deleteAlert(String alertId) async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          "Delete Alert?",
          style: TextStyle(
            color: Colors.redAccent,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: const Text("This action cannot be undone."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              "Delete",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _supabase.from('alerts').delete().eq('id', alertId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "Alert deleted successfully.",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        showAuthErrorDialog("Error deleting alert: $e");
      }
    }
  }

  void _showDebtorOptions() {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
            SizedBox(width: 10),
            Text(
              "Alert Debtors",
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
          ],
        ),
        content: Text(
          "How would you like to notify parents with outstanding balances for $_currentSession?",
          style: TextStyle(
            color: isDark ? Colors.white70 : Colors.black87,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _executeDebtorAlert(sendSms: false);
            },
            child: const Text(
              "Dashboard Only",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _executeDebtorAlert(sendSms: true);
            },
            icon: const Icon(Icons.sms_rounded, size: 18),
            label: const Text(
              "Dashboard + SMS",
              style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _executeDebtorAlert({required bool sendSms}) async {
    setState(() => _isSendingDebtorAlert = true);
    try {
      await _supabase.from('alerts').insert({
        'school_id': _schoolId,
        'title': 'FEE REMINDER: $_currentSession',
        'message':
            'Dear Parent, our records show an outstanding balance for the $_currentSession session. Kindly arrange for payment to avoid administrative interruptions.',
        'type': 'fee_urgent',
      });
      if (sendSms) await Future.delayed(const Duration(seconds: 2));
      if (mounted) {
        showSuccessDialog(
          "Alerts Sent",
          "Debtor alerts have been sent to the parent dashboards successfully!",
        );
      }
    } catch (e) {
      showAuthErrorDialog("Failed to send alert: ${e.toString()}");
    } finally {
      if (mounted) setState(() => _isSendingDebtorAlert = false);
    }
  }

  // 🚨 REDESIGNED CUSTOM ALERT MODAL
  void _showCreateAlertDialog() {
    String selectedAudience = 'parent_alert';
    final titleCtrl = TextEditingController();
    final msgCtrl = TextEditingController();
    bool isSubmitting = false;
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color primaryColor = Theme.of(context).primaryColor;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF121212) : Colors.white,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(30),
              ),
            ),
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
              left: 24,
              right: 24,
              top: 12,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
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
                const Text(
                  "Create Custom Alert",
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 24),

                DropdownButtonFormField<String>(
                  initialValue: selectedAudience,
                  decoration: InputDecoration(
                    labelText: "Target Audience",
                    labelStyle: TextStyle(color: Colors.grey.shade500),
                    prefixIcon: Icon(Icons.group_rounded, color: primaryColor),
                    filled: true,
                    fillColor: isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.grey.shade50,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'parent_alert',
                      child: Text(
                        "Parents Only",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'teacher_alert',
                      child: Text(
                        "Teachers Only",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'general',
                      child: Text(
                        "General (All Users)",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'school_website',
                      child: Text(
                        "School Website (Public)",
                        style: TextStyle(
                          color: Colors.teal,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                  onChanged: (val) =>
                      setModalState(() => selectedAudience = val!),
                ),
                const SizedBox(height: 16),

                TextField(
                  controller: titleCtrl,
                  decoration: InputDecoration(
                    labelText: "Alert Title",
                    labelStyle: TextStyle(color: Colors.grey.shade500),
                    filled: true,
                    fillColor: isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.grey.shade50,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                TextField(
                  controller: msgCtrl,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: "Message Body",
                    alignLabelWithHint: true,
                    labelStyle: TextStyle(color: Colors.grey.shade500),
                    filled: true,
                    fillColor: isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.grey.shade50,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 30),

                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: primaryColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    onPressed: isSubmitting
                        ? null
                        : () async {
                            if (titleCtrl.text.isEmpty ||
                                msgCtrl.text.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    "Title and message required.",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  backgroundColor: Colors.orange,
                                ),
                              );
                              return;
                            }
                            setModalState(() => isSubmitting = true);
                            try {
                              await _supabase.from('alerts').insert({
                                'school_id': _schoolId,
                                'title': titleCtrl.text.trim(),
                                'message': msgCtrl.text.trim(),
                                'type': selectedAudience,
                              });
                              if (mounted) {
                                Navigator.pop(ctx);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      "Alert posted successfully!",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              }
                            } catch (e) {
                              showAuthErrorDialog("Failed to post alert: $e");
                            } finally {
                              setModalState(() => isSubmitting = false);
                            }
                          },
                    icon: isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: TridetaLoader(color: Colors.white),
                          )
                        : const Icon(Icons.send_rounded, color: Colors.white),
                    label: Text(
                      isSubmitting ? "POSTING..." : "POST ALERT",
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 30),
              ],
            ),
          );
        },
      ),
    );
  }

  // ===========================================================================
  // 🚨 MODULAR UI COMPOSITION
  // ===========================================================================
  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC);
    Color primaryColor = Theme.of(context).primaryColor;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: bgColor,
        body: Center(child: TridetaLoader(color: primaryColor)),
      );
    }

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text(
          "Action Center",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: bgColor,
        foregroundColor: isDark ? Colors.white : Colors.black87,
        elevation: 0,
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.grey.shade200,
              borderRadius: BorderRadius.circular(16),
            ),
            child: TabBar(
              controller: _tabController,
              dividerColor: Colors.transparent,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                color: primaryColor,
                borderRadius: BorderRadius.circular(16),
              ),
              labelColor: Colors.white,
              unselectedLabelColor: isDark
                  ? Colors.white54
                  : Colors.grey.shade600,
              labelStyle: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
              tabs: const [
                Tab(text: "ALERTS", iconMargin: EdgeInsets.zero),
                Tab(text: "RECEIPTS", iconMargin: EdgeInsets.zero),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: _tabController.index == 0
          ? FloatingActionButton.extended(
              onPressed: _showCreateAlertDialog,
              backgroundColor: primaryColor,
              elevation: 4,
              icon: const Icon(Icons.add_alert_rounded, color: Colors.white),
              label: const Text(
                "New Alert",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            )
          : null,
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
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildAlertsTab(isDark, primaryColor),
                      _buildTransactionsTab(isDark, primaryColor),
                    ],
                  ),
                ),
              ),
            );
          } else {
            return TabBarView(
              controller: _tabController,
              children: [
                _buildAlertsTab(isDark, primaryColor),
                _buildTransactionsTab(isDark, primaryColor),
              ],
            );
          }
        },
      ),
    );
  }

  // 🚨 REDESIGNED PREMIUM HEALTH CARD
  Widget _buildHealthCard(bool isDark) {
    if (_totalExpectedFees == 0) {
      return Container(
        margin: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline_rounded, color: Colors.grey.shade600),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                "Awaiting financial data for $_currentSession.",
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      );
    }

    Color cardColor;
    Color textColor;
    IconData icon;
    String title;
    String subtitle;
    bool showButton = false;

    if (_collectionPercentage < 50.0) {
      cardColor = Colors.redAccent.withValues(alpha: 0.05);
      textColor = Colors.redAccent;
      icon = Icons.warning_amber_rounded;
      title = "CRITICAL REVENUE";
      subtitle =
          "Collection is only ${_collectionPercentage.toStringAsFixed(1)}%. Expected is 50% or more. High outstanding debt detected.";
      showButton = true;
    } else if (_collectionPercentage < 60.0) {
      cardColor = Colors.orange.withValues(alpha: 0.05);
      textColor = Colors.orange;
      icon = Icons.health_and_safety_outlined;
      title = "SYSTEM STABLE";
      subtitle =
          "Collection is at ${_collectionPercentage.toStringAsFixed(1)}%. Minimum operational threshold met.";
    } else if (_collectionPercentage < 70.0) {
      cardColor = Colors.teal.withValues(alpha: 0.05);
      textColor = Colors.teal;
      icon = Icons.trending_up_rounded;
      title = "HEALTHY REVENUE";
      subtitle =
          "Collection is at ${_collectionPercentage.toStringAsFixed(1)}%. Financial health is looking very good.";
    } else {
      cardColor = Colors.green.withValues(alpha: 0.05);
      textColor = Colors.green;
      icon = Icons.verified_user_rounded;
      title = "EXCELLENT REVENUE";
      subtitle =
          "Great job! Collection is at ${_collectionPercentage.toStringAsFixed(1)}%. The school's finances are highly stable.";
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: textColor.withValues(alpha: 0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: textColor.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Circular Progress Indicator
              SizedBox(
                width: 60,
                height: 60,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CircularProgressIndicator(
                      value: _collectionPercentage / 100,
                      strokeWidth: 6,
                      backgroundColor: textColor.withValues(alpha: 0.1),
                      valueColor: AlwaysStoppedAnimation<Color>(textColor),
                      strokeCap: StrokeCap.round,
                    ),
                    Center(child: Icon(icon, color: textColor, size: 24)),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: textColor,
                        fontSize: 16,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white70 : Colors.grey.shade600,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (showButton) ...[
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 45,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: textColor,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _isSendingDebtorAlert ? null : _showDebtorOptions,
                icon: _isSendingDebtorAlert
                    ? const SizedBox(
                        width: 15,
                        height: 15,
                        child: TridetaLoader(color: Colors.white),
                      )
                    : const Icon(Icons.notifications_active_rounded, size: 18),
                label: Text(
                  _isSendingDebtorAlert ? "PROCESSING..." : "ALERT ALL DEBTORS",
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAlertsTab(bool isDark, Color primaryColor) {
    return RefreshIndicator(
      onRefresh: _handleRefresh,
      color: primaryColor,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 100),
        children: [
          _buildHealthCard(isDark),
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: _supabase
                .from('alerts')
                .stream(primaryKey: ['id'])
                .eq('school_id', _schoolId!)
                .order('created_at', ascending: false),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData) {
                return Padding(
                  padding: const EdgeInsets.all(20),
                  child: Center(child: TridetaLoader(color: primaryColor)),
                );
              }
              final alerts = snapshot.data ?? [];
              if (alerts.isEmpty) {
                return SizedBox(
                  height: 250,
                  child: _buildEmptyState(
                    "No Custom Alerts",
                    "Manual notifications will appear here.",
                    Icons.campaign_rounded,
                    isDark,
                  ),
                );
              }

              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 24),
                itemCount: alerts.length,
                itemBuilder: (context, index) {
                  // 🚨 CALLS THE NEW COLLAPSIBLE CARD WIDGET
                  return _CollapsibleAlertCard(
                    alert: alerts[index],
                    primaryColor: primaryColor,
                    isDark: isDark,
                    onDelete: () => _deleteAlert(alerts[index]['id']),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionsTab(bool isDark, Color primaryColor) {
    return RefreshIndicator(
      onRefresh: _handleRefresh,
      color: primaryColor,
      child: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _supabase
            .from('transactions')
            .stream(primaryKey: ['id'])
            .eq('school_id', _schoolId!)
            .order('created_at', ascending: false)
            .limit(50),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return Center(child: TridetaLoader(color: primaryColor));
          }
          final txs = snapshot.data!;
          if (txs.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.5,
                  child: _buildEmptyState(
                    "No Receipts",
                    "Recent transactions appear here.",
                    Icons.receipt_long_rounded,
                    isDark,
                  ),
                ),
              ],
            );
          }

          return ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(24),
            itemCount: txs.length,
            itemBuilder: (context, index) {
              final tx = txs[index];
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
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
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AdminReceiptDetailView(tx: tx),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.receipt_long_rounded,
                              color: Colors.green,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  tx['student_name'] ?? 'Unknown',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  DateFormat('dd MMM, yyyy').format(
                                    DateTime.parse(tx['created_at']).toLocal(),
                                  ),
                                  style: TextStyle(
                                    color: Colors.grey.shade500,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            NumberFormat.currency(
                              symbol: '₦',
                              decimalDigits: 0,
                            ).format(tx['amount']),
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              color: Colors.green,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(String t, String s, IconData i, bool d) => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: d
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.grey.shade100,
            shape: BoxShape.circle,
          ),
          child: Icon(i, size: 40, color: Colors.grey.shade400),
        ),
        const SizedBox(height: 20),
        Text(
          t,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
        ),
        const SizedBox(height: 8),
        Text(
          s,
          style: TextStyle(
            color: Colors.grey.shade500,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    ),
  );
}

// ===========================================================================
// 🚨 LOCAL CUSTOM WIDGET: PREMIUM COLLAPSIBLE ALERT CARD
// ===========================================================================
class _CollapsibleAlertCard extends StatefulWidget {
  final Map<String, dynamic> alert;
  final Color primaryColor;
  final bool isDark;
  final VoidCallback onDelete;

  const _CollapsibleAlertCard({
    required this.alert,
    required this.primaryColor,
    required this.isDark,
    required this.onDelete,
  });

  @override
  State<_CollapsibleAlertCard> createState() => _CollapsibleAlertCardState();
}

class _CollapsibleAlertCardState extends State<_CollapsibleAlertCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    String type = widget.alert['type'] ?? '';
    IconData typeIcon = Icons.notifications_rounded;
    Color typeColor = widget.primaryColor;
    String badgeText = "General";

    if (type == 'parent_alert') {
      typeIcon = Icons.family_restroom_rounded;
      typeColor = Colors.blue;
      badgeText = "Parents";
    } else if (type == 'teacher_alert') {
      typeIcon = Icons.school_rounded;
      typeColor = Colors.purple;
      badgeText = "Teachers";
    } else if (type == 'fee_urgent') {
      typeIcon = Icons.warning_rounded;
      typeColor = Colors.redAccent;
      badgeText = "Debtors";
    } else if (type == 'school_website') {
      typeIcon = Icons.public_rounded;
      typeColor = Colors.teal;
      badgeText = "Website";
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: widget.isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: widget.isDark ? Colors.white10 : Colors.grey.shade200,
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
          borderRadius: BorderRadius.circular(20),
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: typeColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(typeIcon, size: 14, color: typeColor),
                          const SizedBox(width: 6),
                          Text(
                            badgeText,
                            style: TextStyle(
                              fontSize: 11,
                              color: typeColor,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Text(
                      widget.alert['created_at'] != null
                          ? DateFormat('MMM dd, hh:mm a').format(
                              DateTime.parse(
                                widget.alert['created_at'],
                              ).toLocal(),
                            )
                          : '',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: widget.onDelete,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.delete_outline_rounded,
                          color: Colors.redAccent,
                          size: 16,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        widget.alert['title'] ?? 'Notice',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(
                      _isExpanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: Colors.grey.shade400,
                    ),
                  ],
                ),
                // Smoothly animated expansion
                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 300),
                  crossFadeState: _isExpanded
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  firstChild: const SizedBox(width: double.infinity, height: 0),
                  secondChild: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      widget.alert['message'] ?? '',
                      style: TextStyle(
                        color: widget.isDark
                            ? Colors.white70
                            : Colors.grey.shade700,
                        height: 1.5,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
