import 'package:trideta_v2/utils/auth_error_handler.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trideta_v2/widgets/trideta_loader.dart';

// 🚨 IMPORT: Properly pulling in the unified Roster/Search components!
import 'components/student_controls_bar.dart';
import 'components/sticky_controls_delegate.dart';

import 'id_card_preview_screen.dart'; // 🚨 Ensure this points to your preview screen

class IdCardGeneratorScreen extends StatefulWidget {
  const IdCardGeneratorScreen({super.key});

  @override
  State<IdCardGeneratorScreen> createState() => _IdCardGeneratorScreenState();
}

class _IdCardGeneratorScreenState extends State<IdCardGeneratorScreen>
    with AuthErrorHandler {
  final _supabase = Supabase.instance.client;

  bool _isLoading = true;
  final bool _isGenerating = false;

  // 🚨 ID CARD SPECIFIC CONFIG
  String? _schoolId;
  String _schoolName = "Trideta School";
  String _schoolAddress = "Return to School Administration";
  String _schoolPhone = "";
  String _schoolEmail = "";
  String _brandColorHex = "#007ACC";

  // 🚨 UNIFIED SEARCH & ROSTER STATE (Ported directly from Student Management)
  String _searchQuery = "";
  Map<String, String> _formMasters = {};
  List<String> _officialClassOrder = [];
  List<Map<String, dynamic>> _allClassesData = [];
  List<dynamic> _students = [];
  List<dynamic> _allStudentsUnfiltered = [];

  String _selectedClassFilter = 'All Classes';
  String _selectedSort = 'First Name A-Z';
  List<String> _availableClasses = ['All Classes'];

  @override
  void initState() {
    super.initState();
    _initData();
  }

  // ============================================================================
  // 🚨 HYBRID LOGIC ENGINE: ID CONFIG + GLOBAL SEARCH (UNTOUCHED CORE)
  // ============================================================================
  Future<void> _initData() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final profile = await _supabase
          .from('profiles')
          .select('school_id')
          .eq('id', user.id)
          .single();
      _schoolId = profile['school_id'];

      if (_schoolId != null) {
        // 1. Fetch ID Card Configuration
        final schoolData = await _supabase
            .from('schools')
            .select('name, address, contact_phone, contact_email, brand_color')
            .eq('id', _schoolId!)
            .single();

        _schoolName = schoolData['name'] ?? "Trideta School";
        _schoolAddress =
            schoolData['address'] ?? "Return to School Administration";
        _schoolPhone = schoolData['contact_phone'] ?? "";
        _schoolEmail = schoolData['contact_email'] ?? "";
        _brandColorHex = schoolData['brand_color'] ?? "#007ACC";

        // 2. Fetch Classes & Order
        await _fetchClassesAndOrder();

        // 3. Fetch Form Masters (For the Roster UI)
        await _fetchFormMasters();

        // 4. Fetch All Students (For Global Search)
        await _fetchStudents();
      }
    } catch (e) {
      debugPrint("Failed to load init data: $e");
      if (mounted) setState(() => _isLoading = false);
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
      debugPrint("Failed to fetch classes: $e");
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
    try {
      final response = await _supabase
          .from('students')
          .select(
            'id, first_name, last_name, admission_no, passport_url, class_level, created_at, gender',
          )
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
      debugPrint("Failed to fetch students: $e");
      if (mounted) setState(() => _isLoading = false);
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
    });
  }

  // ============================================================================
  // 🚨 ID CARD GENERATION ROUTING (STRICTLY UNTOUCHED)
  // ============================================================================
  void _generateIndividualId(Map<String, dynamic> student) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => IdCardPreviewScreen(
          student: student,
          schoolName: _schoolName,
          schoolAddress: _schoolAddress,
          schoolPhone: _schoolPhone,
          schoolEmail: _schoolEmail,
          brandColorHex: _brandColorHex,
        ),
      ),
    );
  }

  void _generateBulkIdCards() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          "Bulk A4 generation is currently being updated to the new design system. Please download cards individually for now.",
        ),
        backgroundColor: Colors.orange,
      ),
    );
  }

  // ============================================================================
  // 🚨 UNIFIED UI BUILDERS (WhatsApp Style)
  // ============================================================================
  Widget _buildClassListItem(
    String className,
    int count,
    String formMaster,
    Color primaryColor,
    bool isDark,
  ) {
    return InkWell(
      onTap: () {
        setState(() {
          _selectedClassFilter = className;
          _searchQuery = "";
        });
        _filterAndSortStudents();
      },
      child: Column(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 8,
            ),
            leading: CircleAvatar(
              radius: 26,
              backgroundColor: primaryColor.withValues(alpha: 0.1),
              child: Icon(Icons.groups_rounded, color: primaryColor, size: 28),
            ),
            title: Text(
              className,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            subtitle: Row(
              children: [
                Icon(
                  Icons.person_outline_rounded,
                  size: 14,
                  color: Colors.grey.shade500,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    formMaster,
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  "$count",
                  style: TextStyle(
                    color: primaryColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "Students",
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 10),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 76, right: 20),
            child: Divider(
              height: 1,
              color: isDark ? Colors.white10 : Colors.grey.shade200,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color primaryColor = Theme.of(context).primaryColor;

    // 🚨 Premium Material Matte Background
    Color bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC);
    Color textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);

    bool isDesktop = MediaQuery.of(context).size.width > 800;
    double horizontalPadding = isDesktop ? 30.0 : 16.0;

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
        if (_isLoading)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 50.0),
              child: Center(child: TridetaLoader(color: primaryColor)),
            ),
          )
        else ...[
          // ─── GLOBAL STICKY CONTROLS (ALWAYS VISIBLE FOR GLOBAL SEARCH) ───
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

          // ─── CLASS NAVIGATION HEADER (Only when drilled into a specific class) ───
          if (_selectedClassFilter != 'All Classes')
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
                              "Classes",
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
                          color: textColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ─── STATE 1: CLASS ROSTER LIST (No Global Search & No Class Selected) ───
          if (_selectedClassFilter == 'All Classes' &&
              _searchQuery.isEmpty) ...[
            SliverPadding(
              padding: EdgeInsets.symmetric(
                horizontal: horizontalPadding,
                vertical: 10,
              ),
              sliver: SliverToBoxAdapter(
                child: Text(
                  "Select a Class to Generate ID Cards",
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
              padding: EdgeInsets.zero,
              sliver: SliverList(
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
                  String formMaster =
                      _formMasters[className] ?? 'No Form Master';

                  return _buildClassListItem(
                    className,
                    count,
                    formMaster,
                    primaryColor,
                    isDark,
                  );
                }, childCount: classesToShow.length),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 50)),
          ]
          // ─── STATE 2: STUDENT LIST (Global Search Results OR Class Drill-Down) ───
          else ...[
            SliverPadding(
              padding: const EdgeInsets.only(bottom: 50.0),
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
                                  color: textColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  : SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final student = _students[index];
                        final String fullName =
                            "${student['first_name']} ${student['last_name']}";
                        final String? photoUrl = student['passport_url'];

                        return Column(
                          children: [
                            ListTile(
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: horizontalPadding,
                                vertical: 8,
                              ),
                              leading: CircleAvatar(
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
                              title: Text(
                                fullName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  // 🚨 Dynamically show the class level if searching globally
                                  _searchQuery.isNotEmpty
                                      ? "${student['class_level']} • ID: ${student['admission_no'] ?? 'N/A'}"
                                      : "ID: ${student['admission_no'] ?? 'N/A'}",
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: isDark
                                        ? Colors.white70
                                        : Colors.grey.shade600,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              trailing: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: primaryColor,
                                  side: BorderSide(
                                    color: primaryColor.withValues(alpha: 0.5),
                                    width: 1.5,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                onPressed: _isGenerating
                                    ? null
                                    : () => _generateIndividualId(student),
                                icon: const Icon(Icons.badge_rounded, size: 16),
                                label: const Text(
                                  "CARD",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.only(
                                left: horizontalPadding + 64,
                                right: horizontalPadding,
                              ),
                              child: Divider(
                                height: 1,
                                color: isDark
                                    ? Colors.white10
                                    : Colors.grey.shade200,
                              ),
                            ),
                          ],
                        );
                      }, childCount: _students.length),
                    ),
            ),
          ],
        ],
      ],
    );

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text(
          "ID Card Generator",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: bgColor,
        foregroundColor: textColor,
        elevation: 0,
        centerTitle: true,
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
    );
  }
}
