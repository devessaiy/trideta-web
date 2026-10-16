import 'dart:convert'; // 🚨 IMPORTED FOR SMART SHIELD JSON DECODING
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:trideta_v2/widgets/trideta_loader.dart';
import 'package:trideta_v2/screens/parent/parent_ui_kit.dart';

class ParentAlertsMasterDetail extends StatefulWidget {
  const ParentAlertsMasterDetail({super.key});

  @override
  State<ParentAlertsMasterDetail> createState() =>
      _ParentAlertsMasterDetailState();

  // Helper to safely parse the Hex Color from the Database
  static Color getSchoolColor(Map<String, dynamic>? school, Color fallback) {
    if (school == null) return fallback;
    String? hexStr = school['brand_color'];
    if (hexStr != null && hexStr.isNotEmpty) {
      try {
        hexStr = hexStr.replaceAll('#', '');
        if (hexStr.length == 6) hexStr = 'FF$hexStr';
        return Color(int.parse(hexStr, radix: 16));
      } catch (_) {}
    }
    return fallback;
  }

  // ===========================================================================
  // 🖼️ PREMIUM DETAIL / READING PANE (UI only)
  // ===========================================================================
  static Widget buildDetailPane(
    Map<String, dynamic> alert,
    Color primaryColor,
    bool isDark,
  ) {
    Color schoolColor = getSchoolColor(alert['schools'], primaryColor);

    // Check if urgent
    String type = (alert['type'] ?? '').toString().toLowerCase();
    if (type.contains('urgent') ||
        type.contains('fee') ||
        type.contains('debtor')) {
      schoolColor = Colors.orange;
    }

    String dateStr = alert['created_at'] != null
        ? DateFormat(
            'EEEE, MMMM d, yyyy  •  h:mm a',
          ).format(DateTime.parse(alert['created_at']))
        : '';

    final String? logoUrl = alert['schools']?['logo_url'];

    return LayoutBuilder(
      builder: (context, c) {
        final double pad = c.maxWidth < 600 ? 20.0 : 40.0;
        final bool narrow = c.maxWidth < 600;

        return Container(
          color: PUi.bg(isDark),
          child: PBackdrop(
            accent: schoolColor,
            child: SingleChildScrollView(
              padding: EdgeInsets.all(pad),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 780),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Type + date
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          PPill(
                            text: type.replaceAll('_', ' ').toUpperCase(),
                            color: schoolColor,
                          ),
                          Text(
                            dateStr,
                            style: TextStyle(
                              color: PUi.muted(isDark),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text(
                        alert['title'] ?? 'Notice',
                        style: PUi.title(isDark, size: narrow ? 26 : 32),
                      ),
                      const SizedBox(height: 22),

                      // Sender
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 21,
                            backgroundColor: PUi.tint(schoolColor, isDark, 0.12),
                            backgroundImage: logoUrl != null
                                ? NetworkImage(logoUrl)
                                : null,
                            child: logoUrl == null
                                ? Icon(
                                    Icons.school_rounded,
                                    size: 20,
                                    color: schoolColor,
                                  )
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "From",
                                  style: TextStyle(
                                    color: PUi.muted(isDark),
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  alert['schools']?['name'] ??
                                      'School Administration',
                                  style: TextStyle(
                                    color: PUi.ink(isDark),
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14.5,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 26),

                      // Message body
                      PCard(
                        radius: 28,
                        padding: EdgeInsets.all(narrow ? 22 : 32),
                        child: SizedBox(
                          width: double.infinity,
                          child: Text(
                            alert['message'] ?? '',
                            softWrap: true,
                            style: TextStyle(
                              fontSize: narrow ? 15.5 : 16.5,
                              height: 1.75,
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ParentAlertsMasterDetailState extends State<ParentAlertsMasterDetail> {
  final _supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _alerts = [];
  List<Map<String, dynamic>> _uniqueSchools = [];
  String? _selectedFilterSchoolId;

  Map<String, dynamic>? _selectedAlert;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchAlerts();
  }

  // ===========================================================================
  // 🚨 SMART SHIELD UTILS (Copied perfectly from the Admin Engine)
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

  List<Map<String, dynamic>> get _filteredAlerts {
    if (_selectedFilterSchoolId == null) return _alerts;
    return _alerts
        .where((a) => a['school_id'].toString() == _selectedFilterSchoolId)
        .toList();
  }

  Future<void> _fetchAlerts() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final childrenData = await _supabase
          .from('students')
          .select(
            // 🚨 FETCHED CURRENT TERM FOR THE DEBT ENGINE
            '*, schools(id, name, logo_url, brand_color, current_session, current_term)',
          )
          .eq('parent_email', user.email ?? '');

      if (childrenData.isEmpty) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      Map<String, Map<String, dynamic>> schoolMap = {};

      for (var child in childrenData) {
        var s = child['schools'];
        if (s != null) schoolMap[s['id'].toString()] = s;
      }

      _uniqueSchools = schoolMap.values.toList();
      List<String> schoolIds = _uniqueSchools
          .map((s) => s['id'].toString())
          .toList();

      // =======================================================================
      // 🚨 SMART DEBTOR SHIELD ENGINE
      // Runs instantly in the background to calculate if this parent is owing!
      // =======================================================================
      bool hasOutstandingDebt = false;
      try {
        List<String> childIds = childrenData
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

        for (var child in childrenData) {
          var school = child['schools'];
          if (school == null) continue;

          String currentSession = (school['current_session'] ?? '').toString();
          String currentTerm = (school['current_term'] ?? '1st Term')
              .toString();

          String sClass = (child['class_level'] ?? child['current_class'] ?? '')
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

      // Normal Announcements that everyone gets to see
      List<String> allowedAlertTypes = [
        'school_website',
        'general',
        'parent_alert',
      ];

      // 🚨 SHIELD APPLIED: If the parent has no debt, the app completely ignores debtor alerts!
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

      if (_alerts.isNotEmpty) _selectedAlert = _alerts[0];

      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      debugPrint("Failed to load alerts: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _markAsRead(Map<String, dynamic> alert, bool isMobile) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    setState(() {
      _selectedAlert = alert;
      int index = _alerts.indexWhere((a) => a['id'] == alert['id']);
      if (index != -1) _alerts[index]['is_read'] = true;
    });

    try {
      await _supabase.from('alert_reads').upsert({
        'alert_id': alert['id'],
        'user_id': user.id,
      });
    } catch (e) {
      debugPrint("Background read-receipt sync failed: $e");
    }

    if (isMobile && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MobileAlertDetailScreen(alert: alert),
        ),
      );
    }
  }

  // ===========================================================================
  // 🖼️ UI ONLY — presentation below. Fetching, the debtor shield and the
  // read-receipt sync above are untouched.
  // ===========================================================================
  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color primaryColor = Theme.of(context).primaryColor;
    Color bgColor = PUi.bg(isDark);

    if (_isLoading) {
      return Scaffold(
        backgroundColor: bgColor,
        body: Center(child: TridetaLoader(color: primaryColor)),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        bool isMobile = constraints.maxWidth < 900;
        final double listWidth = constraints.maxWidth >= 1250 ? 420 : 370;

        Widget inboxList = Material(
          color: bgColor,
          child: Container(
            width: isMobile ? double.infinity : listWidth,
            decoration: BoxDecoration(
              border: isMobile
                  ? null
                  : Border(right: BorderSide(color: PUi.border(isDark))),
            ),
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 18),
                    child: Text(
                      "Announcements",
                      style: PUi.title(isDark, size: 30),
                    ),
                  ),

                  if (_uniqueSchools.length > 1)
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          _buildFilterChip("All", null, primaryColor, isDark),
                          ..._uniqueSchools.map(
                            (s) => _buildFilterChip(
                              s['name'],
                              s['id'].toString(),
                              ParentAlertsMasterDetail.getSchoolColor(
                                s,
                                primaryColor,
                              ),
                              isDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_uniqueSchools.length > 1) const SizedBox(height: 18),

                  Expanded(
                    child: _filteredAlerts.isEmpty
                        ? Center(
                            child: PEmptyState(
                              title: "No announcements found.",
                              accent: primaryColor,
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                            itemCount: _filteredAlerts.length,
                            itemBuilder: (context, index) {
                              final alert = _filteredAlerts[index];
                              return _buildAlertCard(
                                alert,
                                isMobile,
                                isDark,
                                primaryColor,
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        );

        if (isMobile) {
          return Scaffold(
            backgroundColor: bgColor,
            body: PBackdrop(accent: primaryColor, child: inboxList),
          );
        }

        return Scaffold(
          backgroundColor: bgColor,
          body: Row(
            children: [
              inboxList,
              Expanded(
                child: _selectedAlert == null || _filteredAlerts.isEmpty
                    ? Center(
                        child: PEmptyState(
                          title: "Select an announcement to read",
                          accent: primaryColor,
                        ),
                      )
                    : ParentAlertsMasterDetail.buildDetailPane(
                        _selectedAlert!,
                        primaryColor,
                        isDark,
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAlertCard(
    Map<String, dynamic> alert,
    bool isMobile,
    bool isDark,
    Color primaryColor,
  ) {
    bool isSelected = !isMobile && _selectedAlert?['id'] == alert['id'];
    bool isUnread = !(alert['is_read'] ?? false);

    Color schoolBrandColor = ParentAlertsMasterDetail.getSchoolColor(
      alert['schools'],
      primaryColor,
    );
    String type = (alert['type'] ?? '').toString().toLowerCase();

    Color iconColor = isUnread ? schoolBrandColor : PUi.muted(isDark);
    IconData badgeIcon = Icons.notifications_rounded;

    if (type.contains('urgent') ||
        type.contains('fee') ||
        type.contains('debtor')) {
      iconColor = isUnread ? Colors.orange : PUi.muted(isDark);
      badgeIcon = Icons.warning_rounded;
    }

    String timeAgo = alert['created_at'] != null
        ? DateFormat('MMM d').format(DateTime.parse(alert['created_at']))
        : '';

    return GestureDetector(
      onTap: () => _markAsRead(alert, isMobile),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? PUi.tint(schoolBrandColor, isDark, 0.07)
              : PUi.surface(isDark),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSelected
                ? schoolBrandColor.withValues(alpha: 0.55)
                : PUi.border(isDark),
            width: isSelected ? 1.6 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: schoolBrandColor.withValues(alpha: 0.12),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ]
              : PUi.softShadow(isDark),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 2),
              child: PIconBadge(
                icon: badgeIcon,
                color: iconColor,
                size: 44,
                iconSize: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (isUnread)
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: schoolBrandColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                      Expanded(
                        child: Text(
                          alert['title'] ?? 'Notice',
                          style: TextStyle(
                            fontWeight: isUnread
                                ? FontWeight.w800
                                : FontWeight.w600,
                            fontSize: 15,
                            color: PUi.ink(isDark),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        timeAgo,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: isUnread
                              ? schoolBrandColor
                              : PUi.muted(isDark),
                          fontWeight: isUnread
                              ? FontWeight.w800
                              : FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    alert['message'] ?? '',
                    style: TextStyle(
                      fontSize: 13,
                      color: isUnread
                          ? (isDark ? Colors.white70 : Colors.black87)
                          : PUi.muted(isDark),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(
    String label,
    String? schoolId,
    Color color,
    bool isDark,
  ) {
    bool isActive = _selectedFilterSchoolId == schoolId;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedFilterSchoolId = schoolId;
          if (_filteredAlerts.isNotEmpty) {
            _selectedAlert = _filteredAlerts[0];
          } else {
            _selectedAlert = null;
          }
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        decoration: BoxDecoration(
          color: isActive ? color : PUi.surface(isDark),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: isActive ? color : PUi.border(isDark)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
            color: isActive ? Colors.white : PUi.muted(isDark),
          ),
        ),
      ),
    );
  }
}

class MobileAlertDetailScreen extends StatelessWidget {
  final Map<String, dynamic> alert;
  const MobileAlertDetailScreen({super.key, required this.alert});

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color primaryColor = Theme.of(context).primaryColor;

    return Scaffold(
      backgroundColor: PUi.bg(isDark),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 20, 4),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.maybePop(context),
                    style: IconButton.styleFrom(
                      backgroundColor: PUi.surface(isDark),
                      side: BorderSide(color: PUi.border(isDark)),
                      minimumSize: const Size(44, 44),
                    ),
                    icon: Icon(
                      Icons.arrow_back_rounded,
                      color: PUi.ink(isDark),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    "Announcement",
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                      color: PUi.ink(isDark),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ParentAlertsMasterDetail.buildDetailPane(
                alert,
                primaryColor,
                isDark,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
