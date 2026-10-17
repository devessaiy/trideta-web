import 'package:flutter/material.dart';
import 'package:trideta_v2/screens/admin/student_admission_screen.dart';
import 'package:trideta_v2/screens/admin/id_card_generator_screen.dart';
import 'package:trideta_v2/widgets/trideta_ui_kit.dart';

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

  Widget _action({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return PCard(
      radius: 24,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      onTap: onTap,
      child: Row(
        children: [
          PIconBadge(icon: icon, color: color, size: 46, iconSize: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15.5,
                    color: PUi.ink(isDark),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 13, color: PUi.muted(isDark)),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: PUi.muted(isDark)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isDesktop = MediaQuery.of(context).size.width > 800;

    Widget actionsList = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _action(
          icon: Icons.person_add_rounded,
          color: primaryColor,
          title: "Admit Student",
          subtitle: "Enroll a new student to the system",
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const StudentAdmissionScreen()),
            ).then((_) => onRefresh());
          },
        ),
        const SizedBox(height: 12),
        _action(
          icon: Icons.badge_rounded,
          color: Colors.orange,
          title: "Generate ID Card",
          subtitle: "Create digital identity cards",
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const IdCardGeneratorScreen()),
            );
          },
        ),
      ],
    );

    // Desktop view keeps a fixed-width block to sit beside the stats
    if (isDesktop) {
      return SizedBox(
        width: 350,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 12),
              child: Text("DIRECTORY TOOLS", style: PUi.sectionLabel(isDark)),
            ),
            actionsList,
          ],
        ),
      );
    }

    // Mobile shows the two actions as cards under the status tile
    return actionsList;
  }
}
