import 'package:flutter/material.dart';
import 'package:trideta_v2/screens/admin/student_admission_screen.dart';
import 'package:trideta_v2/screens/admin/id_card_generator_screen.dart';

class StudentQuickActionsBox extends StatelessWidget {
  final Color primaryColor;
  final bool isDark;
  final VoidCallback onRefresh;

  const StudentQuickActionsBox({
    super.key,
    required this.primaryColor,
    required this.isDark,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    bool isDesktop = MediaQuery.of(context).size.width > 800;

    return Container(
      // 🚨 FIXED: Fixed width on Desktop ensures buttons stretch perfectly side-by-side with Status Card
      width: isDesktop ? 300 : double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment
            .stretch, // 🚨 FIXED: Forces buttons to stretch full width
        children: [
          // 🚨 FIXED: Made title prominent to match Status Card
          Text(
            "Directory Tools",
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 22,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 8),

          // 🚨 FIXED: Added Description Text
          Text(
            "Quickly admit new students or generate digital identity cards.",
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white70 : Colors.grey.shade600,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),

          // 🚨 FIXED: Stacked buttons vertically
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 0,
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const StudentAdmissionScreen(),
                ),
              ).then((_) => onRefresh());
            },
            icon: const Icon(Icons.person_add_rounded, size: 18),
            label: const Text(
              "ADMIT STUDENT",
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 12,
                letterSpacing: 1.0,
              ),
            ),
          ),
          const SizedBox(height: 12),

          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: isDark
                  ? Colors.white.withValues(alpha: 0.1)
                  : primaryColor.withValues(alpha: 0.1),
              foregroundColor: isDark ? Colors.white : primaryColor,
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 0,
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const IdCardGeneratorScreen(),
                ),
              );
            },
            icon: const Icon(Icons.badge_rounded, size: 18),
            label: const Text(
              "GENERATE ID",
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 12,
                letterSpacing: 1.0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
