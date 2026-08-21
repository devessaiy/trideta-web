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

    // 🚨 UI FIX: Replaced heavy buttons with sleek ListTiles matching the WhatsApp vibe
    Widget actionsList = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const StudentAdmissionScreen()),
            ).then((_) => onRefresh());
          },
          child: Column(
            children: [
              ListTile(
                contentPadding: EdgeInsets.symmetric(
                  horizontal: isDesktop ? 16 : 4,
                  vertical: 4,
                ),
                leading: CircleAvatar(
                  radius: 24,
                  backgroundColor: primaryColor.withValues(alpha: 0.1),
                  child: Icon(
                    Icons.person_add_rounded,
                    color: primaryColor,
                    size: 24,
                  ),
                ),
                title: const Text(
                  "Admit Student",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    "Enroll a new student to the system",
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                  ),
                ),
                trailing: Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.grey.shade400,
                ),
              ),
              Padding(
                padding: EdgeInsets.only(
                  left: isDesktop ? 70 : 60,
                  right: isDesktop ? 16 : 4,
                ),
                child: Divider(
                  height: 1,
                  color: isDark ? Colors.white10 : Colors.grey.shade200,
                ),
              ),
            ],
          ),
        ),
        InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const IdCardGeneratorScreen()),
            );
          },
          child: Column(
            children: [
              ListTile(
                contentPadding: EdgeInsets.symmetric(
                  horizontal: isDesktop ? 16 : 4,
                  vertical: 4,
                ),
                leading: CircleAvatar(
                  radius: 24,
                  backgroundColor: Colors.orange.withValues(alpha: 0.1),
                  child: const Icon(
                    Icons.badge_rounded,
                    color: Colors.orange,
                    size: 24,
                  ),
                ),
                title: const Text(
                  "Generate ID Card",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    "Create digital identity cards",
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                  ),
                ),
                trailing: Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.grey.shade400,
                ),
              ),
              Padding(
                padding: EdgeInsets.only(
                  left: isDesktop ? 70 : 60,
                  right: isDesktop ? 16 : 4,
                ),
                child: Divider(
                  height: 1,
                  color: isDark ? Colors.white10 : Colors.grey.shade200,
                ),
              ),
            ],
          ),
        ),
      ],
    );

    // Desktop view safely keeps its bounding container to fit the grid
    if (isDesktop) {
      return Container(
        width: 350,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isDark ? Colors.white10 : Colors.grey.shade200,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                "Directory Tools",
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ),
            const SizedBox(height: 12),
            actionsList,
          ],
        ),
      );
    }

    // Mobile natively dumps the raw flat list right under the Status tile!
    return actionsList;
  }
}
