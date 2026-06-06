import 'package:flutter/material.dart';

class AcademicSetupWidget extends StatelessWidget {
  final List<String> activeClasses;
  final String? selectedClass;
  final String resolvedSession;
  final String resolvedTerm;
  final String? selectedDepartment;
  final String studentCategory;
  final Color primaryColor;
  final bool isDark;
  final Color cardColor;
  final Function(String) onClassChanged;
  final Function(String?) onDepartmentChanged;
  final Function(String) onCategoryChanged;

  const AcademicSetupWidget({
    super.key,
    required this.activeClasses,
    required this.selectedClass,
    required this.resolvedSession,
    required this.resolvedTerm,
    required this.selectedDepartment,
    required this.studentCategory,
    required this.primaryColor,
    required this.isDark,
    required this.cardColor,
    required this.onClassChanged,
    required this.onDepartmentChanged,
    required this.onCategoryChanged,
  });

  @override
  Widget build(BuildContext context) {
    // 🚨 SMART DETECTION: Prevents JSS from showing the Department dropdown!
    bool isSeniorSecondary =
        (selectedClass ?? "").toUpperCase().contains("SS") &&
        !(selectedClass ?? "").toUpperCase().contains("JSS");

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(
          "Academic Setup",
          Icons.school_rounded,
          primaryColor,
        ),
        const SizedBox(height: 20),
        _buildDropdown(
          "Class Designation",
          activeClasses,
          selectedClass,
          (v) => onClassChanged(v!),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: primaryColor.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: primaryColor.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Icon(Icons.auto_awesome_rounded, color: primaryColor, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Auto-Synced to $resolvedSession  •  $resolvedTerm",
                  style: TextStyle(
                    color: primaryColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),

        // 🚨 CONDITIONAL RENDER: Department logic smoothly integrates here
        if (isSeniorSecondary) ...[
          const SizedBox(height: 16),
          _buildDropdown(
            "Department (Optional)",
            ['Science', 'Art', 'Commercial'],
            selectedDepartment,
            (v) => onDepartmentChanged(v),
          ),
        ],
        const SizedBox(height: 16),
        _buildDropdown(
          "Admission Type",
          ['Regular', 'Transfer', 'Scholarship', 'Special'],
          studentCategory,
          (v) => onCategoryChanged(v!),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title, IconData icon, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 12),
            Text(
              title.toUpperCase(),
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: color,
                letterSpacing: 1.5,
                fontSize: 11,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Divider(height: 1, color: Colors.grey.withValues(alpha: 0.2)),
      ],
    );
  }

  Widget _buildDropdown(
    String hint,
    List<String> items,
    String? value,
    Function(String?) onChanged,
  ) {
    if (value != null && !items.contains(value)) items.add(value);
    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.03)
            : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: value,
          hint: Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Text(
              hint,
              style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
            ),
          ),
          icon: Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Icon(Icons.keyboard_arrow_down_rounded, color: primaryColor),
          ),
          items: items
              .map(
                (e) => DropdownMenuItem(
                  value: e,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: Text(
                      e,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
          onChanged: onChanged,
          dropdownColor: isDark ? const Color(0xFF2C2C2C) : Colors.white,
        ),
      ),
    );
  }
}
