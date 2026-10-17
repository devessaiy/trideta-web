import 'package:flutter/material.dart';
import 'package:trideta_v2/widgets/trideta_ui_kit.dart';
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PCard(
          radius: 26,
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              PIconBadge(
                icon: Icons.analytics_rounded,
                color: primaryColor,
                size: 52,
                iconSize: 26,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Total Enrolled: $totalStudents",
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: PUi.ink(isDark),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Males: $maleCount  •  Females: $femaleCount",
                      style: TextStyle(
                        color: PUi.muted(isDark),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const PPill(text: "ACTIVE", color: Colors.green),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // The quick actions flow underneath the status tile
        StudentQuickActionsBox(
          primaryColor: primaryColor,
          isDark: isDark,
          onRefresh: onRefresh,
        ),
      ],
    );
  }
}
