import 'package:trideta_v2/utils/auth_error_handler.dart';
import 'package:trideta_v2/widgets/trideta_loader.dart';
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

  // ===========================================================================
  // 🚨 LOGIC ENGINE: STRICTLY UNTOUCHED
  // ===========================================================================
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
                    'override_session': null,
                    'override_term': null,
                    'list_order': _classes.length,
                  });
                }
              }
            } catch (e) {
              debugPrint("JSON Decode Error (Classes): $e");
            }
          }

          var classSubjectsRaw = school['class_subjects'];
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

      for (String oldName in _renamedClasses.keys) {
        String newName = _renamedClasses[oldName]!;

        await _supabase
            .from('students')
            .update({'class_level': newName})
            .eq('school_id', _schoolId!)
            .eq('class_level', oldName);

        await _supabase
            .from('staff_assignments')
            .update({'class_assigned': newName})
            .eq('school_id', _schoolId!)
            .eq('class_assigned', oldName);
      }

      List<Map<String, dynamic>> classesToInsert = [];
      List<Map<String, dynamic>> classesToUpdate = [];

      for (int i = 0; i < _classes.length; i++) {
        var c = _classes[i];
        if (c['id'] == null) {
          classesToInsert.add({
            'school_id': _schoolId,
            'name': c['name'],
            'override_session': c['override_session'],
            'override_term': c['override_term'],
            'list_order': i,
          });
        } else {
          classesToUpdate.add({
            'id': c['id'],
            'school_id': _schoolId,
            'name': c['name'],
            'override_session': c['override_session'],
            'override_term': c['override_term'],
            'list_order': i,
          });
        }
      }

      Map<String, String> classNameToId = {};

      if (classesToInsert.isNotEmpty) {
        final insertedClasses = await _supabase
            .from('classes')
            .insert(classesToInsert)
            .select('id, name');
        for (var c in insertedClasses) {
          classNameToId[c['name'].toString()] = c['id'].toString();
        }
      }
      if (classesToUpdate.isNotEmpty) {
        final updatedClasses = await _supabase
            .from('classes')
            .upsert(classesToUpdate)
            .select('id, name');
        for (var c in updatedClasses) {
          classNameToId[c['name'].toString()] = c['id'].toString();
        }
      }

      List<Map<String, dynamic>> subjectsToInsert = [];
      List<Map<String, dynamic>> subjectsToUpdate = [];

      for (var s in _classSubjects) {
        if (s['id'] == null) {
          subjectsToInsert.add({
            'school_id': _schoolId,
            'class_name': s['class_name'],
            'class_id': classNameToId[s['class_name']],
            'subject_name': s['subject_name'],
            'type': s['type'],
          });
        } else {
          subjectsToUpdate.add({
            'id': s['id'],
            'school_id': _schoolId,
            'class_name': s['class_name'],
            'class_id': classNameToId[s['class_name']],
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

      await _supabase
          .from('schools')
          .update({'active_classes': [], 'class_subjects': {}})
          .eq('id', _schoolId!);

      if (mounted) {
        setState(() {
          _isSaving = false;
          _renamedClasses.clear();
        });
        showSuccessDialog(
          "Success",
          "School structure secured to the database.",
        );
      }
    } catch (e) {
      debugPrint("💥 DB SAVE ERROR: $e");
      if (mounted) {
        setState(() => _isSaving = false);
        showAuthErrorDialog("Failed to save. Please check your connection.");
      }
    }
  }

  // ===========================================================================
  // 🚨 MULTI-TENANT CALENDAR FEATURE & MODALS
  // ===========================================================================

  Future<void> _editClass(Map<String, dynamic> cls) async {
    final oldName = cls['name'];
    final editController = TextEditingController(text: oldName);

    // Custom Calendar States
    bool usesCustomCalendar =
        cls['override_session'] != null || cls['override_term'] != null;
    String customSession = cls['override_session'] ?? '2025/2026';
    String customTerm = cls['override_term'] ?? '1st Term';

    Color primaryColor = Theme.of(context).primaryColor;
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    Map<String, dynamic>? result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: cardColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
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
                      decoration: _inputStyle(
                        "Class Name",
                        Icons.class_rounded,
                        isDark,
                        primaryColor,
                      ),
                    ),
                    const SizedBox(height: 25),

                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.05)
                            : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: usesCustomCalendar
                              ? primaryColor.withValues(alpha: 0.5)
                              : (isDark
                                    ? Colors.white10
                                    : Colors.grey.shade200),
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
                            activeThumbColor: primaryColor,
                            value: usesCustomCalendar,
                            onChanged: (val) =>
                                setDialogState(() => usesCustomCalendar = val),
                          ),
                          if (usesCustomCalendar) ...[
                            const SizedBox(height: 10),
                            DropdownButtonFormField<String>(
                              initialValue: customSession,
                              dropdownColor: cardColor,
                              decoration: _inputStyle(
                                "Session",
                                Icons.calendar_month_rounded,
                                isDark,
                                primaryColor,
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
                              onChanged: (val) =>
                                  setDialogState(() => customSession = val!),
                            ),
                            const SizedBox(height: 10),
                            DropdownButtonFormField<String>(
                              initialValue: customTerm,
                              dropdownColor: cardColor,
                              decoration: _inputStyle(
                                "Term",
                                Icons.history_edu_rounded,
                                isDark,
                                primaryColor,
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
                              onChanged: (val) =>
                                  setDialogState(() => customTerm = val!),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text(
                    "Cancel",
                    style: TextStyle(
                      color: Colors.grey,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx, {
                      'newName': editController.text.trim().toUpperCase(),
                      'session': usesCustomCalendar ? customSession : null,
                      'term': usesCustomCalendar ? customTerm : null,
                    });
                  },
                  child: const Text(
                    "Save Config",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null) {
      String newName = result['newName'];
      if (newName.isNotEmpty &&
          newName != oldName &&
          _classes.any((c) => c['name'] == newName)) {
        _showDuplicateAlert("'$newName' already exists.");
        return;
      }

      setState(() {
        if (newName.isNotEmpty) {
          cls['name'] = newName;
          if (newName != oldName) _renamedClasses[oldName] = newName;
          for (var s in _classSubjects) {
            if (s['class_name'] == oldName) s['class_name'] = newName;
          }
          if (_selectedClassName == oldName) _selectedClassName = newName;
        }

        // Apply the Custom Calendar Overrides
        cls['override_session'] = result['session'];
        cls['override_term'] = result['term'];
      });
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
        'override_session': null,
        'override_term': null,
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
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    String? newName = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            "Rename Subject",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: TextField(
            controller: editController,
            textCapitalization: TextCapitalization.characters,
            autofocus: true,
            decoration: _inputStyle(
              "Subject Name",
              Icons.book_rounded,
              isDark,
              primaryColor,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                "Cancel",
                style: TextStyle(
                  color: Colors.grey,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: primaryColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () =>
                  Navigator.pop(ctx, editController.text.trim().toUpperCase()),
              child: const Text(
                "Save",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
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
        content: Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.orange.shade800,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
    );
  }

  void _applySubjectsToMultipleClasses(List<String> targetClasses) {
    if (_selectedClassName == null) return;

    List<Map<String, dynamic>> sourceSubjects = _classSubjects
        .where((s) => s['class_name'] == _selectedClassName)
        .toList();
    if (sourceSubjects.isEmpty) {
      _showDuplicateAlert(
        "There are no subjects to copy from $_selectedClassName",
      );
      return;
    }

    setState(() {
      for (String targetClass in targetClasses) {
        for (var sub in sourceSubjects) {
          bool exists = _classSubjects.any(
            (s) =>
                s['class_name'] == targetClass &&
                s['subject_name'] == sub['subject_name'],
          );
          if (!exists) {
            _classSubjects.add({
              'id': null,
              'class_name': targetClass,
              'subject_name': sub['subject_name'],
              'type': sub['type'],
            });
          }
        }
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          "Subjects successfully copied! Remember to save changes.",
        ),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _showDuplicateDialog() {
    if (_classes.length <= 1) {
      _showDuplicateAlert("No other classes available to copy to.");
      return;
    }

    List<String> availableClasses = _classes
        .map((c) => c['name'] as String)
        .where((name) => name != _selectedClassName)
        .toList();
    List<String> selectedTargets = [];

    showDialog(
      context: context,
      builder: (context) {
        bool isDark = Theme.of(context).brightness == Brightness.dark;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Text(
                "Copy Subjects to...",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).primaryColor,
                ),
              ),
              content: SizedBox(
                width: 300,
                height: 300,
                child: Column(
                  children: [
                    Text(
                      "Copying from $_selectedClassName",
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
                            color: isDark
                                ? Colors.white10
                                : Colors.grey.shade300,
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: ListView(
                          children: availableClasses.map((cls) {
                            return CheckboxListTile(
                              title: Text(
                                cls,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              value: selectedTargets.contains(cls),
                              activeColor: Theme.of(context).primaryColor,
                              onChanged: (val) => setDialogState(
                                () => val == true
                                    ? selectedTargets.add(cls)
                                    : selectedTargets.remove(cls),
                              ),
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
                    style: TextStyle(
                      color: Colors.grey,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    if (selectedTargets.isNotEmpty) {
                      _applySubjectsToMultipleClasses(selectedTargets);
                    }
                  },
                  child: const Text(
                    "Apply",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ===========================================================================
  // 🚨 PREMIUM UI (REFINED)
  // ===========================================================================
  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: TridetaLoader()));

    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC);
    Color primaryColor = Theme.of(context).primaryColor;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text(
          "System Configuration",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: bgColor,
        foregroundColor: isDark ? Colors.white : const Color(0xFF1A1A2E),
        elevation: 0,
        centerTitle: true,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth > 900) {
            return Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 1200),
                padding: const EdgeInsets.all(24),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 4,
                      child: _buildClassesPanel(isDark, primaryColor),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      flex: 6,
                      child: _buildSubjectsPanel(isDark, primaryColor),
                    ),
                  ],
                ),
              ),
            );
          } else {
            return DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white10 : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: TabBar(
                      labelColor: Colors.white,
                      unselectedLabelColor: isDark
                          ? Colors.white70
                          : Colors.grey.shade600,
                      indicatorSize: TabBarIndicatorSize.tab,
                      dividerColor: Colors.transparent,
                      indicator: BoxDecoration(
                        color: primaryColor,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      tabs: const [
                        Tab(
                          child: Text(
                            "Classes",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        Tab(
                          child: Text(
                            "Subjects",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: _buildClassesPanel(isDark, primaryColor),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: _buildSubjectsPanel(isDark, primaryColor),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }
        },
      ),
      bottomNavigationBar: _buildBottomBar(isDark, primaryColor),
    );
  }

  Widget _buildClassesPanel(bool isDark, Color primaryColor) {
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
                  controller: _classController,
                  textCapitalization: TextCapitalization.characters,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  decoration: _inputStyle(
                    "Add new class",
                    Icons.add_business_rounded,
                    isDark,
                    primaryColor,
                  ),
                  onSubmitted: (_) => _addClass(),
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
                onPressed: _addClass,
                child: const Icon(Icons.add_rounded, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: _classes.isEmpty
                ? const Center(
                    child: Text(
                      "No classes configured.",
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ReorderableListView.builder(
                    itemCount: _classes.length,
                    onReorder: (oldIdx, newIdx) {
                      setState(() {
                        if (newIdx > oldIdx) newIdx -= 1;
                        _classes.insert(newIdx, _classes.removeAt(oldIdx));
                      });
                    },
                    itemBuilder: (ctx, i) {
                      var cls = _classes[i];
                      bool hasCustomCal =
                          cls['override_session'] != null ||
                          cls['override_term'] != null;

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
                                onPressed: () => _editClass(cls),
                                tooltip: "Configure",
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  size: 18,
                                  color: Colors.redAccent,
                                ),
                                onPressed: () => _removeClass(cls),
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

  Widget _buildSubjectsPanel(bool isDark, Color primaryColor) {
    if (_classes.isEmpty) {
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
              if (_classSubjects.isNotEmpty)
                TextButton.icon(
                  onPressed: _showDuplicateDialog,
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
            initialValue: _selectedClassName,
            dropdownColor: isDark ? const Color(0xFF2C2C2C) : Colors.white,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87,
              fontSize: 14,
            ),
            decoration: _inputStyle(
              "Target Class",
              Icons.filter_alt_rounded,
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

          Row(
            children: [
              Expanded(
                flex: 5,
                child: TextField(
                  controller: _subjectController,
                  textCapitalization: TextCapitalization.characters,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  decoration: _inputStyle(
                    "Add subject",
                    Icons.add_task_rounded,
                    isDark,
                    primaryColor,
                  ),
                  onSubmitted: (_) => _addSubject(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 4,
                child: DropdownButtonFormField<String>(
                  initialValue: _subjectType,
                  dropdownColor: isDark
                      ? const Color(0xFF2C2C2C)
                      : Colors.white,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                    fontSize: 13,
                  ),
                  isExpanded: true,
                  decoration: _inputStyle(
                    "Type",
                    Icons.category_rounded,
                    isDark,
                    primaryColor,
                  ),
                  items: ['Compulsory', 'Elective']
                      .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (val) => setState(() => _subjectType = val!),
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
                onPressed: _addSubject,
                child: const Icon(Icons.add_rounded, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 30),

          Expanded(
            child: _selectedClassName == null
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
    final subs = _classSubjects
        .where(
          (s) => s['class_name'] == _selectedClassName && s['type'] == type,
        )
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
                onTap: () => _editSubject(s),
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
                        onTap: () => _removeSubject(s),
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

  Widget _buildBottomBar(bool isDark, Color primaryColor) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.white10 : Colors.grey.shade200,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        height: 55,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: primaryColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          onPressed: _isSaving ? null : _saveConfig,
          icon: _isSaving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: TridetaLoader(color: Colors.white),
                )
              : const Icon(
                  Icons.security_update_good_rounded,
                  color: Colors.white,
                ),
          label: Text(
            _isSaving ? "SAVING..." : "SECURE SYSTEM CONFIGURATION",
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
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
}
