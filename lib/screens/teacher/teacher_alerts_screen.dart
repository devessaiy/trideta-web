import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:trideta_v2/widgets/trideta_loader.dart';

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

      final profile = await _supabase
          .from('profiles')
          .select('school_id')
          .eq('id', user.id)
          .single();

      // 🚨 MAINTAINED STRICT LOGIC: Only Teacher-relevant alerts
      final allowedAlertTypes = ['school_website', 'general', 'teacher_alert'];

      // 🚨 Added JOIN for school data to get Brand Color & Logos for the UI
      final alertsData = await _supabase
          .from('alerts')
          .select('*, schools(id, name, logo_url, brand_color)')
          .eq('school_id', profile['school_id'])
          .filter('type', 'in', allowedAlertTypes)
          .order('created_at', ascending: false);

      // 🚨 Safe Read-Receipt Check (For the Unread Badge Integration)
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
    Color bgColor = isDark ? const Color(0xFF121212) : Colors.white;
    Color textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);

    if (_isLoading) {
      return Scaffold(
        backgroundColor: bgColor,
        body: Center(child: TridetaLoader(color: primaryColor)),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        bool isMobile = constraints.maxWidth < 900;

        // ─── MASTER INBOX LIST ───
        Widget inboxList = Material(
          color: bgColor,
          child: Container(
            width: isMobile ? double.infinity : 400,
            decoration: BoxDecoration(
              border: isMobile
                  ? null
                  : Border(
                      right: BorderSide(
                        color: Colors.grey.withValues(alpha: 0.15),
                      ),
                    ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 30, 24, 20),
                  child: Text(
                    "Announcements",
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                ),

                Expanded(
                  child: _alerts.isEmpty
                      ? Center(
                          child: Text(
                            "You're all caught up!",
                            style: TextStyle(color: Colors.grey.shade500),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 10,
                          ),
                          itemCount: _alerts.length,
                          itemBuilder: (context, index) {
                            final alert = _alerts[index];
                            bool isSelected =
                                !isMobile &&
                                _selectedAlert?['id'] == alert['id'];
                            bool isUnread = !(alert['is_read'] ?? false);

                            Color schoolBrandColor = getSchoolColor(
                              alert['schools'],
                              primaryColor,
                            );
                            String type = (alert['type'] ?? '')
                                .toString()
                                .toLowerCase();

                            Color iconColor = isUnread
                                ? schoolBrandColor
                                : Colors.grey.shade400;
                            Color iconBg = isUnread
                                ? schoolBrandColor.withValues(alpha: 0.1)
                                : (isDark
                                      ? Colors.white10
                                      : Colors.grey.shade100);
                            IconData badgeIcon = Icons.notifications_rounded;

                            if (type.contains('urgent')) {
                              iconColor = isUnread
                                  ? Colors.redAccent
                                  : Colors.grey.shade400;
                              iconBg = isUnread
                                  ? Colors.redAccent.withValues(alpha: 0.1)
                                  : (isDark
                                        ? Colors.white10
                                        : Colors.grey.shade100);
                              badgeIcon = Icons.warning_rounded;
                            } else if (type.contains('teacher')) {
                              iconColor = isUnread
                                  ? Colors.purple
                                  : Colors.grey.shade400;
                              iconBg = isUnread
                                  ? Colors.purple.withValues(alpha: 0.1)
                                  : (isDark
                                        ? Colors.white10
                                        : Colors.grey.shade100);
                              badgeIcon = Icons.school_rounded;
                            }

                            String timeAgo = alert['created_at'] != null
                                ? DateFormat(
                                    'MMM d',
                                  ).format(DateTime.parse(alert['created_at']))
                                : '';

                            return GestureDetector(
                              onTap: () => _markAsRead(alert, isMobile),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? schoolBrandColor.withValues(alpha: 0.05)
                                      : (isDark
                                            ? const Color(0xFF1E1E1E)
                                            : Colors.white),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: isSelected
                                        ? schoolBrandColor.withValues(
                                            alpha: 0.5,
                                          )
                                        : (isDark
                                              ? Colors.white10
                                              : Colors.grey.shade200),
                                    width: isSelected ? 1.5 : 1.0,
                                  ),
                                  boxShadow: isSelected
                                      ? [
                                          BoxShadow(
                                            color: schoolBrandColor.withValues(
                                              alpha: 0.1,
                                            ),
                                            blurRadius: 15,
                                            offset: const Offset(0, 5),
                                          ),
                                        ]
                                      : [
                                          BoxShadow(
                                            color: Colors.black.withValues(
                                              alpha: 0.02,
                                            ),
                                            blurRadius: 8,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      margin: const EdgeInsets.only(top: 4),
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: iconBg,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        badgeIcon,
                                        color: iconColor,
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  alert['title'] ?? 'Notice',
                                                  style: TextStyle(
                                                    fontWeight: isUnread
                                                        ? FontWeight.w900
                                                        : FontWeight.w600,
                                                    fontSize: 15,
                                                    color: textColor,
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Text(
                                                timeAgo,
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: isUnread
                                                      ? schoolBrandColor
                                                      : Colors.grey.shade500,
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
                                                  ? (isDark
                                                        ? Colors.white70
                                                        : Colors.black87)
                                                  : Colors.grey.shade500,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );

        if (isMobile) {
          return Scaffold(backgroundColor: bgColor, body: inboxList);
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
                        child: Text(
                          "Select an announcement to read",
                          style: TextStyle(color: Colors.grey.shade500),
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

    return Container(
      color: isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(40, 40, 40, 30),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              border: Border(
                bottom: BorderSide(
                  color: isDark ? Colors.white10 : Colors.grey.shade200,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: schoolColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: schoolColor.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Text(
                        type.replaceAll('_', ' ').toUpperCase(),
                        style: TextStyle(
                          color: schoolColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        dateStr,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  alert['title'] ?? 'Notice',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                    letterSpacing: -0.5,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: isDark
                          ? Colors.white10
                          : Colors.grey.shade100,
                      backgroundImage: alert['schools']?['logo_url'] != null
                          ? NetworkImage(alert['schools']!['logo_url'])
                          : null,
                      child: alert['schools']?['logo_url'] == null
                          ? Icon(Icons.school, size: 18, color: schoolColor)
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
                              color: Colors.grey.shade500,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            alert['schools']?['name'] ??
                                'School Administration',
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black87,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(40),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                  border: Border.all(
                    color: isDark ? Colors.white10 : Colors.white,
                    width: 2,
                  ),
                ),
                child: Text(
                  alert['message'] ?? '',
                  softWrap: true,
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.8,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
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
    Color bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text(
          "Announcement",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        foregroundColor: isDark ? Colors.white : Colors.black,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: isDark ? Colors.white : Colors.black),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(
            color: isDark ? Colors.white10 : Colors.grey.shade200,
            height: 1.0,
          ),
        ),
      ),
      body: _TeacherAlertsScreenState.buildDetailPane(
        alert,
        primaryColor,
        isDark,
      ),
    );
  }
}
