import 'package:trideta_v2/widgets/trideta_loader.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:trideta_v2/screens/admin/student_admission_screen.dart';
import 'package:trideta_v2/screens/admin/student_profile_screen.dart';
import 'package:trideta_v2/screens/admin/id_card_generator_screen.dart';

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

  // Stores the mapped Form Masters: { "jss1": "John Doe", "ss3": "Jane Smith" }
  Map<String, String> _formMasters = {};

  // Stores the official class order defined by the Admin
  List<String> _officialClassOrder = [];

  // Stores the full class data with UUIDs for the promotion engine
  List<Map<String, dynamic>> _allClassesData = [];

  bool _isLoading = true;
  List<dynamic> _students = [];
  List<dynamic> _allStudentsUnfiltered = [];

  // Standard specific filters
  String _selectedClassFilter = 'All Classes';
  String _selectedSort = 'First Name A-Z';
  List<String> _availableClasses = ['All Classes'];

  // Multi-select state
  bool _isSelecting = false;
  final Set<String> _selectedStudentIds = {};

  // Caching the current user's email for the header greeting
  String _userEmail = "Admin";

  @override
  void initState() {
    super.initState();
    _fetchSchoolId();
  }

  // ===========================================================================
  // 🚨 LOGIC ENGINE: STRICTLY UNTOUCHED
  // ===========================================================================
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
          .select('*')
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
          .select('class_level, profiles (first_name, last_name)')
          .eq('school_id', _schoolId!)
          .eq('role', 'Form Master');

      Map<String, String> masterMap = {};
      for (var assignment in assignments) {
        String classLevel = assignment['class_level']?.toString() ?? '';
        var profile = assignment['profiles'];
        if (classLevel.isNotEmpty && profile != null) {
          String masterName =
              "${profile['first_name']} ${profile['last_name']}";
          masterMap[classLevel] = masterName;
        }
      }

      if (mounted) {
        setState(() {
          _formMasters = masterMap;
        });
      }
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

      // Extract unique classes for the filter dropdown
      Set<String> classSet = {'All Classes'};
      for (var s in loadedStudents) {
        if (s['class_level'] != null &&
            s['class_level'].toString().isNotEmpty) {
          classSet.add(s['class_level'].toString());
        }
      }

      if (mounted) {
        setState(() {
          _allStudentsUnfiltered = loadedStudents;
          _availableClasses = classSet.toList();
          // Sort available classes using the official admin order
          _availableClasses.sort((a, b) {
            if (a == 'All Classes') return -1;
            if (b == 'All Classes') return 1;
            int indexA = _officialClassOrder.indexOf(a);
            int indexB = _officialClassOrder.indexOf(b);
            if (indexA == -1 && indexB == -1) return a.compareTo(b);
            if (indexA == -1) return 1;
            if (indexB == -1) return -1;
            return indexA.compareTo(indexB);
          });
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

    // Filter by Search Query
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((s) {
        final fName = s['first_name']?.toString().toLowerCase() ?? '';
        final lName = s['last_name']?.toString().toLowerCase() ?? '';
        final query = _searchQuery.toLowerCase();
        return fName.contains(query) || lName.contains(query);
      }).toList();
    }

    // Filter by Class
    if (_selectedClassFilter != 'All Classes') {
      filtered = filtered
          .where((s) => s['class_level'] == _selectedClassFilter)
          .toList();
    }

    // Sort the results
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
      // Cleanup any selected students that might have been filtered out
      _selectedStudentIds.removeWhere(
        (id) => !_students.any((student) => student['id'] == id),
      );
      if (_selectedStudentIds.isEmpty) {
        _isSelecting = false;
      }
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

  // --- Mass Promotion Engine ---
  void _showPromotionDialog(Color primaryColor) {
    String? selectedTargetClass;
    bool isProcessing = false;

    List<String> validTargetClasses = List.from(_officialClassOrder);
    validTargetClasses.add("Graduated");
    validTargetClasses.add("Withdrawn");
    validTargetClasses.add("Expelled");

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
                    value: selectedTargetClass,
                    items: validTargetClasses.map((String c) {
                      return DropdownMenuItem(value: c, child: Text(c));
                    }).toList(),
                    onChanged: (val) {
                      setDialogState(() => selectedTargetClass = val);
                    },
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
  // 🚨 UI COMPONENTS (AESTHETIC UPGRADES)
  // ===========================================================================

  Widget _buildDesktopStatPill(
    String label,
    String value,
    IconData icon,
    Color color,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 28, color: color),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.white70 : Colors.grey.shade600,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 18,
                  color: color,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopHeader(Color primaryColor, bool isDark, String email) {
    int totalStudents = _allStudentsUnfiltered.length;
    int maleCount = _allStudentsUnfiltered
        .where((s) => s['gender']?.toString().toLowerCase() == 'male')
        .length;
    int femaleCount = _allStudentsUnfiltered
        .where((s) => s['gender']?.toString().toLowerCase() == 'female')
        .length;

    return Container(
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Student Directory",
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "Manage enrollments, assign classes, and access full academic records across the institution.",
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.white70 : Colors.grey.shade600,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _buildDesktopStatPill(
                      "TOTAL",
                      totalStudents.toString(),
                      Icons.groups_rounded,
                      primaryColor,
                      isDark,
                    ),
                    _buildDesktopStatPill(
                      "MALES",
                      maleCount.toString(),
                      Icons.male_rounded,
                      Colors.blue,
                      isDark,
                    ),
                    _buildDesktopStatPill(
                      "FEMALES",
                      femaleCount.toString(),
                      Icons.female_rounded,
                      Colors.pink,
                      isDark,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 30),
          _buildQuickActionsBox(primaryColor, isDark),
        ],
      ),
    );
  }

  Widget _buildMobileMiniStat(IconData icon, String label, String value) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.2),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMobileHeader(Color primaryColor, bool isDark, String email) {
    int totalStudents = _allStudentsUnfiltered.length;
    int maleCount = _allStudentsUnfiltered
        .where((s) => s['gender']?.toString().toLowerCase() == 'male')
        .length;
    int femaleCount = _allStudentsUnfiltered
        .where((s) => s['gender']?.toString().toLowerCase() == 'female')
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [primaryColor, primaryColor.withValues(alpha: 0.8)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: primaryColor.withValues(alpha: 0.3),
                blurRadius: 15,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.admin_panel_settings_rounded,
                          color: Colors.white,
                          size: 14,
                        ),
                        SizedBox(width: 6),
                        Text(
                          "Active Session",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.school_rounded,
                    color: Colors.white70,
                    size: 30,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Text(
                "Total Enrolled",
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                "$totalStudents",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 42,
                  fontWeight: FontWeight.w900,
                  height: 1.0,
                ),
              ),
              const SizedBox(height: 24),

              // 🚨 NEW PREMIUM DEMOGRAPHICS ROW
              Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 16,
                  horizontal: 20,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildMobileMiniStat(
                      Icons.male_rounded,
                      "MALES",
                      maleCount.toString(),
                    ),
                    Container(
                      width: 1,
                      height: 35,
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                    _buildMobileMiniStat(
                      Icons.female_rounded,
                      "FEMALES",
                      femaleCount.toString(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildQuickActionsBox(primaryColor, isDark),
      ],
    );
  }

  Widget _buildQuickActionsBox(Color primaryColor, bool isDark) {
    return Container(
      width: double
          .infinity, // 🚨 FIX: Forces the card to stretch to full width on mobile
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Directory Tools",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: isDark ? Colors.white54 : Colors.grey.shade500,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    vertical: 16,
                    horizontal: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const StudentAdmissionScreen(),
                    ),
                  ).then((_) => _fetchStudents());
                },
                icon: const Icon(Icons.person_add_rounded, size: 18),
                label: const Text(
                  "ADMIT STUDENT",
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
                ),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: isDark
                      ? Colors.white.withValues(alpha: 0.1)
                      : primaryColor.withValues(alpha: 0.1),
                  foregroundColor: isDark ? Colors.white : primaryColor,
                  padding: const EdgeInsets.symmetric(
                    vertical: 16,
                    horizontal: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const IdCardGeneratorScreen(),
                    ),
                  );
                },
                icon: const Icon(Icons.badge_rounded, size: 18),
                label: const Text(
                  "GENERATE ID",
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildControlsRow(Color primaryColor, bool isDark, bool isDesktop) {
    final searchField = Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
        ),
      ),
      child: TextField(
        onChanged: (val) {
          setState(() => _searchQuery = val);
          _filterAndSortStudents();
        },
        style: TextStyle(
          fontSize: 14,
          color: isDark ? Colors.white : Colors.black87,
        ),
        decoration: InputDecoration(
          hintText: "Search by name...",
          hintStyle: TextStyle(
            color: isDark ? Colors.white30 : Colors.grey.shade400,
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            color: isDark ? Colors.white54 : Colors.grey.shade400,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
      ),
    );

    final filters = Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? Colors.white10 : Colors.grey.shade200,
              ),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: _selectedClassFilter,
                icon: Icon(
                  Icons.filter_list_rounded,
                  color: Colors.grey.shade400,
                  size: 18,
                ),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                items: _availableClasses.map((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: (newValue) {
                  if (newValue != null) {
                    setState(() => _selectedClassFilter = newValue);
                    _filterAndSortStudents();
                  }
                },
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? Colors.white10 : Colors.grey.shade200,
              ),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: _selectedSort,
                icon: Icon(
                  Icons.sort_rounded,
                  color: Colors.grey.shade400,
                  size: 18,
                ),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                items:
                    [
                      'First Name A-Z',
                      'First Name Z-A',
                      'Date Added (Newest)',
                      'Date Added (Oldest)',
                    ].map((String value) {
                      return DropdownMenuItem<String>(
                        value: value,
                        child: Text(
                          value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                onChanged: (newValue) {
                  if (newValue != null) {
                    setState(() => _selectedSort = newValue);
                    _filterAndSortStudents();
                  }
                },
              ),
            ),
          ),
        ),
      ],
    );

    return isDesktop
        ? Row(
            children: [
              Expanded(flex: 2, child: searchField),
              const SizedBox(width: 16),
              Expanded(flex: 3, child: filters),
            ],
          )
        : Column(children: [searchField, const SizedBox(height: 12), filters]);
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color primaryColor = Theme.of(context).primaryColor;
    Color bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC);

    bool isDesktop = MediaQuery.of(context).size.width > 800;
    double horizontalPadding = isDesktop ? 30.0 : 16.0;

    Widget rosterContent = CustomScrollView(
      slivers: [
        // ─── TOP HEADER (Scrolls out of view) ───
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            horizontalPadding,
            horizontalPadding,
            16.0,
          ),
          sliver: SliverToBoxAdapter(
            child: isDesktop
                ? _buildDesktopHeader(primaryColor, isDark, _userEmail)
                : _buildMobileHeader(primaryColor, isDark, _userEmail),
          ),
        ),

        // ─── STICKY CONTROLS (Pins to the top) ───
        SliverPersistentHeader(
          pinned: true,
          delegate: _StickyControlsDelegate(
            bgColor: bgColor,
            height: isDesktop ? 80.0 : 170.0,
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
            child: _buildControlsRow(primaryColor, isDark, isDesktop),
          ),
        ),

        // ─── STUDENT LIST (Scrolls continuously) ───
        SliverPadding(
          padding: EdgeInsets.only(
            left: horizontalPadding,
            right: horizontalPadding,
            bottom: horizontalPadding,
          ),
          sliver: _isLoading
              ? SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 50.0),
                    child: Center(child: TridetaLoader(color: primaryColor)),
                  ),
                )
              : _students.isEmpty
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
                            "No Students Found",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "Try adjusting your search or filters.",
                            style: TextStyle(color: Colors.grey.shade500),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              : SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final student = _students[index];
                    final isSelected = _selectedStudentIds.contains(
                      student['id'],
                    );
                    final String fullName =
                        "${student['first_name']} ${student['last_name']}";
                    final String classLevel =
                        student['class_level'] ?? 'Unassigned';
                    final String? photoUrl = student['passport_url'];

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected
                              ? primaryColor
                              : (isDark
                                    ? Colors.white10
                                    : Colors.grey.shade200),
                          width: isSelected ? 2 : 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.02),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        onTap: () {
                          if (_isSelecting) {
                            _toggleSelection(student['id']);
                          } else {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => StudentProfileScreen(
                                  name: student['first_name'] ?? '',
                                  id: student['id'] ?? '',
                                  studentClass: student['class'] ?? '',
                                  imagePath: student['photo_url'],
                                  parentPhone: student['parent_phone'],
                                  parentEmail: student['parent_email'],
                                ),
                              ),
                            ).then((_) => _fetchStudents());
                          }
                        },
                        onLongPress: () => _toggleSelection(student['id']),
                        leading: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_isSelecting)
                              Checkbox(
                                value: isSelected,
                                onChanged: (_) =>
                                    _toggleSelection(student['id']),
                                activeColor: primaryColor,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            CircleAvatar(
                              radius: 24,
                              backgroundColor: primaryColor.withValues(
                                alpha: 0.1,
                              ),
                              backgroundImage:
                                  photoUrl != null && photoUrl.isNotEmpty
                                  ? NetworkImage(photoUrl)
                                  : null,
                              child: photoUrl == null || photoUrl.isEmpty
                                  ? Icon(
                                      Icons.person_rounded,
                                      color: primaryColor,
                                    )
                                  : null,
                            ),
                          ],
                        ),
                        title: Text(
                          fullName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            "ID: ${student['admission_no'] ?? 'N/A'} • $classLevel",
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade500,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        trailing: Icon(
                          Icons.chevron_right_rounded,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    );
                  }, childCount: _students.length),
                ),
        ),
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
              onPressed: () {
                setState(() {
                  _selectedStudentIds.clear();
                  _isSelecting = false;
                });
              },
            ),
          if (!_isSelecting && !isDesktop)
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

// ===========================================================================
// 🚨 CUSTOM DELEGATE FOR STICKY SEARCH/FILTER ROW
// ===========================================================================
class _StickyControlsDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  final double height;
  final Color bgColor;
  final EdgeInsets padding;

  _StickyControlsDelegate({
    required this.child,
    required this.height,
    required this.bgColor,
    required this.padding,
  });

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      color: bgColor,
      padding: padding.copyWith(top: 10.0, bottom: 16.0),
      alignment: Alignment.center,
      child: child,
    );
  }

  @override
  bool shouldRebuild(covariant _StickyControlsDelegate oldDelegate) {
    return true;
  }
}
