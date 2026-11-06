import 'package:flutter/material.dart';
import 'package:trideta_v2/widgets/trideta_loader.dart';
import 'package:trideta_v2/widgets/trideta_ui_kit.dart';

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
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 70),
        child: Center(child: TridetaLoader(color: primaryColor)),
      );
    }

    // Inline (non-scrolling) list: the whole profile page scrolls as one.
    return ListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _buildStatCard(
                "Attendance",
                attendancePercentage,
                Icons.calendar_month_rounded,
                Colors.blue,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _buildStatCard(
                "Grade Average",
                gradeAverage,
                Icons.auto_graph_rounded,
                Colors.purple,
              ),
            ),
          ],
        ),
        const SizedBox(height: 26),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text("SUBJECT GRADES", style: PUi.sectionLabel(isDark)),
        ),
        if (subjectGrades.isEmpty)
          PCard(
            radius: 26,
            padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
            child: SizedBox(
              width: double.infinity,
              child: Center(
                child: Text(
                  "No scores recorded yet.",
                  style: TextStyle(
                    color: PUi.muted(isDark),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          )
        else
          PCard(
            radius: 26,
            padding: EdgeInsets.zero,
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
                      (double.tryParse(gradeData['score'].toString()) ?? 0)
                          .clamp(0, 100)
                          .toDouble(),
                    ),
                    if (gradeData != subjectGrades.last)
                      Divider(
                        height: 1,
                        color: PUi.border(isDark),
                        indent: 20,
                        endIndent: 20,
                      ),
                  ],
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  // "92.5% (37/40 Days)" is shown as a big value with a small caption.
  Widget _buildStatCard(String title, String val, IconData icon, Color color) {
    String main = val;
    String? sub;
    final int cut = val.indexOf(' (');
    if (cut > 0 && val.endsWith(')')) {
      main = val.substring(0, cut);
      sub = val.substring(cut + 2, val.length - 1);
    }

    return PCard(
      radius: 26,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PIconBadge(icon: icon, color: color, size: 42, iconSize: 20),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              fontSize: 12.5,
              color: PUi.muted(isDark),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              main,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
                color: PUi.ink(isDark),
              ),
            ),
          ),
          if (sub != null) ...[
            const SizedBox(height: 2),
            Text(
              sub,
              style: TextStyle(fontSize: 12, color: PUi.muted(isDark)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGradeTile(
    String name,
    String score,
    Color color,
    double scoreValue,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                    color: textColor,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              PPill(text: score, color: color),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: scoreValue / 100,
              minHeight: 5,
              backgroundColor: PUi.tint(color, isDark, 0.1),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }
}
