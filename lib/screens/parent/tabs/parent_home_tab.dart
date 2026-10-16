import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:trideta_v2/screens/parent/parent_ui_kit.dart';

class ParentHomeTab extends StatelessWidget {
  final String parentName;
  final String parentEmail;
  final String primarySession;
  final List<Map<String, dynamic>> myChildren;
  final List<Map<String, dynamic>> alerts;
  final bool showAlertBrief;
  final Future<void> Function() onRefresh;
  final Function(int) onNavigate;
  final Function() onDismissAlert;

  const ParentHomeTab({
    super.key,
    required this.parentName,
    required this.parentEmail,
    required this.primarySession,
    required this.myChildren,
    required this.alerts,
    required this.showAlertBrief,
    required this.onRefresh,
    required this.onNavigate,
    required this.onDismissAlert,
  });

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color primaryColor = Theme.of(context).primaryColor;
    Color bgColor = PUi.bg(isDark);

    // Calculate unread alerts
    List<Map<String, dynamic>> unreadAlerts = alerts
        .where((a) => !(a['is_read'] ?? false))
        .toList();
    int unreadCount = unreadAlerts.length;

    // Grab the first name for the greeting
    String firstName = parentName.split(' ').first;
    if (firstName.isEmpty) firstName = "Parent";

    // Split alerts: 1 for the prominent card, the rest for the list
    Map<String, dynamic>? latestAlert = alerts.isNotEmpty ? alerts.first : null;
    List<Map<String, dynamic>> recentAlerts = alerts.length > 1
        ? alerts.sublist(1)
        : [];

    return Container(
      color: bgColor,
      child: PBackdrop(
        accent: primaryColor,
        child: SafeArea(
          child: RefreshIndicator(
            color: primaryColor,
            onRefresh: onRefresh,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final bool wide = constraints.maxWidth >= 820;

                final header = _buildHeader(
                  firstName,
                  unreadCount,
                  primaryColor,
                  isDark,
                  bgColor,
                );
                final hero = _buildHeroCard(primaryColor, unreadCount);
                final latest = latestAlert == null
                    ? null
                    : _buildLatestAlert(
                        latestAlert,
                        primaryColor,
                        isDark,
                      );
                final announcements = _buildAnnouncementsSection(
                  recentAlerts,
                  primaryColor,
                  isDark,
                );

                final Widget body = wide
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          header,
                          const SizedBox(height: 32),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 5,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    hero,
                                    if (latest != null) ...[
                                      const SizedBox(height: 24),
                                      latest,
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 28),
                              Expanded(flex: 6, child: announcements),
                            ],
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          header,
                          const SizedBox(height: 24),
                          hero,
                          if (latest != null) ...[
                            const SizedBox(height: 20),
                            latest,
                          ],
                          const SizedBox(height: 28),
                          announcements,
                        ],
                      );

                return SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.symmetric(
                    horizontal: wide ? 40 : 20,
                    vertical: wide ? 32 : 16,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1100),
                      child: body,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // WIDGET BUILDERS
  // ===========================================================================

  Widget _buildHeader(
    String firstName,
    int unreadCount,
    Color primaryColor,
    bool isDark,
    Color bgColor,
  ) {
    final String initial = firstName.isNotEmpty
        ? firstName[0].toUpperCase()
        : 'P';

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: PUi.tint(primaryColor, isDark, 0.14),
                child: Text(
                  initial,
                  style: TextStyle(
                    color: primaryColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  "Hello, $firstName",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PUi.title(isDark, size: 26),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),

        // Notification bell with unread badge
        GestureDetector(
          onTap: () => onNavigate(2),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: PUi.surface(isDark),
                  shape: BoxShape.circle,
                  border: Border.all(color: PUi.border(isDark)),
                ),
                child: Icon(
                  Icons.notifications_rounded,
                  color: primaryColor,
                  size: 24,
                ),
              ),
              if (unreadCount > 0)
                Positioned(
                  top: -3,
                  right: -3,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: Colors.redAccent,
                      shape: BoxShape.circle,
                      border: Border.all(color: bgColor, width: 2.5),
                    ),
                    child: Text(
                      unreadCount > 9 ? '9+' : unreadCount.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeroCard(Color primaryColor, int unreadCount) {
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [primaryColor.withValues(alpha: 0.88), primaryColor],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withValues(alpha: 0.28),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Faint study illustration (top-right)
          Positioned(
            top: 6,
            right: 8,
            width: 150,
            child: IgnorePointer(
              child: AspectRatio(
                aspectRatio: 300 / 190,
                child: CustomPaint(
                  painter: PScenePainter(
                    scene: PScene.hero,
                    line: Colors.white.withValues(alpha: 0.4),
                    tint: Colors.white.withValues(alpha: 0.08),
                    paper: primaryColor,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Current Academic Session",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  primarySession,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 26),
                Row(
                  children: [
                    Expanded(
                      child: _buildHeroStat(
                        "Linked Wards",
                        myChildren.length.toString(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildHeroStat(
                        "Total Alerts",
                        alerts.length.toString(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildHeroStat("Unread", unreadCount.toString()),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroStat(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              label,
              maxLines: 1,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLatestAlert(
    Map<String, dynamic> alert,
    Color primaryColor,
    bool isDark,
  ) {
    bool isUnread = !(alert['is_read'] ?? false);

    return PCard(
      radius: 26,
      onTap: () => onNavigate(2), // Navigate to alerts tab
      borderColor: isUnread
          ? primaryColor.withValues(alpha: 0.4)
          : PUi.border(isDark),
      borderWidth: isUnread ? 1.5 : 1,
      child: Row(
        children: [
          PIconBadge(
            icon: Icons.campaign_rounded,
            color: primaryColor,
            size: 50,
            iconSize: 24,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      "LATEST ANNOUNCEMENT",
                      style: TextStyle(
                        color: primaryColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),
                    if (isUnread) ...[
                      const SizedBox(width: 8),
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: Colors.redAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  alert['title'] ?? 'Notice',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: PUi.ink(isDark),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  alert['message'] ?? 'Tap to read more.',
                  style: TextStyle(fontSize: 13, color: PUi.muted(isDark)),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.chevron_right_rounded, color: PUi.muted(isDark)),
        ],
      ),
    );
  }

  Widget _buildAnnouncementsSection(
    List<Map<String, dynamic>> recentAlerts,
    Color primaryColor,
    bool isDark,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              "Recent Announcements",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                color: PUi.ink(isDark),
              ),
            ),
            GestureDetector(
              onTap: () => onNavigate(2),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  "See all",
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: primaryColor,
                    decoration: TextDecoration.underline,
                    decorationColor: primaryColor,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _buildRecentAlertsList(recentAlerts, primaryColor, isDark),
      ],
    );
  }

  Widget _buildRecentAlertsList(
    List<Map<String, dynamic>> recentAlerts,
    Color primaryColor,
    bool isDark,
  ) {
    if (recentAlerts.isEmpty) {
      return PCard(
        radius: 26,
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
        child: SizedBox(
          width: double.infinity,
          child: Center(
            child: Text(
              "No older announcements.",
              style: TextStyle(color: PUi.muted(isDark)),
            ),
          ),
        ),
      );
    }

    // Show only the next 3 alerts to keep it clean
    int displayCount = recentAlerts.length > 3 ? 3 : recentAlerts.length;

    return PCard(
      radius: 26,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (int index = 0; index < displayCount; index++) ...[
            if (index > 0)
              Divider(
                height: 1,
                color: PUi.border(isDark),
                indent: 20,
                endIndent: 20,
              ),
            _buildAlertRow(recentAlerts[index], primaryColor, isDark),
          ],
        ],
      ),
    );
  }

  Widget _buildAlertRow(
    Map<String, dynamic> alert,
    Color primaryColor,
    bool isDark,
  ) {
    bool isUnread = !(alert['is_read'] ?? false);

    String type = (alert['type'] ?? '').toString().toLowerCase();
    Color iconColor = primaryColor;
    IconData icon = Icons.notifications_rounded;

    if (type.contains('urgent') || type.contains('fee')) {
      iconColor = Colors.red;
      icon = Icons.warning_rounded;
    } else if (type.contains('academic')) {
      iconColor = Colors.green;
      icon = Icons.school_rounded;
    }

    String dateStr = "";
    if (alert['created_at'] != null) {
      dateStr = DateFormat(
        'MMMM d, yyyy',
      ).format(DateTime.parse(alert['created_at']));
    }

    return InkWell(
      onTap: () => onNavigate(2),
      borderRadius: BorderRadius.circular(26),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            PIconBadge(icon: icon, color: iconColor, size: 44, iconSize: 20),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    alert['title'] ?? 'Announcement',
                    style: TextStyle(
                      fontWeight: isUnread ? FontWeight.w800 : FontWeight.w600,
                      fontSize: 14.5,
                      color: PUi.ink(isDark),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    dateStr,
                    style: TextStyle(fontSize: 12, color: PUi.muted(isDark)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            isUnread
                ? const PPill(text: "NEW", color: Colors.orange)
                : Icon(
                    Icons.check_circle_rounded,
                    color: Colors.green.shade400,
                    size: 20,
                  ),
          ],
        ),
      ),
    );
  }
}
