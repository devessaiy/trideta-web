import 'package:flutter/material.dart';
import 'package:trideta_v2/widgets/trideta_ui_kit.dart';
import 'student_quick_actions_box.dart';

class StudentDesktopHeader extends StatelessWidget {
  final Color primaryColor;
  final bool isDark;
  final int totalStudents;
  final int maleCount;
  final int femaleCount;
  final VoidCallback onRefresh;

  const StudentDesktopHeader({
    super.key,
    required this.primaryColor,
    required this.isDark,
    required this.totalStudents,
    required this.maleCount,
    required this.femaleCount,
    required this.onRefresh,
  });

  Widget _buildDesktopStatPill(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: PUi.tint(color, isDark, 0.1),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 26, color: color),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: PUi.muted(isDark),
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 20,
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: PCard(
            radius: 30,
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Status Card", style: PUi.title(isDark, size: 28)),
                const SizedBox(height: 8),
                Text(
                  "Manage enrollments, assign classes, and access full academic records across the institution.",
                  style: TextStyle(
                    fontSize: 14,
                    color: PUi.muted(isDark),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _buildDesktopStatPill(
                      "TOTAL",
                      totalStudents.toString(),
                      Icons.groups_rounded,
                      primaryColor,
                    ),
                    _buildDesktopStatPill(
                      "MALES",
                      maleCount.toString(),
                      Icons.male_rounded,
                      Colors.blue,
                    ),
                    _buildDesktopStatPill(
                      "FEMALES",
                      femaleCount.toString(),
                      Icons.female_rounded,
                      Colors.pink,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 24),
        StudentQuickActionsBox(
          primaryColor: primaryColor,
          isDark: isDark,
          onRefresh: onRefresh,
        ),
      ],
    );
  }
}
