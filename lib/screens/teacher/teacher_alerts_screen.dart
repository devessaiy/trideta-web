import 'package:flutter/material.dart';
import 'package:trideta_v2/services/read_through.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:trideta_v2/widgets/trideta_loader.dart';
import 'package:trideta_v2/widgets/trideta_ui_kit.dart';

class TeacherAlertsScreen extends StatefulWidget {
  const TeacherAlertsScreen({super.key});

  @override
  State<TeacherAlertsScreen> createState() => _TeacherAlertsScreenState();
}

class _TeacherAlertsScreenState extends State<TeacherAlertsScreen> {
  final _supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _alerts = [];
  Map<String, dynamic>? _selectedAlert;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchAlerts();
  }

  Future<void> _fetchAlerts() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final profile = await readThrough(
        'a851cdd3|profiles|${user.id}',
        () async => await _supabase
            .from('profiles')
            .select('school_id')
            .eq('id', user.id)
            .single(),
        fresh: const Duration(minutes: 10),
      );

      // 🚨 MAINTAINED STRICT LOGIC: Only Teacher-relevant alerts
      final allowedAlertTypes = ['school_website', 'general', 'teacher_alert'];

      // 🚨 Added JOIN for school data to get Brand Color & Logos for the UI
      final alertsData = await readThrough(
        'e38530ae|alerts|${profile['school_id']}|$allowedAlertTypes',
        () async => await _supabase
            .from('alerts')
            .select('*, schools(id, name, logo_url, brand_color)')
            .eq('school_id', profile['school_id'])
            .filter('type', 'in', allowedAlertTypes)
            .order('created_at', ascending: false),
      );

      // 🚨 Safe Read-Receipt Check (For the Unread Badge Integration)
      List<String> fetchedAlertIds = (alertsData as List)
          .map((a) => a['id'].toString())
          .toList();
      Set<String> readAlertIds = {};

      if (fetchedAlertIds.isNotEmpty) {
        final readsData = await readThrough(
          '169a3b11|alert_reads|${user.id}|$fetchedAlertIds',
          () async => await _supabase
              .from('alert_reads')
              .select('alert_id')
              .eq('user_id', user.id)
              .filter('alert_id', 'in', fetchedAlertIds),
        );

        readAlertIds = (readsData as List)
            .map((r) => r['alert_id'].toString())
            .toSet();
      }

      _alerts = List<Map<String, dynamic>>.from(alertsData).map((alert) {
        alert['is_read'] = readAlertIds.contains(alert['id'].toString());
        return alert;
      }).toList();

      if (_alerts.isNotEmpty) _selectedAlert = _alerts[0];

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint("Failed to load teacher alerts: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 🚨 Triggers when a teacher clicks an alert to read it
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
          builder: (_) => MobileTeacherAlertDetailScreen(alert: alert),
        ),
      );
    }
  }

  // UI Helper for School Colors
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

        // ─── MASTER INBOX LIST ───
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
                  Expanded(
                    child: _alerts.isEmpty
                        ? Center(
                            child: PEmptyState(
                              title: "You're all caught up!",
                              accent: primaryColor,
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                            itemCount: _alerts.length,
                            itemBuilder: (context, index) {
                              return _buildAlertCard(
                                _alerts[index],
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

        // ─── DESKTOP MASTER DETAIL ───
        return Scaffold(
          backgroundColor: bgColor,
          body: Row(
            children: [
              inboxList,
              Expanded(
                child: _selectedAlert == null
                    ? Center(
                        child: PEmptyState(
                          title: "Select an announcement to read",
                          accent: primaryColor,
                        ),
                      )
                    : buildDetailPane(_selectedAlert!, primaryColor, isDark),
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

    Color schoolBrandColor = getSchoolColor(alert['schools'], primaryColor);
    String type = (alert['type'] ?? '').toString().toLowerCase();

    Color iconColor = isUnread ? schoolBrandColor : PUi.muted(isDark);
    IconData badgeIcon = Icons.notifications_rounded;

    if (type.contains('urgent')) {
      iconColor = isUnread ? Colors.redAccent : PUi.muted(isDark);
      badgeIcon = Icons.warning_rounded;
    } else if (type.contains('teacher')) {
      iconColor = isUnread ? Colors.purple : PUi.muted(isDark);
      badgeIcon = Icons.school_rounded;
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

  // ===========================================================================
  // PREMIUM READING PANE (Static helper so the mobile view can use it too)
  // ===========================================================================
  static Widget buildDetailPane(
    Map<String, dynamic> alert,
    Color primaryColor,
    bool isDark,
  ) {
    Color schoolColor = getSchoolColor(alert['schools'], primaryColor);

    String type = (alert['type'] ?? '').toString().toLowerCase();
    if (type.contains('urgent')) schoolColor = Colors.redAccent;
    if (type.contains('teacher')) schoolColor = Colors.purple;

    String dateStr = alert['created_at'] != null
        ? DateFormat(
            'EEEE, MMMM d, yyyy  •  h:mm a',
          ).format(DateTime.parse(alert['created_at']))
        : '';

    final String? logoUrl = alert['schools']?['logo_url'];

    return LayoutBuilder(
      builder: (context, c) {
        final bool narrow = c.maxWidth < 600;
        final double pad = narrow ? 20.0 : 40.0;

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

// ─── MOBILE READING VIEW ───
class MobileTeacherAlertDetailScreen extends StatelessWidget {
  final Map<String, dynamic> alert;
  const MobileTeacherAlertDetailScreen({super.key, required this.alert});

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
              child: _TeacherAlertsScreenState.buildDetailPane(
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
