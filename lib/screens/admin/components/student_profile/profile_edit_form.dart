import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';

class ProfileEditForm extends StatelessWidget {
  final Uint8List? webImage;
  final String displayImagePath;
  final VoidCallback onPickImage;
  final TextEditingController firstNameController;
  final TextEditingController middleNameController;
  final TextEditingController lastNameController;
  final TextEditingController dobController;
  final TextEditingController addressController;

  final String
  studentClass; // 🚨 Added studentClass to evaluate the Department logic
  final String selectedGender;
  final Function(String) onGenderChanged;
  final String selectedDepartment;
  final Function(String) onDepartmentChanged;
  final String studentCategory;
  final Function(String) onCategoryChanged;

  final VoidCallback onDateTap;
  final Color primaryColor;
  final Color cardColor;
  final Color textColor;
  final bool isDark;

  const ProfileEditForm({
    super.key,
    required this.webImage,
    required this.displayImagePath,
    required this.onPickImage,
    required this.firstNameController,
    required this.middleNameController,
    required this.lastNameController,
    required this.dobController,
    required this.addressController,
    required this.studentClass, // 🚨 Required here
    required this.selectedGender,
    required this.onGenderChanged,
    required this.selectedDepartment,
    required this.onDepartmentChanged,
    required this.studentCategory,
    required this.onCategoryChanged,
    required this.onDateTap,
    required this.primaryColor,
    required this.cardColor,
    required this.textColor,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    // 🚨 SMART DETECTION: Ensures JSS does not accidentally trigger the SS logic!
    bool isSeniorSecondary =
        studentClass.toUpperCase().contains("SS") &&
        !studentClass.toUpperCase().contains("JSS");

    return SingleChildScrollView(
      padding: const EdgeInsets.all(30),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(24),
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
            Center(
              child: GestureDetector(
                onTap: onPickImage,
                child: Stack(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: primaryColor.withValues(alpha: 0.3),
                          width: 2,
                        ),
                      ),
                      child: CircleAvatar(
                        radius: 55,
                        backgroundColor: primaryColor.withValues(alpha: 0.1),
                        backgroundImage: webImage != null
                            ? MemoryImage(webImage!)
                            : (displayImagePath.isNotEmpty)
                            ? (displayImagePath.startsWith('http')
                                  ? NetworkImage(displayImagePath)
                                  : FileImage(File(displayImagePath))
                                        as ImageProvider)
                            : null,
                        child: (webImage == null && displayImagePath.isEmpty)
                            ? Icon(
                                Icons.person_rounded,
                                size: 50,
                                color: primaryColor,
                              )
                            : null,
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: primaryColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: cardColor, width: 2),
                        ),
                        child: const Icon(
                          Icons.camera_alt_rounded,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 30),

            _buildSectionTitle(
              "Student Biodata",
              Icons.person_outline_rounded,
              primaryColor,
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _buildTextField(
                    firstNameController,
                    "First Name",
                    Icons.badge_rounded,
                    isRequired: true,
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
              isRequired: true,
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
                    isRequired: true,
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
            const SizedBox(height: 16),

            // 🚨 CONDITIONAL RENDER: Department logic smoothly integrates here
            if (isSeniorSecondary)
              Row(
                children: [
                  Expanded(
                    child: _buildDropdown(
                      "Department",
                      ['General', 'Science', 'Art', 'Commercial'],
                      selectedDepartment,
                      (v) => onDepartmentChanged(v!),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildDropdown(
                      "Category",
                      [
                        'Regular',
                        'Transfer',
                        'Scholarship',
                        'Special',
                        'Staff Child',
                        'Orphan',
                      ],
                      studentCategory,
                      (v) => onCategoryChanged(v!),
                    ),
                  ),
                ],
              )
            else
              _buildDropdown(
                "Category",
                [
                  'Regular',
                  'Transfer',
                  'Scholarship',
                  'Special',
                  'Staff Child',
                  'Orphan',
                ],
                studentCategory,
                (v) => onCategoryChanged(v!),
              ),

            const SizedBox(height: 16),
            _buildTextField(
              addressController,
              "Home Address",
              Icons.location_on_rounded,
              maxLines: 2,
              isRequired: false,
            ),
            const SizedBox(height: 20),

            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    color: Colors.orange,
                    size: 16,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Parent credentials are locked. They must be updated by the parent or via the security tab to prevent sibling sync issues.",
                      style: TextStyle(
                        color: Colors.orange,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, color: color.withValues(alpha: 0.7), size: 18),
        const SizedBox(width: 8),
        Text(
          title.toUpperCase(),
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: color.withValues(alpha: 0.7),
            letterSpacing: 1.2,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _buildTextField(
    TextEditingController ctrl,
    String label,
    IconData? icon, {
    bool isRequired = true,
    int maxLines = 1,
    bool readOnly = false,
    VoidCallback? onTap,
  }) {
    return TextFormField(
      controller: ctrl,
      maxLines: maxLines,
      readOnly: readOnly,
      onTap: onTap,
      validator: isRequired
          ? (v) => v!.trim().isEmpty ? "Required field" : null
          : null,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey.shade500, fontSize: 13),
        prefixIcon: icon != null
            ? Icon(icon, color: primaryColor.withValues(alpha: 0.5), size: 18)
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
