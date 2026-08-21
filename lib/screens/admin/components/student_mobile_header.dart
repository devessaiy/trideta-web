import 'package:flutter/material.dart';
import 'student_quick_actions_box.dart';

class StudentMobileHeader extends StatelessWidget {
  final Color primaryColor;
  final bool isDark;
  final int totalStudents;
  final int maleCount;
  final int femaleCount;
  final VoidCallback onRefresh;

  const StudentMobileHeader({
    super.key,
    required this.primaryColor,
    required this.isDark,
    required this.totalStudents,
    required this.maleCount,
    required this.femaleCount,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 🚨 UI FIX: Replaced massive gradient card with a sleek, flat ListTile
        InkWell(
          onTap: null, // Keeps the layout structure standard
          child: Column(
            children: [
              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 8,
                ),
                leading: CircleAvatar(
                  radius: 26,
                  backgroundColor: primaryColor.withValues(alpha: 0.1),
                  child: Icon(
                    Icons.analytics_rounded,
                    color: primaryColor,
                    size: 28,
                  ),
                ),
                title: Text(
                  "Total Enrolled: $totalStudents",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Text(
                    "Males: $maleCount  •  Females: $femaleCount",
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                  ),
                ),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    "Active",
                    style: TextStyle(
                      color: Colors.green,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 60, right: 4),
                child: Divider(
                  height: 1,
                  color: isDark ? Colors.white10 : Colors.grey.shade200,
                ),
              ),
            ],
          ),
        ),

        // 🚨 The Quick Actions Box flows seamlessly underneath
        StudentQuickActionsBox(
          primaryColor: primaryColor,
          isDark: isDark,
          onRefresh: onRefresh,
        ),
      ],
    );
  }
}
