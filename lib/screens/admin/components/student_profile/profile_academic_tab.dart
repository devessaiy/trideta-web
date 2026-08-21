import 'package:flutter/material.dart';
import 'package:trideta_v2/widgets/trideta_loader.dart';

class ProfileAcademicTab extends StatelessWidget {
  final bool isFetchingAcademics;
  final String attendancePercentage;
  final String gradeAverage;
  final List<Map<String, dynamic>> subjectGrades;
  final Color primaryColor;
  final Color cardColor;
  final Color textColor;
  final bool isDark;

  const ProfileAcademicTab({
    super.key,
    required this.isFetchingAcademics,
    required this.attendancePercentage,
    required this.gradeAverage,
    required this.subjectGrades,
    required this.primaryColor,
    required this.cardColor,
    required this.textColor,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    if (isFetchingAcademics) {
      return Center(child: TridetaLoader(color: primaryColor));
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 100),
      children: [
        // 🚨 UI FIX: Pure flat ListTiles matching Contact Info
        ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 8,
          ),
          leading: const Icon(
            Icons.calendar_month_rounded,
            color: Colors.blue,
            size: 28,
          ),
          title: const Text(
            "Attendance",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          trailing: Text(
            attendancePercentage,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.blue,
              fontSize: 16,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 72, right: 24),
          child: Divider(
            height: 1,
            color: isDark ? Colors.white10 : Colors.grey.shade200,
          ),
        ),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 8,
          ),
          leading: const Icon(
            Icons.auto_graph_rounded,
            color: Colors.purple,
            size: 28,
          ),
          title: const Text(
            "Grade Average",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          trailing: Text(
            gradeAverage,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.purple,
              fontSize: 16,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 72, right: 24),
          child: Divider(
            height: 1,
            color: isDark ? Colors.white10 : Colors.grey.shade200,
          ),
        ),

        Container(
          height: 12,
          color: isDark ? Colors.black : Colors.grey.shade100,
        ),

        const Padding(
          padding: EdgeInsets.fromLTRB(24, 24, 24, 8),
          child: Text(
            "SUBJECT GRADES",
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 12,
              color: Colors.grey,
              letterSpacing: 1.2,
            ),
          ),
        ),
        if (subjectGrades.isEmpty)
          Container(
            padding: const EdgeInsets.all(30),
            color: cardColor,
            child: Center(
              child: Text(
                "No scores recorded yet.",
                style: TextStyle(
                  color: Colors.grey.shade500,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          )
        else
          Container(
            color: cardColor,
            child: Column(
              children: subjectGrades.map((gradeData) {
                Color gColor = Colors.grey;
                if (gradeData['grade'] == 'A') gColor = Colors.green;
                if (gradeData['grade'] == 'B') gColor = Colors.blue;
                if (gradeData['grade'] == 'C') gColor = Colors.orange;
                if (gradeData['grade'] == 'P') gColor = Colors.purple;
                if (gradeData['grade'] == 'F') gColor = Colors.red;
                return Column(
                  children: [
                    _buildGradeTile(
                      gradeData['subject'],
                      "${gradeData['score']} (${gradeData['grade']})",
                      gColor,
                    ),
                    if (gradeData != subjectGrades.last)
                      Padding(
                        padding: const EdgeInsets.only(left: 24, right: 24),
                        child: Divider(
                          height: 1,
                          color: isDark ? Colors.white10 : Colors.grey.shade200,
                        ),
                      ),
                  ],
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildGradeTile(String name, String score, Color color) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      title: Text(
        name,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 14,
          color: textColor,
        ),
      ),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          score,
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: color,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
