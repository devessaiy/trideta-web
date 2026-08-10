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
  // 🚨 LOGIC ENGINE (100% UNTOUCHED)
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
          .select(
            'id, name, override_session, override_term, list_order, promotion_criteria',
          )
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
              'override_session': c['override_session'],
              'override_term': c['override_term'],
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
                    'override_session': null,
                    'override_term': null,
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
            'override_session': c['override_session'],
            'override_term': c['override_term'],
            'promotion_criteria': c['promotion_criteria'],
            'list_order': i,
          });
        } else {
          classesToUpdate.add({
            'id': c['id'],
            'school_id': _schoolId,
            'name': c['name'],
            'override_session': c['override_session'],
            'override_term': c['override_term'],
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

      if (subjectsToInsert.isNotEmpty)
        await _supabase.from('class_subjects').insert(subjectsToInsert);
      if (subjectsToUpdate.isNotEmpty)
        await _supabase.from('class_subjects').upsert(subjectsToUpdate);

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

        cls['override_session'] = result['session'];
        cls['override_term'] = result['term'];
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
        'override_session': null,
        'override_term': null,
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

class ClassesPanel extends StatelessWidget {
  final List<Map<String, dynamic>> classes;
  final TextEditingController classController;
  final bool isDark;
  final Color primaryColor;
  final VoidCallback onAddClass;
  final Future<void> Function(Map<String, dynamic>) onEditClass;
  final void Function(Map<String, dynamic>) onRemoveClass;
  final void Function(int, int) onReorder;

  const ClassesPanel({
    super.key,
    required this.classes,
    required this.classController,
    required this.isDark,
    required this.primaryColor,
    required this.onAddClass,
    required this.onEditClass,
    required this.onRemoveClass,
    required this.onReorder,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: classController,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  hintText: 'New class name',
                  filled: true,
                  fillColor: isDark ? Colors.white10 : Colors.grey.shade100,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: primaryColor,
                minimumSize: const Size(120, 52),
              ),
              onPressed: onAddClass,
              child: const Text('Add'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: classes.isEmpty
              ? Center(
                  child: Text(
                    'No classes configured yet.',
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                )
              : ReorderableListView.builder(
                  onReorder: onReorder,
                  itemCount: classes.length,
                  itemBuilder: (context, index) {
                    final cls = classes[index];
                    final displayName = cls['name']?.toString() ?? '';
                    final session = cls['override_session']?.toString() ?? '';
                    final term = cls['override_term']?.toString() ?? '';
                    final subtitle = [
                      if (session.isNotEmpty) 'Session: $session',
                      if (term.isNotEmpty) 'Term: $term',
                    ].join(' • ');

                    return Card(
                      key: ValueKey(cls['id'] ?? displayName),
                      color: isDark ? Colors.white10 : Colors.white,
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      child: ListTile(
                        title: Text(
                          displayName,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: subtitle.isNotEmpty ? Text(subtitle) : null,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined),
                              color: primaryColor,
                              onPressed: () => onEditClass(cls),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              color: Colors.redAccent,
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
    );
  }
}

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
  final Future<void> Function(Map<String, dynamic>) onEditSubject;
  final void Function(Map<String, dynamic>) onRemoveSubject;
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
    final filteredSubjects = selectedClassName == null
        ? <Map<String, dynamic>>[]
        : classSubjects
              .where((s) => s['class_name'] == selectedClassName)
              .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value: selectedClassName,
                items: classes
                    .map(
                      (cls) => DropdownMenuItem(
                        value: cls['name']?.toString(),
                        child: Text(cls['name']?.toString() ?? ''),
                      ),
                    )
                    .toList(),
                onChanged: onTargetClassChanged,
                decoration: InputDecoration(
                  labelText: 'Class',
                  filled: true,
                  fillColor: isDark ? Colors.white10 : Colors.grey.shade100,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<String>(
                value: subjectType,
                items: const [
                  DropdownMenuItem(
                    value: 'Compulsory',
                    child: Text('Compulsory'),
                  ),
                  DropdownMenuItem(value: 'Elective', child: Text('Elective')),
                ],
                onChanged: onSubjectTypeChanged,
                decoration: InputDecoration(
                  labelText: 'Type',
                  filled: true,
                  fillColor: isDark ? Colors.white10 : Colors.grey.shade100,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: subjectController,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  hintText: 'New subject name',
                  filled: true,
                  fillColor: isDark ? Colors.white10 : Colors.grey.shade100,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: primaryColor,
                minimumSize: const Size(120, 52),
              ),
              onPressed: onAddSubject,
              child: const Text('Add'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              selectedClassName == null
                  ? 'Subjects'
                  : 'Subjects for $selectedClassName',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            TextButton.icon(
              onPressed: onCopySubjects,
              icon: Icon(Icons.copy_all_outlined, color: primaryColor),
              label: Text(
                'Copy Subjects',
                style: TextStyle(color: primaryColor),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: filteredSubjects.isEmpty
              ? Center(
                  child: Text(
                    selectedClassName == null
                        ? 'Please select a class first.'
                        : 'No subjects registered for this class.',
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount: filteredSubjects.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final subject = filteredSubjects[index];
                    return Card(
                      color: isDark ? Colors.white10 : Colors.white,
                      child: ListTile(
                        title: Text(
                          subject['subject_name']?.toString() ?? '',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(subject['type']?.toString() ?? ''),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined),
                              color: primaryColor,
                              onPressed: () => onEditSubject(subject),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              color: Colors.redAccent,
                              onPressed: () => onRemoveSubject(subject),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

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
  late final TextEditingController _nameController;
  late final TextEditingController _sessionController;
  late final TextEditingController _termController;
  late final TextEditingController _passMarkController;

  @override
  void initState() {
    super.initState();
    final promoCriteria = widget.schoolClass['promotion_criteria'] ?? {};
    _nameController = TextEditingController(
      text: widget.schoolClass['name']?.toString() ?? '',
    );
    _sessionController = TextEditingController(
      text: widget.schoolClass['override_session']?.toString() ?? '',
    );
    _termController = TextEditingController(
      text: widget.schoolClass['override_term']?.toString() ?? '',
    );
    _passMarkController = TextEditingController(
      text: promoCriteria['pass_mark']?.toString() ?? '40',
    );
  }

  @override
  Widget build(BuildContext context) {
    final background = widget.isDark ? const Color(0xFF1E1E1E) : Colors.white;
    return AlertDialog(
      backgroundColor: background,
      title: const Text('Edit Class'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Class name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _sessionController,
              decoration: const InputDecoration(labelText: 'Override session'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _termController,
              decoration: const InputDecoration(labelText: 'Override term'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passMarkController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Promotion pass mark',
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Subjects: ${widget.availableSubjects.length}',
                style: TextStyle(
                  color: widget.isDark ? Colors.white70 : Colors.black54,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: widget.primaryColor),
          onPressed: () {
            final newName = _nameController.text.trim().toUpperCase();
            final promoCriteria = {
              'pass_mark': int.tryParse(_passMarkController.text) ?? 40,
              'core_subjects':
                  widget.schoolClass['promotion_criteria']?['core_subjects'] ??
                  [],
            };
            Navigator.of(context).pop({
              'newName': newName,
              'session': _sessionController.text.trim(),
              'term': _termController.text.trim(),
              'promo_criteria': promoCriteria,
            });
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

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
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  Widget build(BuildContext context) {
    final background = widget.isDark ? const Color(0xFF1E1E1E) : Colors.white;
    return AlertDialog(
      backgroundColor: background,
      title: const Text('Edit Subject'),
      content: TextField(
        controller: _controller,
        textCapitalization: TextCapitalization.characters,
        decoration: const InputDecoration(labelText: 'Subject name'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: widget.primaryColor),
          onPressed: () {
            Navigator.of(context).pop(_controller.text.trim().toUpperCase());
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

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
  final Set<String> _selectedClasses = {};

  @override
  Widget build(BuildContext context) {
    final background = widget.isDark ? const Color(0xFF1E1E1E) : Colors.white;
    return AlertDialog(
      backgroundColor: background,
      title: Text('Copy subjects from ${widget.sourceClassName}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: widget.availableClasses.map((className) {
            return CheckboxListTile(
              value: _selectedClasses.contains(className),
              title: Text(className),
              onChanged: (checked) {
                setState(() {
                  if (checked == true) {
                    _selectedClasses.add(className);
                  } else {
                    _selectedClasses.remove(className);
                  }
                });
              },
            );
          }).toList(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: widget.primaryColor),
          onPressed: () => Navigator.of(context).pop(_selectedClasses.toList()),
          child: const Text('Copy'),
        ),
      ],
    );
  }
}
