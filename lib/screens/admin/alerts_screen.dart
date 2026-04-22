import 'package:trideta_v2/utils/auth_error_handler.dart';
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
        title: const Text("Delete Alert?"),
        content: const Text("This action cannot be undone."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
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
                style: TextStyle(color: Colors.white),
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
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
            SizedBox(width: 10),
            Text(
              "Alert Debtors",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        content: Text(
          "How would you like to notify parents with outstanding balances for $_currentSession?",
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _executeDebtorAlert(sendSms: false);
            },
            child: const Text("Dashboard Only"),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _executeDebtorAlert(sendSms: true);
            },
            icon: const Icon(Icons.sms_rounded, size: 16),
            label: const Text("Dashboard + SMS"),
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

  // 🚨 UPDATED CUSTOM ALERT FORM
  void _showCreateAlertDialog() {
    String selectedAudience = 'parent_alert';
    final titleCtrl = TextEditingController();
    final msgCtrl = TextEditingController();
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
              left: 24,
              right: 24,
              top: 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Create Custom Alert",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),

                DropdownButtonFormField<String>(
                  initialValue: selectedAudience,
                  decoration: const InputDecoration(
                    labelText: "Target Audience",
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'parent_alert',
                      child: Text("Parents Only"),
                    ),
                    DropdownMenuItem(
                      value: 'teacher_alert',
                      child: Text("Teachers Only"),
                    ),
                    DropdownMenuItem(
                      value: 'general',
                      child: Text("General (All Users)"),
                    ),
                    // 🚨 ROUTED TO THE SCHOOL'S OWN WEBSITE
                    DropdownMenuItem(
                      value: 'school_website',
                      child: Text(
                        "School Website (Public)",
                        style: TextStyle(
                          color: Colors.teal,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                  onChanged: (val) =>
                      setModalState(() => selectedAudience = val!),
                ),
                const SizedBox(height: 15),

                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(
                    labelText: "Alert Title",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 15),

                TextField(
                  controller: msgCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: "Message Body",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: isSubmitting
                        ? null
                        : () async {
                            if (titleCtrl.text.isEmpty ||
                                msgCtrl.text.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text("Title and message required."),
                                ),
                              );
                              return;
                            }
                            setModalState(() => isSubmitting = true);
                            try {
                              // Safely inserts into the School's isolated alerts table
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
                                    content: Text("Alert posted successfully!"),
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
                    child: isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            "POST ALERT",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC);
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
          "Action Center",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: primaryColor,
        automaticallyImplyLeading: false,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold),
          tabs: const [
            Tab(text: "System Alerts", icon: Icon(Icons.campaign_rounded)),
            Tab(
              text: "Recent Receipts",
              icon: Icon(Icons.receipt_long_rounded),
            ),
          ],
        ),
      ),
      floatingActionButton: _tabController.index == 0
          ? FloatingActionButton.extended(
              onPressed: _showCreateAlertDialog,
              backgroundColor: primaryColor,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_alert_rounded),
              label: const Text(
                "New Alert",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            )
          : null,
      // 🚨 SHAPE-SHIFTER: LayoutBuilder
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth > 800) {
            // 💻 DESKTOP LAYOUT
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
            // 📱 MOBILE LAYOUT
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

  Widget _buildHealthCard(bool isDark) {
    if (_totalExpectedFees == 0) {
      return Container(
        margin: const EdgeInsets.all(20),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.grey.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Row(
          children: [
            Icon(Icons.info_outline, color: Colors.grey),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                "Awaiting financial data for the current session.",
                style: TextStyle(color: Colors.grey),
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
      cardColor = Colors.redAccent.withOpacity(0.1);
      textColor = Colors.redAccent;
      icon = Icons.warning_amber_rounded;
      title = "LOW REVENUE DETECTED";
      subtitle =
          "Collection for $_currentSession is only ${_collectionPercentage.toStringAsFixed(1)}%. Expected is 50% or more. High outstanding debt detected.";
      showButton = true;
    } else if (_collectionPercentage < 60.0) {
      cardColor = Colors.orange.withOpacity(0.1);
      textColor = Colors.orange;
      icon = Icons.health_and_safety_outlined;
      title = "SYSTEM STABLE";
      subtitle =
          "Collection for $_currentSession is at ${_collectionPercentage.toStringAsFixed(1)}%. Minimum operational threshold met.";
    } else if (_collectionPercentage < 70.0) {
      cardColor = Colors.teal.withOpacity(0.1);
      textColor = Colors.teal;
      icon = Icons.trending_up_rounded;
      title = "HEALTHY REVENUE";
      subtitle =
          "Collection for $_currentSession is at ${_collectionPercentage.toStringAsFixed(1)}%. Financial health is looking very good.";
    } else {
      cardColor = Colors.green.withOpacity(0.1);
      textColor = Colors.green;
      icon = Icons.verified_user_rounded;
      title = "EXCELLENT REVENUE";
      subtitle =
          "Great job! Collection for $_currentSession is at ${_collectionPercentage.toStringAsFixed(1)}%. The school's finances are highly stable.";
    }

    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: textColor.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: textColor),
              const SizedBox(width: 10),
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: textColor,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
          if (showButton) ...[
            const SizedBox(height: 15),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: textColor,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: _isSendingDebtorAlert ? null : _showDebtorOptions,
                icon: _isSendingDebtorAlert
                    ? const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.notifications_active, size: 18),
                label: Text(
                  _isSendingDebtorAlert ? "PROCESSING..." : "ALERT ALL DEBTORS",
                  style: const TextStyle(fontWeight: FontWeight.bold),
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
        padding: const EdgeInsets.only(bottom: 80), // Padding for FAB
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
                  child: Center(
                    child: CircularProgressIndicator(color: primaryColor),
                  ),
                );
              }

              final alerts = snapshot.data ?? [];
              if (alerts.isEmpty) {
                return SizedBox(
                  height: 250,
                  child: _buildEmptyState(
                    "No Custom Alerts",
                    "Manual alerts will appear here.",
                    Icons.campaign_rounded,
                    isDark,
                  ),
                );
              }

              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                itemCount: alerts.length,
                itemBuilder: (context, index) {
                  final alert = alerts[index];

                  // Visual indicator for Audience
                  String type = alert['type'] ?? '';
                  IconData typeIcon = Icons.notifications;
                  Color typeColor = primaryColor;
                  String badgeText = "General";

                  if (type == 'parent_alert') {
                    typeIcon = Icons.family_restroom;
                    typeColor = Colors.blue;
                    badgeText = "Parents";
                  } else if (type == 'teacher_alert') {
                    typeIcon = Icons.school;
                    typeColor = Colors.purple;
                    badgeText = "Teachers";
                  } else if (type == 'fee_urgent') {
                    typeIcon = Icons.warning_rounded;
                    typeColor = Colors.red;
                    badgeText = "Debtors";
                  } else if (type == 'school_website') {
                    // 🚨 NEW BADGE FOR SCHOOL WEBSITE ALERTS
                    typeIcon = Icons.public;
                    typeColor = Colors.teal;
                    badgeText = "Website";
                  }

                  return Card(
                    margin: const EdgeInsets.only(bottom: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: typeColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    Icon(typeIcon, size: 12, color: typeColor),
                                    const SizedBox(width: 4),
                                    Text(
                                      badgeText,
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: typeColor,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Spacer(),
                              Text(
                                alert['created_at'] != null
                                    ? DateFormat('MMM dd, hh:mm a').format(
                                        DateTime.parse(alert['created_at']),
                                      )
                                    : '',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey,
                                ),
                              ),
                              const SizedBox(width: 5),
                              InkWell(
                                onTap: () => _deleteAlert(alert['id']),
                                child: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.red,
                                  size: 18,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            alert['title'] ?? 'Notice',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            alert['message'] ?? '',
                            style: TextStyle(
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
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
            return Center(
              child: CircularProgressIndicator(color: primaryColor),
            );
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
                    Icons.receipt_long,
                    isDark,
                  ),
                ),
              ],
            );
          }

          return ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            itemCount: txs.length,
            itemBuilder: (context, index) {
              final tx = txs[index];
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white10 : Colors.white,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: Colors.grey.withOpacity(0.1)),
                ),
                child: ListTile(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AdminReceiptDetailView(tx: tx),
                    ),
                  ),
                  leading: const CircleAvatar(
                    backgroundColor: Colors.green,
                    child: Icon(
                      Icons.receipt_long,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  title: Text(
                    tx['student_name'] ?? 'Unknown',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    DateFormat(
                      'dd MMM, yyyy',
                    ).format(DateTime.parse(tx['created_at'])),
                  ),
                  trailing: Text(
                    NumberFormat.currency(
                      symbol: '₦',
                      decimalDigits: 0,
                    ).format(tx['amount']),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
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
        Icon(i, size: 60, color: Colors.grey[400]),
        const SizedBox(height: 10),
        Text(
          t,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        Text(s, style: const TextStyle(color: Colors.grey, fontSize: 13)),
      ],
    ),
  );
}
