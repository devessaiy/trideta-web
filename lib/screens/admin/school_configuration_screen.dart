import 'package:trideta_v2/utils/auth_error_handler.dart';
import 'package:trideta_v2/widgets/trideta_loader.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// 🚨 IMPORT: Points to the separated UI components
import '../school_configuration_widgets.dart';

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
  // 🚨 LOGIC ENGINE (GLOBAL CALENDAR ENFORCED)
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

      // 🚨 REMOVED override_session and override_term from fetch
      final classesData = await _supabase
          .from('classes')
          .select('id, name, list_order, promotion_criteria')
          .eq('school_id', _schoolId!)
          .order('list_order', ascending: true);

      final subjectsData = await _supabase
          .from('class_subjects')
          .select()
          .eq('school_id', _schoolId!);

      if (mounted) {
        setState(() {
          _classes = List<Map<String, dynamic>>.from(classesData).map((c) {
            return {
              'id': c['id'],
              'name': c['name'],
              'promotion_criteria':
                  c['promotion_criteria'] ??
                  {'pass_mark': 40, 'core_subjects': []},
              'list_order': c['list_order'],
            };
          }).toList();

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
                    'promotion_criteria': {
                      'pass_mark': 40,
                      'core_subjects': [],
                    },
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
            'promotion_criteria': c['promotion_criteria'],
            'list_order': i,
          });
        } else {
          classesToUpdate.add({
            'id': c['id'],
            'school_id': _schoolId,
            'name': c['name'],
            'promotion_criteria': c['promotion_criteria'],
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
      if (mounted) {
        setState(() => _isSaving = false);
        showAuthErrorDialog("Failed to save. Please check your connection.");
      }
    }
  }

  // ===========================================================================
  // 🚨 DIALOG HANDLERS
  // ===========================================================================

  Future<void> _editClass(Map<String, dynamic> cls) async {
    final oldName = cls['name'];
    List<String> availableSubjects = _classSubjects
        .where((s) => s['class_name'] == oldName)
        .map((s) => s['subject_name'].toString())
        .toList();

    Map<String, dynamic>? result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => EditClassDialog(
        schoolClass: cls,
        availableSubjects: availableSubjects,
        primaryColor: Theme.of(context).primaryColor,
        isDark: Theme.of(context).brightness == Brightness.dark,
      ),
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

        cls['promotion_criteria'] = result['promo_criteria'];
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
        'promotion_criteria': {'pass_mark': 40, 'core_subjects': []},
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
    String? newName = await showDialog<String>(
      context: context,
      builder: (ctx) => EditSubjectDialog(
        initialName: subject['subject_name'],
        primaryColor: Theme.of(context).primaryColor,
        isDark: Theme.of(context).brightness == Brightness.dark,
      ),
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

  void _showDuplicateDialog() async {
    if (_classes.length <= 1) {
      _showDuplicateAlert("No other classes available to copy to.");
      return;
    }

    List<String> availableClasses = _classes
        .map((c) => c['name'] as String)
        .where((name) => name != _selectedClassName)
        .toList();

    List<String>? selectedTargets = await showDialog<List<String>>(
      context: context,
      builder: (ctx) => CopySubjectsDialog(
        sourceClassName: _selectedClassName!,
        availableClasses: availableClasses,
        primaryColor: Theme.of(context).primaryColor,
        isDark: Theme.of(context).brightness == Brightness.dark,
      ),
    );

    if (selectedTargets != null && selectedTargets.isNotEmpty) {
      _applySubjectsToMultipleClasses(selectedTargets);
    }
  }

  // ===========================================================================
  // 🚨 CLEAN, MODULARIZED UI
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
                      child: ClassesPanel(
                        classes: _classes,
                        classController: _classController,
                        isDark: isDark,
                        primaryColor: primaryColor,
                        onAddClass: _addClass,
                        onEditClass: _editClass,
                        onRemoveClass: _removeClass,
                        onReorder: (oldIdx, newIdx) {
                          setState(() {
                            if (newIdx > oldIdx) newIdx -= 1;
                            _classes.insert(newIdx, _classes.removeAt(oldIdx));
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      flex: 6,
                      child: SubjectsPanel(
                        classes: _classes,
                        classSubjects: _classSubjects,
                        subjectController: _subjectController,
                        selectedClassName: _selectedClassName,
                        subjectType: _subjectType,
                        isDark: isDark,
                        primaryColor: primaryColor,
                        onTargetClassChanged: (val) =>
                            setState(() => _selectedClassName = val),
                        onSubjectTypeChanged: (val) =>
                            setState(() => _subjectType = val!),
                        onAddSubject: _addSubject,
                        onEditSubject: _editSubject,
                        onRemoveSubject: _removeSubject,
                        onCopySubjects: _showDuplicateDialog,
                      ),
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
                          child: ClassesPanel(
                            classes: _classes,
                            classController: _classController,
                            isDark: isDark,
                            primaryColor: primaryColor,
                            onAddClass: _addClass,
                            onEditClass: _editClass,
                            onRemoveClass: _removeClass,
                            onReorder: (oldIdx, newIdx) {
                              setState(() {
                                if (newIdx > oldIdx) newIdx -= 1;
                                _classes.insert(
                                  newIdx,
                                  _classes.removeAt(oldIdx),
                                );
                              });
                            },
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: SubjectsPanel(
                            classes: _classes,
                            classSubjects: _classSubjects,
                            subjectController: _subjectController,
                            selectedClassName: _selectedClassName,
                            subjectType: _subjectType,
                            isDark: isDark,
                            primaryColor: primaryColor,
                            onTargetClassChanged: (val) =>
                                setState(() => _selectedClassName = val),
                            onSubjectTypeChanged: (val) =>
                                setState(() => _subjectType = val!),
                            onAddSubject: _addSubject,
                            onEditSubject: _editSubject,
                            onRemoveSubject: _removeSubject,
                            onCopySubjects: _showDuplicateDialog,
                          ),
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
}
