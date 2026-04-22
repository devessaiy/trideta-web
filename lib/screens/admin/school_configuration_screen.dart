import 'package:trideta_v2/utils/auth_error_handler.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SchoolConfigurationScreen extends StatefulWidget {
  const SchoolConfigurationScreen({super.key});

  @override
  State<SchoolConfigurationScreen> createState() =>
      _SchoolConfigurationScreenState();
}

class _SchoolConfigurationScreenState extends State<SchoolConfigurationScreen>
    with AuthErrorHandler {
  final _supabase = Supabase.instance.client;

  bool _isLoading = true;
  bool _isSaving = false;
  String? _schoolId;

  // --- RELATIONAL STATE DATA ---
  List<Map<String, dynamic>> _classes = [];
  List<Map<String, dynamic>> _classSubjects = [];

  final List<String> _deletedClassIds = [];
  final List<String> _deletedSubjectIds = [];

  // 🚨 DEEP CASCADE TRACKER
  final Map<String, String> _renamedClasses = {};

  // --- INPUT CONTROLLERS ---
  final _classController = TextEditingController();
  final _subjectController = TextEditingController();
  String? _selectedClassName;
  String _subjectType = 'Compulsory';

  @override
  void initState() {
    super.initState();
    _fetchRelationalConfig();
  }

  Future<void> _fetchRelationalConfig() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final profile = await _supabase
          .from('profiles')
          .select('school_id')
          .eq('id', user.id)
          .single();
      _schoolId = profile['school_id'];

      final school = await _supabase
          .from('schools')
          .select('active_classes, class_subjects')
          .eq('id', _schoolId!)
          .single();

      final classesData = await _supabase
          .from('classes')
          .select()
          .eq('school_id', _schoolId!)
          .order('list_order', ascending: true);

      final subjectsData = await _supabase
          .from('class_subjects')
          .select()
          .eq('school_id', _schoolId!);

      if (mounted) {
        setState(() {
          _classes = List<Map<String, dynamic>>.from(classesData);
          _classSubjects = List<Map<String, dynamic>>.from(subjectsData);

          var activeClassesRaw = school['active_classes'];
          // Ignore empty arrays or strings
          if (activeClassesRaw != null && activeClassesRaw.toString() != '[]') {
            try {
              List<dynamic> jsonClasses = activeClassesRaw is String
                  ? jsonDecode(activeClassesRaw)
                  : activeClassesRaw;

              for (var jc in jsonClasses) {
                String cName = jc.toString().trim().toUpperCase();
                if (cName.isNotEmpty &&
                    !_classes.any(
                      (c) => c['name'].toString().toUpperCase() == cName,
                    )) {
                  _classes.add({
                    'id': null,
                    'name': cName,
                    'list_order': _classes.length,
                  });
                }
              }
            } catch (e) {
              debugPrint("JSON Decode Error (Classes): $e");
            }
          }

          var classSubjectsRaw = school['class_subjects'];
          // Ignore empty maps or strings
          if (classSubjectsRaw != null && classSubjectsRaw.toString() != '{}') {
            try {
              Map<String, dynamic> jsonSubjects = classSubjectsRaw is String
                  ? jsonDecode(classSubjectsRaw)
                  : classSubjectsRaw;

              jsonSubjects.forEach((className, typeMap) {
                if (typeMap is Map) {
                  typeMap.forEach((type, subs) {
                    if (subs is List) {
                      for (var sub in subs) {
                        String sName = sub.toString().trim().toUpperCase();
                        String cName = className
                            .toString()
                            .trim()
                            .toUpperCase();

                        String cleanType =
                            type.toString().toLowerCase() == 'optional'
                            ? 'Elective'
                            : type.toString();

                        bool exists = _classSubjects.any(
                          (s) =>
                              s['class_name'].toString().toUpperCase() ==
                                  cName &&
                              s['subject_name'].toString().toUpperCase() ==
                                  sName,
                        );

                        if (!exists && sName.isNotEmpty) {
                          _classSubjects.add({
                            'id': null,
                            'class_name': cName,
                            'subject_name': sName,
                            'type': cleanType,
                          });
                        }
                      }
                    }
                  });
                }
              });
            } catch (e) {
              debugPrint("JSON Decode Error (Subjects): $e");
            }
          }

          if (_classes.isNotEmpty) {
            if (_selectedClassName == null ||
                !_classes.any((c) => c['name'] == _selectedClassName)) {
              _selectedClassName = _classes.first['name'];
            }
          }

          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        showAuthErrorDialog(
          "Failed to load configuration. Please check connection.",
        );
      }
    }
  }

  // --- 🚨 FIXED: SPLIT INSERT VS UPDATE LOGIC WITH PROPER DART SYNTAX ---
  Future<void> _saveConfig() async {
    setState(() => _isSaving = true);
    try {
      if (_deletedClassIds.isNotEmpty) {
        await _supabase
            .from('classes')
            .delete()
            .filter('id', 'in', _deletedClassIds);
      }
      if (_deletedSubjectIds.isNotEmpty) {
        await _supabase
            .from('class_subjects')
            .delete()
            .filter('id', 'in', _deletedSubjectIds);
      }

      // 🚨 THE DEEP CASCADE: Update students and staff who belong to renamed classes
      for (String oldName in _renamedClasses.keys) {
        String newName = _renamedClasses[oldName]!;

        // Update Students
        await _supabase
            .from('students')
            .update({'class_level': newName})
            .eq('school_id', _schoolId!)
            .eq('class_level', oldName);

        // Update Staff Assignments
        await _supabase
            .from('staff_assignments')
            .update({'class_assigned': newName})
            .eq('school_id', _schoolId!)
            .eq('class_assigned', oldName);
      }

      // 🚨 SMART SPLIT: Classes
      List<Map<String, dynamic>> classesToInsert = [];
      List<Map<String, dynamic>> classesToUpdate = [];

      for (int i = 0; i < _classes.length; i++) {
        var c = _classes[i];
        if (c['id'] == null) {
          classesToInsert.add({
            'school_id': _schoolId,
            'name': c['name'],
            'list_order': i,
          });
        } else {
          classesToUpdate.add({
            'id': c['id'],
            'school_id': _schoolId,
            'name': c['name'],
            'list_order': i,
          });
        }
      }

      if (classesToInsert.isNotEmpty) {
        await _supabase.from('classes').insert(classesToInsert);
      }
      if (classesToUpdate.isNotEmpty) {
        await _supabase.from('classes').upsert(classesToUpdate);
      }

      // 🚨 SMART SPLIT: Subjects
      List<Map<String, dynamic>> subjectsToInsert = [];
      List<Map<String, dynamic>> subjectsToUpdate = [];

      for (var s in _classSubjects) {
        if (s['id'] == null) {
          subjectsToInsert.add({
            'school_id': _schoolId,
            'class_name': s['class_name'],
            'subject_name': s['subject_name'],
            'type': s['type'],
          });
        } else {
          subjectsToUpdate.add({
            'id': s['id'],
            'school_id': _schoolId,
            'class_name': s['class_name'],
            'subject_name': s['subject_name'],
            'type': s['type'],
          });
        }
      }

      if (subjectsToInsert.isNotEmpty) {
        await _supabase.from('class_subjects').insert(subjectsToInsert);
      }
      if (subjectsToUpdate.isNotEmpty) {
        await _supabase.from('class_subjects').upsert(subjectsToUpdate);
      }

      // ✅ CORRECT DART SYNTAX FOR WIPING JSON
      await _supabase
          .from('schools')
          .update({'active_classes': [], 'class_subjects': {}})
          .eq('id', _schoolId!);

      if (mounted) {
        setState(() {
          _isSaving = false;
          _renamedClasses.clear(); // Clear tracker after successful save
        });
        showSuccessDialog(
          "Success",
          "School structure secured to the database.",
        );
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) Navigator.pop(context);
        });
      }
    } catch (e) {
      debugPrint("💥 DB SAVE ERROR: $e");
      if (mounted) {
        setState(() => _isSaving = false);
        showAuthErrorDialog("Failed to save. Please check your connection.");
      }
    }
  }

  void _addClass() {
    final clsName = _classController.text.trim().toUpperCase();
    if (clsName.isEmpty) return;
    if (_classes.any((c) => c['name'].toString().toUpperCase() == clsName)) {
      _showDuplicateAlert("'$clsName' already exists.");
      return;
    }
    setState(() {
      _classes.add({
        'id': null,
        'name': clsName,
        'list_order': _classes.length,
      });
      _selectedClassName ??= clsName;
      _classController.clear();
    });
  }

  void _removeClass(Map<String, dynamic> cls) {
    setState(() {
      if (cls['id'] != null) _deletedClassIds.add(cls['id']);
      _classes.remove(cls);

      final subsToRemove = _classSubjects
          .where((s) => s['class_name'] == cls['name'])
          .toList();
      for (var s in subsToRemove) {
        if (s['id'] != null) _deletedSubjectIds.add(s['id']);
        _classSubjects.remove(s);
      }

      if (_selectedClassName == cls['name']) {
        _selectedClassName = _classes.isNotEmpty
            ? _classes.first['name']
            : null;
      }
    });
  }

  Future<void> _editClass(Map<String, dynamic> cls) async {
    final oldName = cls['name'];
    final editController = TextEditingController(text: oldName);
    Color primaryColor = Theme.of(context).primaryColor;

    String? newName = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          title: const Text(
            "Edit Class Name",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: TextField(
            controller: editController,
            textCapitalization: TextCapitalization.characters,
            autofocus: true,
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.grey.withOpacity(0.1),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: primaryColor),
              onPressed: () =>
                  Navigator.pop(ctx, editController.text.trim().toUpperCase()),
              child: const Text("Save", style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );

    if (newName != null && newName.isNotEmpty && newName != oldName) {
      if (_classes.any((c) => c['name'] == newName)) {
        _showDuplicateAlert("'$newName' already exists.");
        return;
      }
      setState(() {
        cls['name'] = newName;
        // 🚨 TRACK THE RENAME FOR THE DEEP CASCADE
        _renamedClasses[oldName] = newName;

        for (var s in _classSubjects) {
          if (s['class_name'] == oldName) s['class_name'] = newName;
        }
        if (_selectedClassName == oldName) _selectedClassName = newName;
      });
    }
  }

  void _addSubject() {
    final subName = _subjectController.text.trim().toUpperCase();
    if (subName.isEmpty || _selectedClassName == null) return;

    bool exists = _classSubjects.any(
      (s) =>
          s['class_name'] == _selectedClassName &&
          s['subject_name'].toString().toUpperCase() == subName,
    );
    if (exists) {
      _showDuplicateAlert("'$subName' is already in $_selectedClassName.");
      return;
    }

    setState(() {
      _classSubjects.add({
        'id': null,
        'subject_name': subName,
        'type': _subjectType,
        'class_name': _selectedClassName,
      });
      _subjectController.clear();
    });
  }

  void _removeSubject(Map<String, dynamic> subject) {
    setState(() {
      if (subject['id'] != null) _deletedSubjectIds.add(subject['id']);
      _classSubjects.remove(subject);
    });
  }

  Future<void> _editSubject(Map<String, dynamic> subject) async {
    final editController = TextEditingController(text: subject['subject_name']);
    Color primaryColor = Theme.of(context).primaryColor;

    String? newName = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          title: const Text(
            "Rename Subject",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: TextField(
            controller: editController,
            textCapitalization: TextCapitalization.characters,
            autofocus: true,
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.grey.withOpacity(0.1),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: primaryColor),
              onPressed: () =>
                  Navigator.pop(ctx, editController.text.trim().toUpperCase()),
              child: const Text("Save", style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );

    if (newName != null &&
        newName.isNotEmpty &&
        newName != subject['subject_name']) {
      bool exists = _classSubjects.any(
        (s) =>
            s != subject &&
            s['class_name'] == subject['class_name'] &&
            s['subject_name'].toString().toUpperCase() == newName,
      );
      if (exists) {
        _showDuplicateAlert("'$newName' already exists in this class.");
        return;
      }
      setState(() => subject['subject_name'] = newName);
    }
  }

  void _showDuplicateAlert(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.orange.shade800,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC);
    Color cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    Color primaryColor = Theme.of(context).primaryColor;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: bgColor,
        body: Center(child: CircularProgressIndicator(color: primaryColor)),
      );
    }

    // 🚨 EXTRACTED MAIN CONTENT FOR LAYOUT BUILDER
    Widget mainContent = Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              _buildSectionLabel("1. MANAGE CLASSES", isDark, primaryColor),
              _buildClassManager(cardColor, isDark, primaryColor),
              const SizedBox(height: 30),
              _buildSectionLabel("2. SUBJECT CURRICULUM", isDark, primaryColor),
              _buildSubjectManager(cardColor, isDark, primaryColor),
            ],
          ),
        ),
        _buildSaveBottomBar(isDark, primaryColor),
      ],
    );

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text(
          "Structure Editor",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      // 🚨 SHAPE-SHIFTER: LayoutBuilder
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth > 800) {
            // 💻 DESKTOP LAYOUT (Constrained Center Column)
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: Container(
                  decoration: BoxDecoration(
                    color: bgColor,
                    border: Border(
                      left: BorderSide(
                        color: isDark ? Colors.white10 : Colors.grey.shade200,
                        width: 1,
                      ),
                      right: BorderSide(
                        color: isDark ? Colors.white10 : Colors.grey.shade200,
                        width: 1,
                      ),
                    ),
                  ),
                  child: mainContent,
                ),
              ),
            );
          } else {
            // 📱 MOBILE LAYOUT (Full Screen)
            return mainContent;
          }
        },
      ),
    );
  }

  Widget _buildSectionLabel(String text, bool isDark, Color primaryColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        text,
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: primaryColor,
          fontSize: 12,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildClassManager(Color cardColor, bool isDark, Color primaryColor) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _classController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: _inputStyle(
                    "e.g. JSS 1",
                    Icons.school,
                    isDark,
                    primaryColor,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filled(
                onPressed: _addClass,
                icon: const Icon(Icons.add, color: Colors.white),
                style: IconButton.styleFrom(
                  backgroundColor: primaryColor,
                  padding: const EdgeInsets.all(16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          const Text(
            "Drag to reorder. Tap the pencil to edit.",
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
          const SizedBox(height: 10),
          if (_classes.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20.0),
                child: Text("No classes added yet."),
              ),
            ),
          SizedBox(
            height: 250,
            child: ReorderableListView.builder(
              shrinkWrap: true,
              itemCount: _classes.length,
              onReorder: (oldIdx, newIdx) {
                setState(() {
                  if (newIdx > oldIdx) newIdx -= 1;
                  _classes.insert(newIdx, _classes.removeAt(oldIdx));
                });
              },
              itemBuilder: (ctx, i) => Container(
                key: ValueKey(_classes[i]['name']),
                margin: const EdgeInsets.only(bottom: 5),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withOpacity(0.02)
                      : Colors.grey[50],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: ListTile(
                  dense: true,
                  leading: Text(
                    "${i + 1}.",
                    style: TextStyle(
                      color: primaryColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  title: Text(
                    _classes[i]['name'],
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.edit_rounded,
                          color: Colors.blue,
                          size: 18,
                        ),
                        onPressed: () => _editClass(_classes[i]),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.remove_circle_outline,
                          color: Colors.red,
                          size: 20,
                        ),
                        onPressed: () => _removeClass(_classes[i]),
                      ),
                      const Icon(Icons.drag_handle, color: Colors.grey),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubjectManager(
    Color cardColor,
    bool isDark,
    Color primaryColor,
  ) {
    if (_classes.isEmpty) {
      return const Text(
        "Add a class first.",
        style: TextStyle(color: Colors.grey),
      );
    }
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _selectedClassName,
            decoration: _inputStyle(
              "Target Class",
              Icons.class_,
              isDark,
              primaryColor,
            ),
            items: _classes
                .map(
                  (c) => DropdownMenuItem<String>(
                    value: c['name'],
                    child: Text(c['name']),
                  ),
                )
                .toList(),
            onChanged: (val) => setState(() => _selectedClassName = val),
          ),
          const SizedBox(height: 15),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'Compulsory', label: Text('Compulsory')),
              ButtonSegment(value: 'Elective', label: Text('Elective')),
            ],
            selected: {_subjectType},
            onSelectionChanged: (Set<String> newSelection) =>
                setState(() => _subjectType = newSelection.first),
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? primaryColor.withOpacity(0.1)
                    : Colors.transparent,
              ),
              foregroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? primaryColor
                    : Colors.grey,
              ),
            ),
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _subjectController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: _inputStyle(
                    "Subject Name",
                    Icons.book,
                    isDark,
                    primaryColor,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filled(
                onPressed: _addSubject,
                icon: const Icon(Icons.add, color: Colors.white),
                style: IconButton.styleFrom(
                  backgroundColor: primaryColor,
                  padding: const EdgeInsets.all(16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text(
            "Tap a subject to rename it.",
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 10),
          _buildSubjectChipWrap("Compulsory Subjects", 'Compulsory'),
          const SizedBox(height: 15),
          _buildSubjectChipWrap("Elective Subjects", 'Elective'),
        ],
      ),
    );
  }

  Widget _buildSubjectChipWrap(String label, String type) {
    if (_selectedClassName == null) return const SizedBox();
    final subjects = _classSubjects
        .where(
          (s) => s['class_name'] == _selectedClassName && s['type'] == type,
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 5),
        if (subjects.isEmpty)
          const Text(
            "None added",
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey,
              fontStyle: FontStyle.italic,
            ),
          ),
        Wrap(
          spacing: 8,
          children: subjects
              .map(
                (s) => InputChip(
                  label: Text(
                    s['subject_name'],
                    style: const TextStyle(fontSize: 11),
                  ),
                  deleteIconColor: Colors.red,
                  onDeleted: () => _removeSubject(s),
                  onPressed: () => _editSubject(s),
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  Widget _buildSaveBottomBar(bool isDark, Color primaryColor) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        height: 55,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
          ),
          onPressed: _isSaving ? null : _saveConfig,
          child: _isSaving
              ? const CircularProgressIndicator(color: Colors.white)
              : const Text(
                  "SAVE CONFIGURATION",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
      ),
    );
  }

  InputDecoration _inputStyle(
    String label,
    IconData icon,
    bool isDark,
    Color primaryColor,
  ) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: primaryColor, size: 20),
      filled: true,
      fillColor: isDark ? Colors.white.withOpacity(0.03) : Colors.grey[50],
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide.none,
      ),
    );
  }
}
