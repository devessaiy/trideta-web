import 'package:flutter/material.dart';

// ===========================================================================
// 🚨 SHARED INPUT STYLING
// ===========================================================================
InputDecoration buildConfigInputStyle(
  String label,
  IconData icon,
  bool isDark,
  Color primaryColor,
) {
  return InputDecoration(
    labelText: label,
    labelStyle: TextStyle(color: Colors.grey.shade500, fontSize: 13),
    prefixIcon: Icon(icon, color: primaryColor, size: 18),
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
  );
}

// ===========================================================================
// 🚨 CLASSES MANAGEMENT PANEL
// ===========================================================================
class ClassesPanel extends StatelessWidget {
  final List<Map<String, dynamic>> classes;
  final TextEditingController classController;
  final bool isDark;
  final Color primaryColor;
  final VoidCallback onAddClass;
  final Function(int, int) onReorder;
  final Function(Map<String, dynamic>) onEditClass;
  final Function(Map<String, dynamic>) onRemoveClass;

  const ClassesPanel({
    super.key,
    required this.classes,
    required this.classController,
    required this.isDark,
    required this.primaryColor,
    required this.onAddClass,
    required this.onReorder,
    required this.onEditClass,
    required this.onRemoveClass,
  });

  @override
  Widget build(BuildContext context) {
    Color cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
          width: 1.5,
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.school_rounded,
                  color: primaryColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                "Manage Classes",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: classController,
                  textCapitalization: TextCapitalization.characters,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  decoration: buildConfigInputStyle(
                    "Add new class",
                    Icons.add_business_rounded,
                    isDark,
                    primaryColor,
                  ),
                  onSubmitted: (_) => onAddClass(),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: primaryColor,
                  padding: const EdgeInsets.all(16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: onAddClass,
                child: const Icon(Icons.add_rounded, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: classes.isEmpty
                ? const Center(
                    child: Text(
                      "No classes configured.",
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ReorderableListView.builder(
                    itemCount: classes.length,
                    onReorder: onReorder,
                    itemBuilder: (ctx, i) {
                      var cls = classes[i];
                      bool hasCustomCal =
                          cls['override_session'] != null ||
                          cls['override_term'] != null;

                      Map<String, dynamic> promoCriteria =
                          cls['promotion_criteria'] ?? {};
                      List<dynamic> coreSubs =
                          promoCriteria['core_subjects'] ?? [];
                      bool hasCoreRules = coreSubs.isNotEmpty;

                      return Container(
                        key: ValueKey(cls['name']),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.02)
                              : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: hasCustomCal
                                ? Colors.orange.withValues(alpha: 0.3)
                                : (isDark
                                      ? Colors.white10
                                      : Colors.grey.shade200),
                          ),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          title: Row(
                            children: [
                              Text(
                                cls['name'],
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              if (hasCustomCal) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Icon(
                                    Icons.calendar_month_rounded,
                                    color: Colors.orange,
                                    size: 12,
                                  ),
                                ),
                              ],
                              if (hasCoreRules) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.redAccent.withValues(
                                      alpha: 0.1,
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Icon(
                                    Icons.rule_folder_rounded,
                                    color: Colors.redAccent,
                                    size: 12,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          leading: Icon(
                            Icons.drag_indicator_rounded,
                            color: Colors.grey.shade400,
                            size: 20,
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(
                                  Icons.settings_rounded,
                                  size: 18,
                                  color: Colors.blue,
                                ),
                                onPressed: () => onEditClass(cls),
                                tooltip: "Configure",
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  size: 18,
                                  color: Colors.redAccent,
                                ),
                                onPressed: () => onRemoveClass(cls),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// 🚨 SUBJECTS MANAGEMENT PANEL
// ===========================================================================
class SubjectsPanel extends StatelessWidget {
  final List<Map<String, dynamic>> classes;
  final List<Map<String, dynamic>> classSubjects;
  final TextEditingController subjectController;
  final String? selectedClassName;
  final String subjectType;
  final bool isDark;
  final Color primaryColor;
  final ValueChanged<String?> onTargetClassChanged;
  final ValueChanged<String?> onSubjectTypeChanged;
  final VoidCallback onAddSubject;
  final Function(Map<String, dynamic>) onEditSubject;
  final Function(Map<String, dynamic>) onRemoveSubject;
  final VoidCallback onCopySubjects;

  const SubjectsPanel({
    super.key,
    required this.classes,
    required this.classSubjects,
    required this.subjectController,
    required this.selectedClassName,
    required this.subjectType,
    required this.isDark,
    required this.primaryColor,
    required this.onTargetClassChanged,
    required this.onSubjectTypeChanged,
    required this.onAddSubject,
    required this.onEditSubject,
    required this.onRemoveSubject,
    required this.onCopySubjects,
  });

  @override
  Widget build(BuildContext context) {
    if (classes.isEmpty) {
      return const Center(
        child: Text(
          "Add a class first to manage subjects.",
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    Color cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
          width: 1.5,
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: primaryColor.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.library_books_rounded,
                      color: primaryColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    "Manage Subjects",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              if (classSubjects.isNotEmpty)
                TextButton.icon(
                  onPressed: onCopySubjects,
                  icon: const Icon(Icons.copy_all_rounded, size: 18),
                  label: const Text("Copy to..."),
                  style: TextButton.styleFrom(
                    foregroundColor: primaryColor,
                    textStyle: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),

          DropdownButtonFormField<String>(
            initialValue: selectedClassName,
            dropdownColor: isDark ? const Color(0xFF2C2C2C) : Colors.white,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87,
              fontSize: 14,
            ),
            decoration: buildConfigInputStyle(
              "Target Class",
              Icons.filter_alt_rounded,
              isDark,
              primaryColor,
            ),
            items: classes
                .map(
                  (c) => DropdownMenuItem<String>(
                    value: c['name'],
                    child: Text(c['name']),
                  ),
                )
                .toList(),
            onChanged: onTargetClassChanged,
          ),
          const SizedBox(height: 15),

          Row(
            children: [
              Expanded(
                flex: 5,
                child: TextField(
                  controller: subjectController,
                  textCapitalization: TextCapitalization.characters,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  decoration: buildConfigInputStyle(
                    "Add subject",
                    Icons.add_task_rounded,
                    isDark,
                    primaryColor,
                  ),
                  onSubmitted: (_) => onAddSubject(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 4,
                child: DropdownButtonFormField<String>(
                  initialValue: subjectType,
                  dropdownColor: isDark
                      ? const Color(0xFF2C2C2C)
                      : Colors.white,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                    fontSize: 13,
                  ),
                  isExpanded: true,
                  decoration: buildConfigInputStyle(
                    "Type",
                    Icons.category_rounded,
                    isDark,
                    primaryColor,
                  ),
                  items: ['Compulsory', 'Elective']
                      .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: onSubjectTypeChanged,
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: primaryColor,
                  padding: const EdgeInsets.all(16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: onAddSubject,
                child: const Icon(Icons.add_rounded, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 30),

          Expanded(
            child: selectedClassName == null
                ? const Center(child: Text("Select a class to view subjects"))
                : ListView(
                    children: [
                      _buildSubjectCategory("Compulsory", isDark, Colors.green),
                      const SizedBox(height: 25),
                      _buildSubjectCategory("Elective", isDark, Colors.orange),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubjectCategory(String type, bool isDark, Color color) {
    final subs = classSubjects
        .where((s) => s['class_name'] == selectedClassName && s['type'] == type)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              type == 'Compulsory'
                  ? Icons.stars_rounded
                  : Icons.star_border_rounded,
              size: 14,
              color: color,
            ),
            const SizedBox(width: 6),
            Text(
              "$type Subjects",
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: Colors.grey.shade500,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (subs.isEmpty)
          Text(
            "No $type subjects added.",
            style: TextStyle(
              fontStyle: FontStyle.italic,
              color: Colors.grey.shade400,
              fontSize: 13,
            ),
          )
        else
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: subs.map((s) {
              return InkWell(
                onTap: () => onEditSubject(s),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.only(
                    left: 14,
                    right: 6,
                    top: 6,
                    bottom: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? color.withValues(alpha: 0.1)
                        : color.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: color.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        s['subject_name'],
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(width: 6),
                      InkWell(
                        onTap: () => onRemoveSubject(s),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close_rounded,
                            size: 12,
                            color: Colors.redAccent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
      ],
    );
  }
}

// ===========================================================================
// 🚨 EDIT CLASS DIALOG (PROMOTION STANDARDS)
// ===========================================================================
class EditClassDialog extends StatefulWidget {
  final Map<String, dynamic> schoolClass;
  final List<String> availableSubjects;
  final Color primaryColor;
  final bool isDark;

  const EditClassDialog({
    super.key,
    required this.schoolClass,
    required this.availableSubjects,
    required this.primaryColor,
    required this.isDark,
  });

  @override
  State<EditClassDialog> createState() => _EditClassDialogState();
}

class _EditClassDialogState extends State<EditClassDialog> {
  late TextEditingController editController;
  late bool usesCustomCalendar;
  late String customSession;
  late String customTerm;
  late double passMark;
  late List<String> coreSubjects;

  @override
  void initState() {
    super.initState();
    final cls = widget.schoolClass;
    editController = TextEditingController(text: cls['name']);
    usesCustomCalendar =
        cls['override_session'] != null || cls['override_term'] != null;
    customSession = cls['override_session'] ?? '2025/2026';
    customTerm = cls['override_term'] ?? '1st Term';

    Map<String, dynamic> promoCriteria = cls['promotion_criteria'] != null
        ? Map<String, dynamic>.from(cls['promotion_criteria'])
        : {'pass_mark': 40, 'core_subjects': []};

    passMark = (promoCriteria['pass_mark'] ?? 40).toDouble();
    coreSubjects = List<String>.from(promoCriteria['core_subjects'] ?? []);
    coreSubjects.removeWhere((s) => !widget.availableSubjects.contains(s));
  }

  @override
  void dispose() {
    editController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Color cardColor = widget.isDark ? const Color(0xFF1E1E1E) : Colors.white;

    return AlertDialog(
      backgroundColor: cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Text(
        "Edit Class Configuration",
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: editController,
              textCapitalization: TextCapitalization.characters,
              decoration: buildConfigInputStyle(
                "Class Name",
                Icons.class_rounded,
                widget.isDark,
                widget.primaryColor,
              ),
            ),
            const SizedBox(height: 25),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: widget.isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: usesCustomCalendar
                      ? widget.primaryColor.withValues(alpha: 0.5)
                      : (widget.isDark ? Colors.white10 : Colors.grey.shade200),
                ),
              ),
              child: Column(
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      "Custom Academic Calendar",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    subtitle: Text(
                      usesCustomCalendar
                          ? "Independent from global school calendar."
                          : "Inheriting global school calendar.",
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                      ),
                    ),
                    activeThumbColor: widget.primaryColor,
                    value: usesCustomCalendar,
                    onChanged: (val) =>
                        setState(() => usesCustomCalendar = val),
                  ),
                  if (usesCustomCalendar) ...[
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: customSession,
                      dropdownColor: cardColor,
                      decoration: buildConfigInputStyle(
                        "Session",
                        Icons.calendar_month_rounded,
                        widget.isDark,
                        widget.primaryColor,
                      ),
                      items: ['2024/2025', '2025/2026', '2026/2027']
                          .map(
                            (e) => DropdownMenuItem(
                              value: e,
                              child: Text(
                                e,
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (val) => setState(() => customSession = val!),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: customTerm,
                      dropdownColor: cardColor,
                      decoration: buildConfigInputStyle(
                        "Term",
                        Icons.history_edu_rounded,
                        widget.isDark,
                        widget.primaryColor,
                      ),
                      items: ['1st Term', '2nd Term', '3rd Term']
                          .map(
                            (e) => DropdownMenuItem(
                              value: e,
                              child: Text(
                                e,
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (val) => setState(() => customTerm = val!),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 25),

            const Text(
              "Academic Promotion Standards",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: widget.isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: widget.isDark ? Colors.white10 : Colors.grey.shade200,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Minimum Pass Mark",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: widget.primaryColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          "${passMark.toInt()}%",
                          style: TextStyle(
                            color: widget.primaryColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: passMark,
                    min: 0,
                    max: 100,
                    divisions: 100,
                    activeColor: widget.primaryColor,
                    onChanged: (val) => setState(() => passMark = val),
                  ),
                  const SizedBox(height: 15),
                  const Text(
                    "Core Subjects (Must Pass)",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  if (widget.availableSubjects.isEmpty)
                    Text(
                      "Add subjects to this class first to assign core requirements.",
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                        fontStyle: FontStyle.italic,
                      ),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: widget.availableSubjects.map((sub) {
                        bool isCore = coreSubjects.contains(sub);
                        return FilterChip(
                          label: Text(
                            sub,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: isCore
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: isCore
                                  ? Colors.white
                                  : (widget.isDark
                                        ? Colors.white70
                                        : Colors.black87),
                            ),
                          ),
                          selected: isCore,
                          showCheckmark: false,
                          selectedColor: Colors.redAccent,
                          backgroundColor: widget.isDark
                              ? Colors.white10
                              : Colors.grey.shade200,
                          onSelected: (selected) {
                            setState(() {
                              if (selected) {
                                coreSubjects.add(sub);
                              } else {
                                coreSubjects.remove(sub);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(
            "Cancel",
            style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
          ),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: widget.primaryColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onPressed: () {
            Navigator.pop(context, {
              'newName': editController.text.trim().toUpperCase(),
              'session': usesCustomCalendar ? customSession : null,
              'term': usesCustomCalendar ? customTerm : null,
              'promo_criteria': {
                'pass_mark': passMark.toInt(),
                'core_subjects': coreSubjects,
              },
            });
          },
          child: const Text(
            "Save Config",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}

// ===========================================================================
// 🚨 EDIT SUBJECT DIALOG
// ===========================================================================
class EditSubjectDialog extends StatefulWidget {
  final String initialName;
  final Color primaryColor;
  final bool isDark;

  const EditSubjectDialog({
    super.key,
    required this.initialName,
    required this.primaryColor,
    required this.isDark,
  });

  @override
  State<EditSubjectDialog> createState() => _EditSubjectDialogState();
}

class _EditSubjectDialogState extends State<EditSubjectDialog> {
  late TextEditingController editController;

  @override
  void initState() {
    super.initState();
    editController = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    editController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: widget.isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text(
        "Rename Subject",
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      content: TextField(
        controller: editController,
        textCapitalization: TextCapitalization.characters,
        autofocus: true,
        decoration: buildConfigInputStyle(
          "Subject Name",
          Icons.book_rounded,
          widget.isDark,
          widget.primaryColor,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(
            "Cancel",
            style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
          ),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: widget.primaryColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          onPressed: () =>
              Navigator.pop(context, editController.text.trim().toUpperCase()),
          child: const Text(
            "Save",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}

// ===========================================================================
// 🚨 COPY SUBJECTS DIALOG
// ===========================================================================
class CopySubjectsDialog extends StatefulWidget {
  final String sourceClassName;
  final List<String> availableClasses;
  final Color primaryColor;
  final bool isDark;

  const CopySubjectsDialog({
    super.key,
    required this.sourceClassName,
    required this.availableClasses,
    required this.primaryColor,
    required this.isDark,
  });

  @override
  State<CopySubjectsDialog> createState() => _CopySubjectsDialogState();
}

class _CopySubjectsDialogState extends State<CopySubjectsDialog> {
  List<String> selectedTargets = [];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: widget.isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        "Copy Subjects to...",
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: widget.primaryColor,
        ),
      ),
      content: SizedBox(
        width: 300,
        height: 300,
        child: Column(
          children: [
            Text(
              "Copying from ${widget.sourceClassName}",
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: widget.isDark
                        ? Colors.white10
                        : Colors.grey.shade300,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: ListView(
                  children: widget.availableClasses.map((cls) {
                    return CheckboxListTile(
                      title: Text(
                        cls,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      value: selectedTargets.contains(cls),
                      activeColor: widget.primaryColor,
                      onChanged: (val) {
                        setState(() {
                          if (val == true) {
                            selectedTargets.add(cls);
                          } else {
                            selectedTargets.remove(cls);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(
            "Cancel",
            style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
          ),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: widget.primaryColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          onPressed: () => Navigator.pop(context, selectedTargets),
          child: const Text(
            "Apply",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
