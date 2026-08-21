import 'package:flutter/material.dart';
import 'package:trideta_v2/screens/admin/student_profile_screen.dart';

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

    return InkWell(
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
      child: Container(
        color: isSelected
            ? primaryColor.withValues(alpha: 0.1)
            : Colors.transparent,
        child: Column(
          children: [
            ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 4,
              ),
              leading: Stack(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: primaryColor.withValues(alpha: 0.1),
                    backgroundImage: avatarUrl.isNotEmpty
                        ? NetworkImage(avatarUrl)
                        : null,
                    child: avatarUrl.isEmpty
                        ? Text(
                            initial,
                            style: TextStyle(
                              color: primaryColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          )
                        : null,
                  ),
                  if (isSelected)
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
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
              title: Text(
                displayFullName.toUpperCase(),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Row(
                children: [
                  Icon(
                    Icons.badge_rounded,
                    size: 14,
                    color: Colors.grey.shade500,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    admNo,
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                  ),
                  const SizedBox(width: 12),
                  Icon(
                    Icons.person_rounded,
                    size: 14,
                    color: Colors.grey.shade500,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    gender,
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                  ),
                ],
              ),
              trailing: isSelecting
                  ? Checkbox(
                      value: isSelected,
                      activeColor: primaryColor,
                      shape: const CircleBorder(),
                      onChanged: (_) => onToggleSelection(sId),
                    )
                  : Icon(
                      Icons.chevron_right_rounded,
                      color: Colors.grey.shade400,
                    ),
            ),
            Padding(
              // Indented divider just like WhatsApp
              padding: const EdgeInsets.only(left: 76, right: 20),
              child: Divider(
                height: 1,
                color: isDark ? Colors.white10 : Colors.grey.shade200,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
