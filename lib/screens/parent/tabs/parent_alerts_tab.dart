import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ParentAlertsTab extends StatelessWidget {
  final List<Map<String, dynamic>> alerts;
  final VoidCallback onRefresh;

  const ParentAlertsTab({
    super.key,
    required this.alerts,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color primaryColor = Theme.of(context).primaryColor;

    return SafeArea(
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              border: Border(
                bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.1)),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.notifications_active_rounded,
                    color: primaryColor,
                  ),
                ),
                const SizedBox(width: 15),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Notifications",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    Text(
                      "Stay updated with school announcements",
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              color: primaryColor,
              onRefresh: () async => onRefresh(),
              child: alerts.isEmpty
                  ? ListView(
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.2,
                        ),
                        Icon(
                          Icons.notifications_off_rounded,
                          size: 80,
                          color: Colors.grey[300],
                        ),
                        const SizedBox(height: 15),
                        Center(
                          child: Text(
                            "No new alerts from the school.",
                            style: TextStyle(color: Colors.grey[500]),
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(20),
                      itemCount: alerts.length,
                      itemBuilder: (ctx, i) {
                        final alert = alerts[i];
                        final school = alert['schools'];

                        Color alertColor = primaryColor;
                        IconData icon = Icons.notifications;
                        String type = (alert['type'] ?? '')
                            .toString()
                            .toLowerCase();

                        if (type.contains('fee') ||
                            type.contains('finance') ||
                            type.contains('urgent')) {
                          alertColor = Colors.orange;
                          icon = Icons.account_balance_wallet;
                        } else if (type.contains('academic')) {
                          alertColor = Colors.blue;
                          icon = Icons.school;
                        }

                        return Card(
                          color: isDark
                              ? const Color(0xFF1E1E1E)
                              : Colors.white,
                          margin: const EdgeInsets.only(bottom: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                            side: BorderSide(
                              color: alertColor.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(icon, color: alertColor, size: 20),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        alert['title'] ?? 'Notice',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          color: alertColor,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  alert['message'] ?? '',
                                  style: const TextStyle(fontSize: 14),
                                ),
                                const SizedBox(height: 15),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      school['name'] ?? '',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    Text(
                                      alert['created_at'] != null
                                          ? DateFormat(
                                              'MMM dd, hh:mm a',
                                            ).format(
                                              DateTime.parse(
                                                alert['created_at'],
                                              ),
                                            )
                                          : '',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
