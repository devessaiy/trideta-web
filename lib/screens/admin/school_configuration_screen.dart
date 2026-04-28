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

      // 🚨 ADDED: Dictionary to grab the class UUIDs
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

      // 🚨 SMART SPLIT: Subjects
      List<Map<String, dynamic>> subjectsToInsert = [];
      List<Map<String, dynamic>> subjectsToUpdate = [];

      for (var s in _classSubjects) {
        if (s['id'] == null) {
          subjectsToInsert.add({
            'school_id': _schoolId,
            'class_name': s['class_name'],
            'class_id':
                classNameToId[s['class_name']], // 🚨 ADDED: Link the UUID directly!
            'subject_name': s['subject_name'],
            'type': s['type'],
          });
        } else {
          subjectsToUpdate.add({
            'id': s['id'],
            'school_id': _schoolId,
            'class_name': s['class_name'],
            'class_id':
                classNameToId[s['class_name']], // 🚨 ADDED: Link the UUID directly!
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

    // Get the actual subjects that currently belong to the selected class
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
              'id': null, // It's a new entry for the target class
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
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
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
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: ListView(
                          children: availableClasses.map((cls) {
                            return CheckboxListTile(
                              title: Text(
                                cls,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              value: selectedTargets.contains(cls),
                              activeColor: Theme.of(context).primaryColor,
                              onChanged: (val) {
                                setDialogState(() {
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
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
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
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // --- UI BUILDING ---
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC);
    Color primaryColor = Theme.of(context).primaryColor;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text(
          "School Configuration",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth > 900) {
            // 💻 DESKTOP TWO-COLUMN LAYOUT
            return Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 1200),
                padding: const EdgeInsets.all(20),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 4,
                      child: _buildClassesPanel(isDark, primaryColor),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      flex: 6,
                      child: _buildSubjectsPanel(isDark, primaryColor),
                    ),
                  ],
                ),
              ),
            );
          } else {
            // 📱 MOBILE TAB LAYOUT
            return DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  Container(
                    color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                    child: TabBar(
                      labelColor: primaryColor,
                      unselectedLabelColor: Colors.grey,
                      indicatorColor: primaryColor,
                      indicatorWeight: 3,
                      labelStyle: const TextStyle(fontWeight: FontWeight.bold),
                      tabs: const [
                        Tab(text: "Classes"),
                        Tab(text: "Subjects"),
                      ],
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _buildClassesPanel(isDark, primaryColor),
                        _buildSubjectsPanel(isDark, primaryColor),
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Manage Classes",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _classController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: _inputStyle(
                    "Add new class",
                    Icons.school,
                    isDark,
                    primaryColor,
                  ),
                  onSubmitted: (_) => _addClass(),
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
          const SizedBox(height: 20),
          Expanded(
            child: _classes.isEmpty
                ? const Center(
                    child: Text(
                      "No classes found",
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
                      return Card(
                        key: ValueKey(cls['name']),
                        margin: const EdgeInsets.only(bottom: 8),
                        color: isDark
                            ? Colors.white.withOpacity(0.02)
                            : Colors.grey[50],
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(
                            color: isDark
                                ? Colors.white10
                                : Colors.grey.shade200,
                          ),
                        ),
                        child: ListTile(
                          title: Text(
                            cls['name'],
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          leading: const Icon(
                            Icons.drag_indicator,
                            color: Colors.grey,
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(
                                  Icons.edit,
                                  size: 18,
                                  color: Colors.blue,
                                ),
                                onPressed: () => _editClass(cls),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete_outline,
                                  size: 18,
                                  color: Colors.red,
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

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
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
              const Text(
                "Manage Subjects",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              if (_classSubjects.isNotEmpty)
                TextButton.icon(
                  onPressed: _showDuplicateDialog,
                  icon: const Icon(Icons.copy_all, size: 18),
                  label: const Text("Copy to..."),
                  style: TextButton.styleFrom(
                    foregroundColor: primaryColor,
                    textStyle: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 15),

          // Target Class Dropdown
          Container(
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.03) : Colors.grey[50],
              borderRadius: BorderRadius.circular(15),
            ),
            child: DropdownButtonFormField<String>(
              value: _selectedClassName,
              decoration: _inputStyle(
                "Target Class",
                Icons.filter_alt,
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
          ),
          const SizedBox(height: 15),

          // Input Row
          Row(
            children: [
              Expanded(
                flex: 5,
                child: TextField(
                  controller: _subjectController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: _inputStyle(
                    "Add subject",
                    Icons.book,
                    isDark,
                    primaryColor,
                  ),
                  onSubmitted: (_) => _addSubject(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 4,
                child: DropdownButtonFormField<String>(
                  value: _subjectType,
                  isExpanded:
                      true, // 🚨 Added to force text to stay inside bounds
                  decoration: _inputStyle(
                    "Type",
                    Icons.category,
                    isDark,
                    primaryColor,
                  ),
                  items: ['Compulsory', 'Elective']
                      .map(
                        (t) => DropdownMenuItem(
                          value: t,
                          child: Text(
                            t,
                            style: const TextStyle(
                              fontSize: 12,
                            ), // 🚨 Scaled down slightly for mobile
                            overflow: TextOverflow
                                .ellipsis, // 🚨 Prevents overlay by adding "..." if too tight
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (val) => setState(() => _subjectType = val!),
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

          // Subjects List
          Expanded(
            child: _selectedClassName == null
                ? const Center(child: Text("Select a class to view subjects"))
                : ListView(
                    children: [
                      _buildSubjectCategory("Compulsory", isDark),
                      const SizedBox(height: 15),
                      _buildSubjectCategory("Elective", isDark),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubjectCategory(String type, bool isDark) {
    final subs = _classSubjects
        .where(
          (s) => s['class_name'] == _selectedClassName && s['type'] == type,
        )
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "$type Subjects",
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 5),
        if (subs.isEmpty)
          const Text(
            "None added",
            style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey),
          )
        else
          Wrap(
            spacing: 8,
            children: subs.map((s) {
              return InputChip(
                label: Text(
                  s['subject_name'],
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                backgroundColor: isDark
                    ? Colors.white.withOpacity(0.05)
                    : (type == 'Compulsory'
                          ? Colors.red[50]
                          : Colors.green[50]),
                side: BorderSide.none,
                deleteIconColor: Colors.red,
                onPressed: () => _editSubject(s),
                onDeleted: () => _removeSubject(s),
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
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
        ),
      ),
    );
  }
}
