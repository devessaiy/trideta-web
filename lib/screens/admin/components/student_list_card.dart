import 'package:flutter/material.dart';
import 'package:trideta_v2/screens/admin/student_profile_screen.dart';
import 'package:trideta_v2/widgets/trideta_ui_kit.dart';

class StudentListCard extends StatelessWidget {
  final dynamic student;
  final bool isDark;
  final Color primaryColor;
  final bool isSelected;
  final bool isSelecting;
  final ValueChanged<String> onToggleSelection;
  final VoidCallback onRefresh;

  const StudentListCard({
    super.key,
    required this.student,
    required this.isDark,
    required this.primaryColor,
    required this.isSelected,
    required this.isSelecting,
    required this.onToggleSelection,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    String sId = student['id'].toString();
    String fName = student['first_name']?.toString() ?? "";
    String lName = student['last_name']?.toString() ?? "";
    String admNo = student['admission_no']?.toString() ?? "N/A";
    String gender = student['gender']?.toString() ?? "Unknown";
    String classLevel = student['class_level']?.toString() ?? "Unassigned";

    String initial = fName.isNotEmpty ? fName[0].toUpperCase() : "?";
    String displayFullName = "$lName $fName".trim();
    String avatarUrl = student['passport_url']?.toString() ?? "";

    final BorderRadius br = BorderRadius.circular(26);

    return Container(
      decoration: BoxDecoration(
        color: isSelected
            ? PUi.tint(primaryColor, isDark, 0.08)
            : PUi.surface(isDark),
        borderRadius: br,
        border: Border.all(
          color: isSelected
              ? primaryColor.withValues(alpha: 0.6)
              : PUi.border(isDark),
          width: isSelected ? 1.6 : 1,
        ),
        boxShadow: PUi.softShadow(isDark),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: br,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onLongPress: () {
            if (!isSelecting) {
              onToggleSelection(sId);
            }
          },
          onTap: () {
            if (isSelecting) {
              onToggleSelection(sId);
            } else {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => StudentProfileScreen(
                    name: displayFullName,
                    id: sId,
                    studentClass: classLevel,
                    imagePath: avatarUrl.isNotEmpty ? avatarUrl : null,
                    parentPhone: student['parent_phone'],
                    parentEmail: student['parent_email'],
                  ),
                ),
              ).then((_) => onRefresh());
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Stack(
                  children: [
                    PAvatar(
                      initial: initial,
                      imageUrl: avatarUrl,
                      radius: 24,
                      ringColor: primaryColor,
                    ),
                    if (isSelected)
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: PUi.surface(isDark),
                              width: 2,
                            ),
                          ),
                          child: const Icon(
                            Icons.check,
                            size: 12,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        displayFullName.toUpperCase(),
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14.5,
                          color: PUi.ink(isDark),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Icon(
                            Icons.badge_rounded,
                            size: 14,
                            color: PUi.muted(isDark),
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              admNo,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: PUi.muted(isDark),
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Icon(
                            Icons.person_rounded,
                            size: 14,
                            color: PUi.muted(isDark),
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              gender,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: PUi.muted(isDark),
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                isSelecting
                    ? Checkbox(
                        value: isSelected,
                        activeColor: primaryColor,
                        shape: const CircleBorder(),
                        onChanged: (_) => onToggleSelection(sId),
                      )
                    : Icon(
                        Icons.chevron_right_rounded,
                        color: PUi.muted(isDark),
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
