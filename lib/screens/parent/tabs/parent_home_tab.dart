import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ParentHomeTab extends StatelessWidget {
  final String parentName;
  final String parentEmail;
  final String primarySession;
  final List<Map<String, dynamic>> myChildren;
  final List<Map<String, dynamic>> alerts;
  final bool showAlertBrief;
  final VoidCallback onRefresh;
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

    // Absolute white background for the premium feel
    Color bgColor = isDark ? const Color(0xFF121212) : Colors.white;
    Color textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    Color subTextColor = isDark ? Colors.white70 : const Color(0xFF9098B1);

    // Calculate unread alerts
    List<Map<String, dynamic>> unreadAlerts = alerts
        .where((a) => !(a['is_read'] ?? false))
        .toList();
    int unreadCount = unreadAlerts.length;

    // Grab the first name for the greeting
    String firstName = parentName.split(' ').first;
    if (firstName.isEmpty) firstName = "Parent";

    // Split alerts: 1 for the prominent popup, the rest for the bottom list
    Map<String, dynamic>? latestAlert = alerts.isNotEmpty ? alerts.first : null;
    List<Map<String, dynamic>> recentAlerts = alerts.length > 1
        ? alerts.sublist(1)
        : [];

    return SafeArea(
      child: Container(
        color: bgColor,
        child: RefreshIndicator(
          color: primaryColor,
          onRefresh: () async => onRefresh(),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. HEADER (Profile Picture & Notification Bell)
                _buildHeader(
                  firstName,
                  unreadCount,
                  primaryColor,
                  textColor,
                  bgColor,
                ),
                const SizedBox(height: 30),

                // 2. MAIN MASTER CARD (Glassy & Premium)
                _buildGlassyMasterCard(primaryColor, unreadCount),
                const SizedBox(height: 25),

                // 3. PREMIUM LATEST ALERT POPUP (Replaced the pill tabs)
                if (latestAlert != null) ...[
                  _buildPremiumLatestAlert(
                    latestAlert,
                    primaryColor,
                    isDark,
                    textColor,
                    subTextColor,
                  ),
                  const SizedBox(height: 30),
                ],

                // 4. RECENT ANNOUNCEMENTS LIST
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Recent Announcements",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                    GestureDetector(
                      onTap: () => onNavigate(2),
                      child: Text(
                        "See all",
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: primaryColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                _buildRecentAlertsList(
                  recentAlerts,
                  primaryColor,
                  isDark,
                  textColor,
                  subTextColor,
                ),
              ],
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
    Color textColor,
    Color bgColor,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            // 🚨 Replaced the Hamburger Menu with a Profile Picture Placeholder
            CircleAvatar(
              radius: 22,
              backgroundColor: primaryColor.withValues(alpha: 0.1),
              child: Icon(Icons.person_rounded, color: primaryColor, size: 24),
            ),
            const SizedBox(width: 15),
            Text(
              "Hello, $firstName",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: textColor,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),

        // 🚨 Upgraded Notification Bell with crisp Red Badge
        GestureDetector(
          onTap: () => onNavigate(2),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.notifications_rounded,
                  color: primaryColor,
                  size: 24,
                ),
              ),
              if (unreadCount > 0)
                Positioned(
                  top: -2,
                  right: -2,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: Colors.redAccent,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: bgColor,
                        width: 2.5,
                      ), // Cutout effect
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

  Widget _buildGlassyMasterCard(Color primaryColor, int unreadCount) {
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias, // Ensures the geometric circles stay inside
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [primaryColor.withValues(alpha: 0.85), primaryColor],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.2),
          width: 1.5,
        ),
      ),
      child: Stack(
        children: [
          // 🚨 Decorative geometric overlays for the "Glassy/Premium" feel
          Positioned(
            right: -30,
            top: -30,
            child: CircleAvatar(
              radius: 70,
              backgroundColor: Colors.white.withValues(alpha: 0.1),
            ),
          ),
          Positioned(
            left: -20,
            bottom: -40,
            child: CircleAvatar(
              radius: 60,
              backgroundColor: Colors.white.withValues(alpha: 0.05),
            ),
          ),

          // Card Content
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text(
                  "Current Academic Session",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  primarySession,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 38,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 30),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildMasterCardStat(
                      "Linked Wards",
                      myChildren.length.toString(),
                    ),
                    Container(
                      height: 30,
                      width: 1,
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                    _buildMasterCardStat(
                      "Total Alerts",
                      alerts.length.toString(),
                    ),
                    Container(
                      height: 30,
                      width: 1,
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                    _buildMasterCardStat("Unread", unreadCount.toString()),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMasterCardStat(String label, String value) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildPremiumLatestAlert(
    Map<String, dynamic> alert,
    Color primaryColor,
    bool isDark,
    Color textColor,
    Color subTextColor,
  ) {
    bool isUnread = !(alert['is_read'] ?? false);

    return GestureDetector(
      onTap: () => onNavigate(2), // Navigate to alerts tab
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
          border: Border.all(
            color: isUnread
                ? primaryColor.withValues(alpha: 0.3)
                : (isDark ? Colors.white10 : Colors.grey.shade100),
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.campaign_rounded,
                color: primaryColor,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        "Latest Announcement",
                        style: TextStyle(
                          color: primaryColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                      if (isUnread) ...[
                        const SizedBox(width: 8),
                        Container(
                          width: 6,
                          height: 6,
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
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: textColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    alert['message'] ?? 'Tap to read more.',
                    style: TextStyle(fontSize: 13, color: subTextColor),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentAlertsList(
    List<Map<String, dynamic>> recentAlerts,
    Color primaryColor,
    bool isDark,
    Color textColor,
    Color subTextColor,
  ) {
    if (recentAlerts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40.0),
          child: Text(
            "No older announcements.",
            style: TextStyle(color: subTextColor),
          ),
        ),
      );
    }

    // Show only the next 3 alerts to keep it clean
    int displayCount = recentAlerts.length > 3 ? 3 : recentAlerts.length;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade100,
          width: 1.5,
        ),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: displayCount,
        separatorBuilder: (context, index) => Divider(
          height: 1,
          color: isDark ? Colors.white10 : Colors.grey.shade100,
          indent: 20,
          endIndent: 20,
        ),
        itemBuilder: (context, index) {
          final alert = recentAlerts[index];
          bool isUnread = !(alert['is_read'] ?? false);

          String type = (alert['type'] ?? '').toString().toLowerCase();
          Color iconBg = primaryColor.withValues(alpha: 0.1);
          Color iconColor = primaryColor;
          IconData icon = Icons.notifications_rounded;

          if (type.contains('urgent') || type.contains('fee')) {
            iconBg = Colors.red.withValues(alpha: 0.1);
            iconColor = Colors.red;
            icon = Icons.warning_rounded;
          } else if (type.contains('academic')) {
            iconBg = Colors.green.withValues(alpha: 0.1);
            iconColor = Colors.green;
            icon = Icons.school_rounded;
          }

          String dateStr = "";
          if (alert['created_at'] != null) {
            dateStr = DateFormat(
              'MMMM d, yyyy',
            ).format(DateTime.parse(alert['created_at']));
          }

          return ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 12,
            ),
            leading: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            title: Text(
              alert['title'] ?? 'Announcement',
              style: TextStyle(
                fontWeight: isUnread ? FontWeight.bold : FontWeight.w600,
                fontSize: 14,
                color: textColor,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Text(
                dateStr,
                style: TextStyle(fontSize: 12, color: subTextColor),
              ),
            ),
            trailing: isUnread
                ? Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      "New",
                      style: TextStyle(
                        color: Colors.orange,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                : Icon(
                    Icons.check_circle_rounded,
                    color: Colors.green.shade400,
                    size: 18,
                  ),
            onTap: () => onNavigate(2),
          );
        },
      ),
    );
  }
}
