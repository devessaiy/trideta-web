import 'package:flutter/material.dart';
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
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 28, color: color),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.white70 : Colors.grey.shade600,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 18,
                  color: color,
                  fontWeight: FontWeight.w900,
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
    return Container(
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 🚨 FIXED: Title updated to "Status Card"
                Text(
                  "Status Card",
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "Manage enrollments, assign classes, and access full academic records across the institution.",
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.white70 : Colors.grey.shade600,
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
          const SizedBox(width: 30),
          StudentQuickActionsBox(
            primaryColor: primaryColor,
            isDark: isDark,
            onRefresh: onRefresh,
          ),
        ],
      ),
    );
  }
}
