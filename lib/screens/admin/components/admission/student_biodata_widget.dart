import 'package:flutter/material.dart';

class StudentBiodataWidget extends StatelessWidget {
  final TextEditingController firstNameController;
  final TextEditingController middleNameController;
  final TextEditingController lastNameController;
  final TextEditingController dobController;
  final String selectedGender;
  final Function(String) onGenderChanged;
  final VoidCallback onDateTap;
  final Color primaryColor;
  final bool isDark;
  final Color cardColor;

  const StudentBiodataWidget({
    super.key,
    required this.firstNameController,
    required this.middleNameController,
    required this.lastNameController,
    required this.dobController,
    required this.selectedGender,
    required this.onGenderChanged,
    required this.onDateTap,
    required this.primaryColor,
    required this.isDark,
    required this.cardColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(
          "Student Biodata",
          Icons.badge_rounded,
          Colors.orange,
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: _buildTextField(
                firstNameController,
                "First Name",
                Icons.person_outline_rounded,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildTextField(
                middleNameController,
                "Middle Name",
                null,
                isRequired: false,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildTextField(
          lastNameController,
          "Surname (Last Name)",
          Icons.badge_outlined,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: _buildTextField(
                dobController,
                "Date of Birth",
                Icons.cake_rounded,
                readOnly: true,
                onTap: onDateTap,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: _buildDropdown(
                "Gender",
                ['Male', 'Female'],
                selectedGender,
                (v) => onGenderChanged(v!),
              ),
            ),
          ],
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

  Widget _buildTextField(
    TextEditingController ctrl,
    String label,
    IconData? icon, {
    bool isRequired = true,
    bool readOnly = false,
    VoidCallback? onTap,
  }) {
    return TextFormField(
      controller: ctrl,
      readOnly: readOnly,
      onTap: onTap,
      validator: isRequired
          ? (v) => v!.trim().isEmpty ? "Required field" : null
          : null,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey.shade500, fontSize: 13),
        prefixIcon: icon != null
            ? Icon(icon, color: primaryColor, size: 20)
            : null,
        filled: true,
        fillColor: isDark
            ? Colors.white.withValues(alpha: 0.03)
            : Colors.grey.shade50,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: isDark ? Colors.white10 : Colors.grey.shade200,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: primaryColor.withValues(alpha: 0.5),
            width: 2,
          ),
        ),
      ),
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
