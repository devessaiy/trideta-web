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
    if (isFetchingAcademics)
      return Center(child: TridetaLoader(color: primaryColor));

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 100),
      children: [
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                "Attendance",
                attendancePercentage,
                Icons.calendar_month_rounded,
                Colors.blue,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildStatCard(
                "Average",
                gradeAverage,
                Icons.auto_graph_rounded,
                Colors.purple,
              ),
            ),
          ],
        ),
        const SizedBox(height: 30),
        const Text(
          "SUBJECT GRADES",
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 11,
            color: Colors.grey,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 16),
        if (subjectGrades.isEmpty)
          Container(
            padding: const EdgeInsets.all(30),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark ? Colors.white10 : Colors.grey.shade200,
              ),
            ),
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
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark ? Colors.white10 : Colors.grey.shade200,
              ),
            ),
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
                      Divider(
                        height: 1,
                        color: isDark ? Colors.white10 : Colors.grey.shade100,
                      ),
                  ],
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildStatCard(String title, String val, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade500,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              val,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGradeTile(String name, String score, Color color) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
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
