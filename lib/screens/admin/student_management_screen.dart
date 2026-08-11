import 'package:trideta_v2/widgets/trideta_loader.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// 🚨 IMPORT: Pulls in all separated UI components!
import 'components/student_desktop_header.dart';
import 'components/student_mobile_header.dart';
import 'components/student_controls_bar.dart';
import 'components/student_list_card.dart';
import 'components/sticky_controls_delegate.dart';

class StudentManagementScreen extends StatefulWidget {
  const StudentManagementScreen({super.key});

  @override
  State<StudentManagementScreen> createState() =>
      _StudentManagementScreenState();
}

class _StudentManagementScreenState extends State<StudentManagementScreen> {
  final _supabase = Supabase.instance.client;

  String? _schoolId;
  String _searchQuery = "";

  Map<String, String> _formMasters = {};
  List<String> _officialClassOrder = [];
  List<Map<String, dynamic>> _allClassesData = [];

  bool _isLoading = true;
  List<dynamic> _students = [];
  List<dynamic> _allStudentsUnfiltered = [];

  String _selectedClassFilter = 'All Classes';
  String _selectedSort = 'First Name A-Z';
  List<String> _availableClasses = ['All Classes'];

  bool _isSelecting = false;
  final Set<String> _selectedStudentIds = {};

  String _userEmail = "Admin";

  @override
  void initState() {
    super.initState();
    _fetchSchoolId();
  }

  Future<void> _fetchSchoolId() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user != null) {
        _userEmail = user.email ?? "Admin";
        final profile = await _supabase
            .from('profiles')
            .select('school_id')
            .eq('id', user.id)
            .single();
        _schoolId = profile['school_id'];
        if (_schoolId != null) {
          await Future.wait([_fetchClassesAndOrder(), _fetchFormMasters()]);
          _fetchStudents();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showError("Failed to verify school ID.");
      }
    }
  }

  Future<void> _fetchClassesAndOrder() async {
    try {
      final classesResponse = await _supabase
          .from('classes')
          .select('id, name')
          .eq('school_id', _schoolId!)
          .order('list_order', ascending: true);

      _allClassesData = List<Map<String, dynamic>>.from(classesResponse);
      _officialClassOrder = _allClassesData
          .map((c) => c['name'].toString())
          .toList();
    } catch (e) {
      debugPrint("Failed to fetch official class order: $e");
    }
  }

  Future<void> _fetchFormMasters() async {
    try {
      final assignments = await _supabase
          .from('staff_assignments')
          .select(
            'class_assigned, profiles!staff_assignments_staff_id_fkey (full_name)',
          )
          .eq('school_id', _schoolId!)
          .isFilter('subject_assigned', null);

      Map<String, String> masterMap = {};
      for (var assignment in assignments) {
        String classLevel = assignment['class_assigned']?.toString() ?? '';
        var profile = assignment['profiles'];
        if (classLevel.isNotEmpty && profile != null) {
          String masterName =
              profile['full_name']?.toString() ?? 'Unknown Staff';
          masterMap[classLevel] = masterName;
        }
      }

      if (mounted) setState(() => _formMasters = masterMap);
    } catch (e) {
      debugPrint("Failed to fetch form masters: $e");
    }
  }

  Future<void> _fetchStudents() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final response = await _supabase
          .from('students')
          .select('*')
          .eq('school_id', _schoolId!);
      final List<dynamic> loadedStudents = List.from(response);

      Set<String> classSet = {'All Classes'};
      classSet.addAll(_officialClassOrder);

      bool hasUnassigned = false;

      for (var s in loadedStudents) {
        final cl = s['class_level']?.toString();
        if (cl == null || cl.isEmpty || !_officialClassOrder.contains(cl)) {
          hasUnassigned = true;
        }
      }

      if (hasUnassigned) {
        classSet.add('Unassigned');
      }

      if (mounted) {
        setState(() {
          _allStudentsUnfiltered = loadedStudents;
          _availableClasses = classSet.toList();

          _availableClasses.sort((a, b) {
            if (a == 'All Classes') return -1;
            if (b == 'All Classes') return 1;
            if (a == 'Unassigned') return 1;
            if (b == 'Unassigned') return -1;
            int indexA = _officialClassOrder.indexOf(a);
            int indexB = _officialClassOrder.indexOf(b);
            if (indexA == -1 && indexB == -1) return a.compareTo(b);
            if (indexA == -1) return 1;
            if (indexB == -1) return -1;
            return indexA.compareTo(indexB);
          });

          if (!_availableClasses.contains(_selectedClassFilter)) {
            _selectedClassFilter = 'All Classes';
          }

          _filterAndSortStudents();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showError("Failed to fetch students. Please try again.");
      }
    }
  }

  void _filterAndSortStudents() {
    List<dynamic> filtered = List.from(_allStudentsUnfiltered);

    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((s) {
        final fName = s['first_name']?.toString().toLowerCase() ?? '';
        final lName = s['last_name']?.toString().toLowerCase() ?? '';
        final query = _searchQuery.toLowerCase();
        return fName.contains(query) || lName.contains(query);
      }).toList();
    }

    if (_selectedClassFilter != 'All Classes') {
      if (_selectedClassFilter == 'Unassigned') {
        filtered = filtered.where((s) {
          final cl = s['class_level']?.toString();
          return cl == null || cl.isEmpty || !_officialClassOrder.contains(cl);
        }).toList();
      } else {
        filtered = filtered
            .where((s) => s['class_level'] == _selectedClassFilter)
            .toList();
      }
    }

    filtered.sort((a, b) {
      switch (_selectedSort) {
        case 'First Name A-Z':
          return (a['first_name'] ?? '').compareTo(b['first_name'] ?? '');
        case 'First Name Z-A':
          return (b['first_name'] ?? '').compareTo(a['first_name'] ?? '');
        case 'Date Added (Newest)':
          DateTime dtA = a['created_at'] != null
              ? DateTime.parse(a['created_at'])
              : DateTime.now();
          DateTime dtB = b['created_at'] != null
              ? DateTime.parse(b['created_at'])
              : DateTime.now();
          return dtB.compareTo(dtA);
        case 'Date Added (Oldest)':
          DateTime dtA = a['created_at'] != null
              ? DateTime.parse(a['created_at'])
              : DateTime.now();
          DateTime dtB = b['created_at'] != null
              ? DateTime.parse(b['created_at'])
              : DateTime.now();
          return dtA.compareTo(dtB);
        default:
          return 0;
      }
    });

    setState(() {
      _students = filtered;
      _selectedStudentIds.removeWhere(
        (id) => !_students.any((student) => student['id'] == id),
      );
      if (_selectedStudentIds.isEmpty) _isSelecting = false;
    });
  }

  void _toggleSelection(String studentId) {
    setState(() {
      if (_selectedStudentIds.contains(studentId)) {
        _selectedStudentIds.remove(studentId);
      } else {
        _selectedStudentIds.add(studentId);
      }
      _isSelecting = _selectedStudentIds.isNotEmpty;
    });
  }

  void _selectAll() {
    setState(() {
      if (_selectedStudentIds.length == _students.length) {
        _selectedStudentIds.clear();
        _isSelecting = false;
      } else {
        _selectedStudentIds.addAll(_students.map((s) => s['id'] as String));
        _isSelecting = true;
      }
    });
  }

  void _showPromotionDialog(Color primaryColor) {
    String? selectedTargetClass;
    bool isProcessing = false;

    List<String> validTargetClasses = List.from(_officialClassOrder);
    validTargetClasses.addAll(["Graduated", "Withdrawn", "Expelled"]);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Text(
                "Reassign ${_selectedStudentIds.length} Students",
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "Select the new target class for the selected students. This will update their current active class immediately.",
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(height: 20),
                  DropdownButtonFormField<String>(
                    decoration: InputDecoration(
                      labelText: "Target Class / Status",
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    initialValue: selectedTargetClass,
                    items: validTargetClasses.map((String c) {
                      return DropdownMenuItem(value: c, child: Text(c));
                    }).toList(),
                    onChanged: (val) =>
                        setDialogState(() => selectedTargetClass = val),
                  ),
                  if (isProcessing)
                    const Padding(
                      padding: EdgeInsets.only(top: 20.0),
                      child: TridetaLoader(),
                    ),
                ],
              ),
              actions: [
                if (!isProcessing)
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text(
                      "CANCEL",
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                if (!isProcessing)
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: selectedTargetClass == null
                        ? null
                        : () async {
                            setDialogState(() => isProcessing = true);
                            try {
                              String? newClassId;
                              if (selectedTargetClass != "Graduated" &&
                                  selectedTargetClass != "Withdrawn" &&
                                  selectedTargetClass != "Expelled") {
                                var targetClassMap = _allClassesData.firstWhere(
                                  (c) => c['name'] == selectedTargetClass,
                                  orElse: () => {},
                                );
                                newClassId = targetClassMap['id'];
                              }

                              Map<String, dynamic> updatePayload = {
                                'class_level': selectedTargetClass,
                              };
                              if (newClassId != null) {
                                updatePayload['class_id'] = newClassId;
                              }

                              for (String studentId in _selectedStudentIds) {
                                await _supabase
                                    .from('students')
                                    .update(updatePayload)
                                    .eq('id', studentId);
                              }

                              if (context.mounted) {
                                Navigator.pop(ctx);
                                _showSuccess(
                                  "${_selectedStudentIds.length} students reassigned to $selectedTargetClass",
                                );
                                setState(() {
                                  _selectedStudentIds.clear();
                                  _isSelecting = false;
                                });
                                _fetchStudents();
                              }
                            } catch (e) {
                              if (context.mounted) {
                                setDialogState(() => isProcessing = false);
                                _showError("Failed to reassign students: $e");
                              }
                            }
                          },
                    child: const Text(
                      "CONFIRM ASSIGNMENT",
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

  void _showError(String msg) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  void _showSuccess(String msg) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.green));
  }

  // ===========================================================================
  // 🚨 UI BUILDERS
  // ===========================================================================

  Widget _buildClassCard(
    String className,
    int count,
    String formMaster,
    Color primaryColor,
    bool isDark,
    Color cardColor,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          setState(() {
            _selectedClassFilter = className;
            _searchQuery = "";
          });
          _filterAndSortStudents();
        },
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
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
                      Icons.class_rounded,
                      color: primaryColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      className,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                "$count Students",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(
                    Icons.person_outline_rounded,
                    size: 14,
                    color: Colors.grey.shade500,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      formMaster,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color primaryColor = Theme.of(context).primaryColor;
    Color bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC);
    Color cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    bool isDesktop = MediaQuery.of(context).size.width > 800;
    double horizontalPadding = isDesktop ? 30.0 : 16.0;

    int totalStudents = _students.length;
    int maleCount = _students
        .where((s) => s['gender']?.toString().toLowerCase() == 'male')
        .length;
    int femaleCount = _students
        .where((s) => s['gender']?.toString().toLowerCase() == 'female')
        .length;

    List<String> classesToShow = List.from(_officialClassOrder);
    int unassignedCount = _allStudentsUnfiltered.where((s) {
      final cl = s['class_level']?.toString();
      return cl == null || cl.isEmpty || !_officialClassOrder.contains(cl);
    }).length;

    if (unassignedCount > 0) {
      if (!classesToShow.contains('Unassigned')) {
        classesToShow.add('Unassigned');
      }
    }

    Widget rosterContent = CustomScrollView(
      slivers: [
        // ─── MODULAR TOP HEADER ───
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            horizontalPadding,
            horizontalPadding,
            16.0,
          ),
          sliver: SliverToBoxAdapter(
            child: totalStudents == 0
                ? const SizedBox.shrink()
                : (isDesktop
                      ? StudentDesktopHeader(
                          primaryColor: primaryColor,
                          isDark: isDark,
                          totalStudents: totalStudents,
                          maleCount: maleCount,
                          femaleCount: femaleCount,
                          onRefresh: _fetchStudents,
                        )
                      : StudentMobileHeader(
                          primaryColor: primaryColor,
                          isDark: isDark,
                          totalStudents: totalStudents,
                          maleCount: maleCount,
                          femaleCount: femaleCount,
                          onRefresh: _fetchStudents,
                        )),
          ),
        ),

        if (_isLoading)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 50.0),
              child: Center(child: TridetaLoader(color: primaryColor)),
            ),
          )
        // ─── STATE 1: CLASS ROSTER GRID ───
        else if (_selectedClassFilter == 'All Classes') ...[
          SliverPadding(
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: 10,
            ),
            sliver: SliverToBoxAdapter(
              child: Text(
                "Select a Class to View Roster",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Colors.grey.shade500,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: isDesktop ? 3 : 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: isDesktop ? 1.5 : 1.1,
              ),
              delegate: SliverChildBuilderDelegate((context, index) {
                String className = classesToShow[index];
                int count;
                if (className == 'Unassigned') {
                  count = unassignedCount;
                } else {
                  count = _allStudentsUnfiltered
                      .where((s) => s['class_level'] == className)
                      .length;
                }
                String formMaster = _formMasters[className] ?? 'No Form Master';

                return _buildClassCard(
                  className,
                  count,
                  formMaster,
                  primaryColor,
                  isDark,
                  cardColor,
                );
              }, childCount: classesToShow.length),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 50)),
        ]
        // ─── STATE 2: STUDENT DRILL-DOWN LIST ───
        else ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: horizontalPadding,
                vertical: 10,
              ),
              child: Row(
                children: [
                  InkWell(
                    onTap: () {
                      setState(() {
                        _selectedClassFilter = 'All Classes';
                        _searchQuery = "";
                        _isSelecting = false;
                        _selectedStudentIds.clear();
                      });
                      _filterAndSortStudents();
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: primaryColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.arrow_back_rounded,
                            color: primaryColor,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            "Back to Classes",
                            style: TextStyle(
                              color: primaryColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Text(
                      "$_selectedClassFilter Roster",
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ─── MODULAR STICKY CONTROLS ───
          SliverPersistentHeader(
            pinned: true,
            delegate: StickyControlsDelegate(
              bgColor: bgColor,
              height: isDesktop ? 80.0 : 170.0,
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
              child: StudentControlsBar(
                primaryColor: primaryColor,
                isDark: isDark,
                isDesktop: isDesktop,
                searchQuery: _searchQuery,
                selectedClassFilter: _selectedClassFilter,
                selectedSort: _selectedSort,
                availableClasses: _availableClasses,
                onSearchChanged: (val) {
                  setState(() => _searchQuery = val);
                  _filterAndSortStudents();
                },
                onClassChanged: (newValue) {
                  if (newValue != null) {
                    setState(() {
                      _selectedClassFilter = newValue;
                      _isSelecting = false;
                      _selectedStudentIds.clear();
                    });
                    _filterAndSortStudents();
                  }
                },
                onSortChanged: (newValue) {
                  if (newValue != null) {
                    setState(() => _selectedSort = newValue);
                    _filterAndSortStudents();
                  }
                },
              ),
            ),
          ),

          // ─── MODULAR STUDENT LIST CARDS ───
          SliverPadding(
            padding: EdgeInsets.only(
              left: horizontalPadding,
              right: horizontalPadding,
              bottom: horizontalPadding,
            ),
            sliver: _students.isEmpty
                ? SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 50.0),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.search_off_rounded,
                              size: 80,
                              color: Colors.grey.shade300,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _searchQuery.isEmpty
                                  ? "No Students in this class"
                                  : "No Students Found",
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 8),
                            if (_searchQuery.isNotEmpty)
                              Text(
                                "Try adjusting your search.",
                                style: TextStyle(color: Colors.grey.shade500),
                              ),
                          ],
                        ),
                      ),
                    ),
                  )
                : SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      return StudentListCard(
                        student: _students[index],
                        isDark: isDark,
                        primaryColor: primaryColor,
                        isSelected: _selectedStudentIds.contains(
                          _students[index]['id'],
                        ),
                        isSelecting: _isSelecting,
                        onToggleSelection: _toggleSelection,
                        onRefresh: _fetchStudents,
                      );
                    }, childCount: _students.length),
                  ),
          ),
        ],
      ],
    );

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text(
          "Student Directory",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: bgColor,
        foregroundColor: isDark ? Colors.white : Colors.black87,
        elevation: 0,
        centerTitle: true,
        actions: [
          if (_isSelecting)
            IconButton(
              icon: const Icon(Icons.select_all_rounded),
              onPressed: _selectAll,
              tooltip: "Select All",
            ),
          if (_isSelecting)
            IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: () => setState(() {
                _selectedStudentIds.clear();
                _isSelecting = false;
              }),
            ),
          if (!_isSelecting &&
              !isDesktop &&
              _selectedClassFilter != 'All Classes')
            IconButton(
              icon: const Icon(Icons.checklist_rounded),
              onPressed: () => setState(() => _isSelecting = true),
            ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth > 800) {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: Container(
                  decoration: BoxDecoration(
                    color: bgColor,
                    border: Border.symmetric(
                      vertical: BorderSide(
                        color: isDark ? Colors.white10 : Colors.grey.shade200,
                      ),
                    ),
                  ),
                  child: rosterContent,
                ),
              ),
            );
          } else {
            return rosterContent;
          }
        },
      ),
      floatingActionButton: _selectedStudentIds.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: () => _showPromotionDialog(primaryColor),
              backgroundColor: primaryColor,
              icon: const Icon(Icons.move_up_rounded, color: Colors.white),
              label: const Text(
                "REASSIGN",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            )
          : null,
    );
  }
}
