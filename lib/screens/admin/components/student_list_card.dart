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
    final String fullName = "${student['first_name']} ${student['last_name']}";
    final String classLevel = student['class_level'] ?? 'Unassigned';
    final String? photoUrl = student['passport_url'];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected
              ? primaryColor
              : (isDark ? Colors.white10 : Colors.grey.shade200),
          width: isSelected ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      // 🚨 FIXED: Wrapped the ListTile in a transparent Material widget to fix the ink splash warning
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
          onTap: () {
            if (isSelecting) {
              onToggleSelection(student['id']);
            } else {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => StudentProfileScreen(
                    name: student['first_name'] ?? '',
                    id: student['id'] ?? '',
                    studentClass: student['class'] ?? '',
                    imagePath: student['photo_url'],
                    parentPhone: student['parent_phone'],
                    parentEmail: student['parent_email'],
                  ),
                ),
              ).then((_) => onRefresh());
            }
          },
          onLongPress: () => onToggleSelection(student['id']),
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isSelecting)
                Checkbox(
                  value: isSelected,
                  onChanged: (_) => onToggleSelection(student['id']),
                  activeColor: primaryColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              CircleAvatar(
                radius: 24,
                backgroundColor: primaryColor.withValues(alpha: 0.1),
                backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                    ? NetworkImage(photoUrl)
                    : null,
                child: photoUrl == null || photoUrl.isEmpty
                    ? Icon(Icons.person_rounded, color: primaryColor)
                    : null,
              ),
            ],
          ),
          title: Text(
            fullName,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              "ID: ${student['admission_no'] ?? 'N/A'} • $classLevel",
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade500,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          trailing: Icon(
            Icons.chevron_right_rounded,
            color: Colors.grey.shade400,
          ),
        ),
      ),
    );
  }
}
