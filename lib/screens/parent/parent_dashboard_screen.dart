import 'dart:convert'; // 🚨 IMPORTED: For the Smart Shield JSON decoding
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trideta_v2/utils/auth_error_handler.dart';
import 'package:trideta_v2/widgets/trideta_loader.dart';

import 'package:trideta_v2/screens/parent/tabs/parent_home_tab.dart';
import 'package:trideta_v2/screens/parent/tabs/parent_wards_tab.dart';
import 'package:trideta_v2/screens/parent/tabs/parent_profile_tab.dart';
import 'package:trideta_v2/screens/parent/parent_alerts_master_detail.dart';

class ParentDashboardScreen extends StatefulWidget {
  const ParentDashboardScreen({super.key});

  @override
  State<ParentDashboardScreen> createState() => _ParentDashboardScreenState();
}

class _ParentDashboardScreenState extends State<ParentDashboardScreen>
    with AuthErrorHandler {
  final _supabase = Supabase.instance.client;

  int _currentIndex = 0;
  bool _isLoading = true;

  String _parentName = "Parent";
  String _parentEmail = "";
  String _primarySession = "N/A";
  List<Map<String, dynamic>> _myChildren = [];
  List<Map<String, dynamic>> _alerts = [];
  bool _showAlertBrief = true;

  @override
  void initState() {
    super.initState();
    _fetchParentData();
  }

  // ===========================================================================
  // 🚨 SMART SHIELD UTILS (Identical to Master Detail)
  // ===========================================================================
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

    if (columnData is String && columnData.startsWith('[')) {
      try {
        List<dynamic> parsedList = jsonDecode(columnData);
        if (parsedList.isEmpty) return true;
        for (var item in parsedList) {
          String cleanItem = isCategory
              ? item.toString().replaceAll(' ', '').toLowerCase()
              : _standardizeClass(item.toString());
          if (cleanItem == 'all' || cleanItem == cleanStudentData) return true;
        }
        return false;
      } catch (e) {
        // Fallback
      }
    }

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

  Future<void> _fetchParentData() async {
    setState(() => _isLoading = true);
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;
      _parentEmail = user.email ?? "";

      final profile = await _supabase
          .from('profiles')
          .select('full_name')
          .eq('id', user.id)
          .maybeSingle();
      if (profile != null) _parentName = profile['full_name'] ?? "Parent";

      final childrenData = await _supabase
          .from('students')
          .select(
            // 🚨 FETCHED CURRENT TERM FOR THE DEBT ENGINE
            '*, schools(id, name, logo_url, brand_color, current_session, current_term)',
          )
          .eq('parent_email', _parentEmail);
      _myChildren = List<Map<String, dynamic>>.from(childrenData);

      if (_myChildren.isNotEmpty) {
        _primarySession = _myChildren[0]['schools']['current_session'] ?? "N/A";
        if (_myChildren[0]['parent_name'] != null &&
            _myChildren[0]['parent_name'].toString().isNotEmpty) {
          _parentName = _myChildren[0]['parent_name'];
        }
      }

      if (_myChildren.isNotEmpty) {
        List<String> schoolIds = _myChildren
            .map((c) => c['school_id'].toString())
            .toSet()
            .toList();

        // =======================================================================
        // 🚨 SMART DEBTOR SHIELD ENGINE (Root Dashboard Version)
        // Calculates debt to ensure Home Page Previews and Notification Counters
        // DO NOT show debtor alerts to non-debtors!
        // =======================================================================
        bool hasOutstandingDebt = false;
        try {
          List<String> childIds = _myChildren
              .map((c) => c['id'].toString())
              .toList();

          final txsData = await _supabase
              .from('transactions')
              .select('student_id, amount, academic_session, academic_term')
              .filter('student_id', 'in', childIds);

          final feesData = await _supabase
              .from('fee_structures')
              .select(
                'amount, applicable_classes, applicable_categories, academic_term, academic_session, school_id',
              )
              .filter('school_id', 'in', schoolIds);

          for (var child in _myChildren) {
            var school = child['schools'];
            if (school == null) continue;

            String currentSession = (school['current_session'] ?? '')
                .toString();
            String currentTerm = (school['current_term'] ?? '1st Term')
                .toString();

            String sClass =
                (child['class_level'] ?? child['current_class'] ?? '')
                    .toString();
            String sCategory = (child['category'] ?? '').toString();
            double walletBalance = (child['wallet_balance'] ?? 0).toDouble();

            double expected = 0.0;
            for (var fee in feesData) {
              if (fee['school_id'].toString() == school['id'].toString() &&
                  fee['academic_session'].toString() == currentSession &&
                  (fee['academic_term'].toString() == currentTerm ||
                      fee['academic_term'].toString() == 'All Terms')) {
                if (_doesItApply(fee['applicable_classes'], sClass) &&
                    _doesItApply(
                      fee['applicable_categories'],
                      sCategory,
                      isCategory: true,
                    )) {
                  expected += (fee['amount'] ?? 0).toDouble();
                }
              }
            }

            double paid = 0.0;
            for (var tx in txsData) {
              if (tx['student_id'].toString() == child['id'].toString()) {
                String txSession = (tx['academic_session'] ?? '').toString();
                String txTerm = (tx['academic_term'] ?? 'All Terms').toString();
                if ((txSession == currentSession || txSession.isEmpty) &&
                    (txTerm == currentTerm ||
                        txTerm == 'All Terms' ||
                        currentTerm == 'All Terms')) {
                  paid += (tx['amount'] ?? 0).toDouble();
                }
              }
            }

            double balance = expected - paid - walletBalance;
            if (balance > 0) {
              hasOutstandingDebt = true;
              break;
            }
          }
        } catch (e) {
          debugPrint("Error checking debt logic: $e");
        }
        // =======================================================================

        List<String> allowedAlertTypes = [
          'school_website',
          'general',
          'parent_alert',
        ];

        // 🚨 SHIELD APPLIED: Only allows debtor alerts through if they owe money
        if (hasOutstandingDebt) {
          allowedAlertTypes.addAll(['fee_urgent', 'fee', 'urgent', 'debtor']);
        }

        final alertsData = await _supabase
            .from('alerts')
            .select('*, schools(id, name, logo_url, brand_color)')
            .filter('school_id', 'in', schoolIds)
            .filter('type', 'in', allowedAlertTypes)
            .order('created_at', ascending: false);

        List<String> fetchedAlertIds = (alertsData as List)
            .map((a) => a['id'].toString())
            .toList();
        Set<String> readAlertIds = {};

        if (fetchedAlertIds.isNotEmpty) {
          final readsData = await _supabase
              .from('alert_reads')
              .select('alert_id')
              .eq('user_id', user.id)
              .filter('alert_id', 'in', fetchedAlertIds);
          readAlertIds = (readsData as List)
              .map((r) => r['alert_id'].toString())
              .toSet();
        }

        _alerts = List<Map<String, dynamic>>.from(alertsData).map((alert) {
          alert['is_read'] = readAlertIds.contains(alert['id'].toString());
          return alert;
        }).toList();
      }

      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        showAuthErrorDialog(
          "Failed to load dashboard data. Check your internet connection.",
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC);
    Color navBarColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    Color primaryColor = Theme.of(context).primaryColor;

    final List<Widget> mobilePages = [
      ParentHomeTab(
        parentName: _parentName,
        parentEmail: _parentEmail,
        primarySession: _primarySession,
        myChildren: _myChildren,
        alerts: _alerts,
        showAlertBrief: _showAlertBrief,
        onRefresh: _fetchParentData,
        onNavigate: (i) => setState(() => _currentIndex = i),
        onDismissAlert: () => setState(() => _showAlertBrief = false),
      ),
      ParentWardsTab(myChildren: _myChildren, onRefresh: _fetchParentData),
      const ParentAlertsMasterDetail(),
      ParentProfileTab(parentName: _parentName),
    ];

    final List<Widget> desktopPages = [
      ParentHomeTab(
        parentName: _parentName,
        parentEmail: _parentEmail,
        primarySession: _primarySession,
        myChildren: _myChildren,
        alerts: _alerts,
        showAlertBrief: _showAlertBrief,
        onRefresh: _fetchParentData,
        onNavigate: (i) => setState(() => _currentIndex = i),
        onDismissAlert: () => setState(() => _showAlertBrief = false),
      ),
      ParentWardsTab(myChildren: _myChildren, onRefresh: _fetchParentData),
      const ParentAlertsMasterDetail(),
      ParentProfileTab(parentName: _parentName),
    ];

    if (_isLoading) {
      return Scaffold(
        backgroundColor: bgColor,
        body: Center(child: TridetaLoader(color: primaryColor)),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 900) {
          return Scaffold(
            backgroundColor: bgColor,
            body: Row(
              children: [
                Container(
                  width: 250,
                  color: navBarColor,
                  child: Column(
                    children: [
                      const SizedBox(height: 40),
                      Icon(Icons.school, size: 50, color: primaryColor),
                      const SizedBox(height: 20),
                      const Text(
                        "TRIDETA",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 40),
                      _buildDesktopNavItem(
                        Icons.home_rounded,
                        "Home",
                        0,
                        primaryColor,
                      ),
                      _buildDesktopNavItem(
                        Icons.family_restroom,
                        "Wards",
                        1,
                        primaryColor,
                      ),
                      _buildDesktopNavItem(
                        Icons.notifications_active_rounded,
                        "Alerts",
                        2,
                        primaryColor,
                      ),
                      _buildDesktopNavItem(
                        Icons.person,
                        "Profile",
                        3,
                        primaryColor,
                      ),
                    ],
                  ),
                ),
                Expanded(child: desktopPages[_currentIndex]),
              ],
            ),
          );
        }

        return Scaffold(
          backgroundColor: bgColor,
          body: IndexedStack(index: _currentIndex, children: mobilePages),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: (i) {
              setState(() => _currentIndex = i);
              if (i == 0) _fetchParentData();
            },
            backgroundColor: navBarColor,
            indicatorColor: primaryColor.withValues(alpha: 0.1),
            destinations: [
              NavigationDestination(
                icon: const Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home_rounded, color: primaryColor),
                label: 'Home',
              ),
              NavigationDestination(
                icon: const Icon(Icons.family_restroom_outlined),
                selectedIcon: Icon(Icons.family_restroom, color: primaryColor),
                label: 'Wards',
              ),
              NavigationDestination(
                icon: const Icon(Icons.notifications_none_rounded),
                selectedIcon: Icon(
                  Icons.notifications_active_rounded,
                  color: primaryColor,
                ),
                label: 'Alerts',
              ),
              NavigationDestination(
                icon: const Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person, color: primaryColor),
                label: 'Profile',
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDesktopNavItem(
    IconData icon,
    String title,
    int index,
    Color primaryColor,
  ) {
    bool isSelected = _currentIndex == index;
    return ListTile(
      leading: Icon(icon, color: isSelected ? primaryColor : Colors.grey),
      title: Text(
        title,
        style: TextStyle(
          color: isSelected ? primaryColor : Colors.grey,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      selected: isSelected,
      selectedTileColor: primaryColor.withValues(alpha: 0.1),
      onTap: () {
        setState(() => _currentIndex = index);
        if (index == 0) _fetchParentData();
      },
    );
  }
}
