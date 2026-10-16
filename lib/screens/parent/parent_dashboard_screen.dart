import 'dart:convert'; // 🚨 IMPORTED: For the Smart Shield JSON decoding
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trideta_v2/utils/auth_error_handler.dart';
import 'package:trideta_v2/widgets/trideta_loader.dart';
import 'package:trideta_v2/screens/parent/parent_ui_kit.dart';

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

  Future<void> _fetchParentData({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);
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
        _primarySession =
            _myChildren[0]['schools']?['current_session'] ?? "N/A";
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

  // ===========================================================================
  // 🖼️ UI ONLY — everything below is presentation. The data/debt/alert logic
  // above is untouched.
  // ===========================================================================
  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = PUi.bg(isDark);
    Color navBarColor = PUi.surface(isDark);
    Color primaryColor = Theme.of(context).primaryColor;

    final List<Widget> mobilePages = [
      ParentHomeTab(
        parentName: _parentName,
        parentEmail: _parentEmail,
        primarySession: _primarySession,
        myChildren: _myChildren,
        alerts: _alerts,
        showAlertBrief: _showAlertBrief,
        onRefresh: () => _fetchParentData(silent: true),
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
        onRefresh: () => _fetchParentData(silent: true),
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
          // Full sidebar on large desktops, slim icon rail on smaller ones.
          final bool expanded = constraints.maxWidth >= 1100;
          return Scaffold(
            backgroundColor: bgColor,
            body: Row(
              children: [
                _buildDesktopSidebar(
                  expanded,
                  isDark,
                  primaryColor,
                  navBarColor,
                ),
                Expanded(child: desktopPages[_currentIndex]),
              ],
            ),
          );
        }

        return Scaffold(
          backgroundColor: bgColor,
          body: IndexedStack(index: _currentIndex, children: mobilePages),
          bottomNavigationBar: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: PUi.border(isDark))),
            ),
            child: NavigationBarTheme(
              data: NavigationBarThemeData(
                height: 68,
                elevation: 0,
                backgroundColor: navBarColor,
                surfaceTintColor: Colors.transparent,
                indicatorColor: primaryColor.withValues(alpha: 0.14),
                indicatorShape: const StadiumBorder(),
                labelTextStyle: WidgetStateProperty.resolveWith((states) {
                  final selected = states.contains(WidgetState.selected);
                  return TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? primaryColor : PUi.muted(isDark),
                  );
                }),
              ),
              child: NavigationBar(
                selectedIndex: _currentIndex,
                onDestinationSelected: (i) {
                  setState(() => _currentIndex = i);
                },
                destinations: [
                  NavigationDestination(
                    icon: Icon(
                      Icons.home_outlined,
                      color: PUi.muted(isDark),
                    ),
                    selectedIcon: Icon(Icons.home_rounded, color: primaryColor),
                    label: 'Home',
                  ),
                  NavigationDestination(
                    icon: Icon(
                      Icons.family_restroom_outlined,
                      color: PUi.muted(isDark),
                    ),
                    selectedIcon: Icon(
                      Icons.family_restroom,
                      color: primaryColor,
                    ),
                    label: 'Wards',
                  ),
                  NavigationDestination(
                    icon: Icon(
                      Icons.notifications_none_rounded,
                      color: PUi.muted(isDark),
                    ),
                    selectedIcon: Icon(
                      Icons.notifications_active_rounded,
                      color: primaryColor,
                    ),
                    label: 'Alerts',
                  ),
                  NavigationDestination(
                    icon: Icon(
                      Icons.person_outline,
                      color: PUi.muted(isDark),
                    ),
                    selectedIcon: Icon(Icons.person, color: primaryColor),
                    label: 'Profile',
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // 🖥️ DESKTOP SIDEBAR
  // ---------------------------------------------------------------------------
  Widget _buildDesktopSidebar(
    bool expanded,
    bool isDark,
    Color primaryColor,
    Color navBarColor,
  ) {
    final initial = _parentName.isNotEmpty
        ? _parentName[0].toUpperCase()
        : 'P';

    return Container(
      width: expanded ? 264 : 92,
      decoration: BoxDecoration(
        color: navBarColor,
        border: Border(right: BorderSide(color: PUi.border(isDark))),
      ),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(expanded ? 20 : 14, 28, expanded ? 20 : 14, 20),
          child: Column(
            crossAxisAlignment: expanded
                ? CrossAxisAlignment.stretch
                : CrossAxisAlignment.center,
            children: [
              // Logo
              Row(
                mainAxisAlignment: expanded
                    ? MainAxisAlignment.start
                    : MainAxisAlignment.center,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: PUi.tint(primaryColor, isDark, 0.12),
                    ),
                    child: Icon(
                      Icons.school_rounded,
                      color: primaryColor,
                      size: 24,
                    ),
                  ),
                  if (expanded) ...[
                    const SizedBox(width: 12),
                    Text(
                      "TRIDETA",
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 19,
                        letterSpacing: 2,
                        color: PUi.ink(isDark),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 36),

              // Navigation
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      _buildDesktopNavItem(
                        Icons.home_rounded,
                        "Home",
                        0,
                        primaryColor,
                        isDark,
                        expanded,
                      ),
                      _buildDesktopNavItem(
                        Icons.family_restroom,
                        "Wards",
                        1,
                        primaryColor,
                        isDark,
                        expanded,
                      ),
                      _buildDesktopNavItem(
                        Icons.notifications_active_rounded,
                        "Alerts",
                        2,
                        primaryColor,
                        isDark,
                        expanded,
                      ),
                      _buildDesktopNavItem(
                        Icons.person,
                        "Profile",
                        3,
                        primaryColor,
                        isDark,
                        expanded,
                      ),
                    ],
                  ),
                ),
              ),

              // Signed-in parent
              if (expanded)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: PUi.surfaceAlt(isDark),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 19,
                        backgroundColor: PUi.tint(primaryColor, isDark, 0.14),
                        child: Text(
                          initial,
                          style: TextStyle(
                            color: primaryColor,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _parentName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: PUi.ink(isDark),
                              ),
                            ),
                            if (_parentEmail.isNotEmpty)
                              Text(
                                _parentEmail,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: PUi.muted(isDark),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )
              else
                CircleAvatar(
                  radius: 21,
                  backgroundColor: PUi.tint(primaryColor, isDark, 0.14),
                  child: Text(
                    initial,
                    style: TextStyle(
                      color: primaryColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopNavItem(
    IconData icon,
    String title,
    int index,
    Color primaryColor,
    bool isDark,
    bool expanded,
  ) {
    final bool isSelected = _currentIndex == index;
    final Color fg = isSelected ? Colors.white : PUi.muted(isDark);

    void select() {
      setState(() => _currentIndex = index);
    }

    if (!expanded) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Tooltip(
          message: title,
          child: Material(
            color: isSelected ? primaryColor : Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: select,
              child: SizedBox(
                width: 54,
                height: 54,
                child: Icon(icon, color: fg, size: 24),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: isSelected ? primaryColor : Colors.transparent,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: select,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(
              children: [
                Icon(icon, color: fg, size: 22),
                const SizedBox(width: 14),
                Text(
                  title,
                  style: TextStyle(
                    color: fg,
                    fontSize: 15,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
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
