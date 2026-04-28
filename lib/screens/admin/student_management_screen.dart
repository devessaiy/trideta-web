import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb; // 🚨 Added for Web Checks
import 'package:supabase_flutter/supabase_flutter.dart';

// 🚨 UPDATED ABSOLUTE IMPORTS
import 'package:trideta_v2/screens/admin/student_admission_screen.dart';
import 'package:trideta_v2/screens/admin/student_profile_screen.dart';

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

  // 🚨 ADDED: Full class data with UUIDs for the promotion engine
  List<Map<String, dynamic>> _allClassesData = [];

  @override
  void initState() {
    super.initState();
    _fetchSchoolId();
  }

  Future<void> _fetchSchoolId() async {
    final user = _supabase.auth.currentUser;
    if (user != null) {
      final profile = await _supabase
          .from('profiles')
          .select('school_id')
          .eq('id', user.id)
          .single();

      final sId = profile['school_id'];
      if (mounted) setState(() => _schoolId = sId);

      if (sId != null) {
        _fetchSchoolConfig(sId);
        _fetchFormMasters(sId);
      }
    }
  }

  // 🚨 STRICTLY FETCHING FROM RELATIONAL 'classes' TABLE (Added UUIDs)
  Future<void> _fetchSchoolConfig(String sId) async {
    try {
      final classesData = await _supabase
          .from('classes')
          .select('id, name')
          .eq('school_id', sId)
          .order('list_order', ascending: true);

      if (mounted) {
        setState(() {
          _allClassesData = List<Map<String, dynamic>>.from(classesData);
          _officialClassOrder = classesData
              .map((c) => c['name'].toString())
              .toList();
        });
      }
    } catch (e) {
      debugPrint("School config fetch error: $e");
    }
  }

  Future<void> _fetchFormMasters(String sId) async {
    try {
      final response = await _supabase
          .from('staff_assignments')
          .select('class_assigned, profiles!inner(full_name)')
          .eq('school_id', sId)
          .filter('subject_assigned', 'is', null);

      Map<String, String> masters = {};

      for (var row in response) {
        String rawClass = (row['class_assigned'] ?? '').toString();
        String normalizedClass = rawClass.toLowerCase().replaceAll(' ', '');

        if (row['profiles'] != null && row['profiles']['full_name'] != null) {
          masters[normalizedClass] = row['profiles']['full_name'];
        }
      }

      if (mounted) {
        setState(() => _formMasters = masters);
      }
    } catch (e) {
      debugPrint("Form Master fetch error: $e");
    }
  }

  Future<void> _handleRefresh() async {
    await _fetchSchoolId();
    setState(() {}); // This forces the StreamBuilder to restart the connection
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC);
    Color cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    Color textColor = isDark ? Colors.white : Colors.black87;

    Color primaryColor = Theme.of(context).primaryColor;

    final Stream<List<Map<String, dynamic>>>? studentStream = _schoolId == null
        ? null
        : _supabase
              .from('students')
              .stream(primaryKey: ['id'])
              .eq('school_id', _schoolId!)
              .order('first_name', ascending: true);

    // 🚨 MAIN CONTENT EXTRACTED FOR LAYOUT BUILDER
    Widget mainContent = Column(
      children: [
        // --- HEADER STATS ---
        _buildTopHeader(isDark, primaryColor),

        // --- SEARCH BAR ---
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
          child: TextField(
            onChanged: (val) => setState(() => _searchQuery = val),
            style: TextStyle(color: textColor),
            decoration: InputDecoration(
              hintText: "Search Classes or Students...",
              hintStyle: TextStyle(
                color: isDark ? Colors.white54 : Colors.grey,
              ),
              prefixIcon: Icon(Icons.search_rounded, color: primaryColor),
              filled: true,
              fillColor: cardColor,
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
              contentPadding: const EdgeInsets.symmetric(vertical: 15),
            ),
          ),
        ),

        // --- LIST AREA ---
        Expanded(
          child: studentStream == null
              ? const Center(child: CircularProgressIndicator())
              : StreamBuilder<List<Map<String, dynamic>>>(
                  stream: studentStream,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return _buildErrorState(isDark, primaryColor);
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final allStudents = snapshot.data!;

                    // If searching, bypass classes and show raw students
                    if (_searchQuery.isNotEmpty) {
                      final filteredStudents = allStudents.where((s) {
                        final name = "${s['first_name']} ${s['last_name']}"
                            .toLowerCase();
                        final id = (s['admission_no'] ?? "").toLowerCase();
                        final cls = (s['class_level'] ?? "").toLowerCase();
                        return name.contains(_searchQuery.toLowerCase()) ||
                            id.contains(_searchQuery.toLowerCase()) ||
                            cls.contains(_searchQuery.toLowerCase());
                      }).toList();

                      if (filteredStudents.isEmpty) {
                        return _buildEmptyState(isDark);
                      }

                      Widget searchList = ListView.builder(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        itemCount: filteredStudents.length,
                        itemBuilder: (context, index) {
                          return _buildStudentCard(
                            filteredStudents[index],
                            cardColor,
                            textColor,
                            isDark,
                            primaryColor,
                          );
                        },
                      );

                      // 🚨 CONDITIONAL REFRESH INDICATOR
                      return kIsWeb
                          ? searchList
                          : RefreshIndicator(
                              onRefresh: _handleRefresh,
                              color: primaryColor,
                              child: searchList,
                            );
                    }

                    // 🚨 THE NEW BUCKET LOGIC 🚨

                    // 1. Create empty buckets for ALL official classes
                    Map<String, List<Map<String, dynamic>>> grouped = {};
                    for (String cls in _officialClassOrder) {
                      grouped[cls] = [];
                    }

                    List<Map<String, dynamic>> unassignedOrLegacy = [];

                    // 2. Drop students into their matching buckets
                    for (var s in allStudents) {
                      String studentClass = (s['class_level'] ?? "")
                          .toString()
                          .trim();

                      String? matchedOfficialClass;
                      for (String officialClass in _officialClassOrder) {
                        if (officialClass.toUpperCase() ==
                            studentClass.toUpperCase()) {
                          matchedOfficialClass = officialClass;
                          break;
                        }
                      }

                      if (matchedOfficialClass != null) {
                        grouped[matchedOfficialClass]!.add(s);
                      } else {
                        unassignedOrLegacy.add(s);
                      }
                    }

                    // 3. Build the display list
                    List<String> displayClasses = List.from(
                      _officialClassOrder,
                    );
                    if (unassignedOrLegacy.isNotEmpty) {
                      displayClasses.add("Unassigned / Legacy Data");
                      grouped["Unassigned / Legacy Data"] = unassignedOrLegacy;
                    }

                    if (displayClasses.isEmpty) {
                      return _buildEmptyState(isDark);
                    }

                    Widget classList = ListView.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      itemCount: displayClasses.length,
                      itemBuilder: (context, index) {
                        String cls = displayClasses[index];
                        List<Map<String, dynamic>> classRoster = grouped[cls]!;
                        return _buildClassOverviewCard(
                          cls,
                          classRoster,
                          cardColor,
                          textColor,
                          isDark,
                          primaryColor,
                        );
                      },
                    );

                    // 🚨 CONDITIONAL REFRESH INDICATOR
                    return kIsWeb
                        ? classList
                        : RefreshIndicator(
                            onRefresh: _handleRefresh,
                            color: primaryColor,
                            child: classList,
                          );
                  },
                ),
        ),
      ],
    );

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text(
          "Student Management",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false,
        // 🚨 ADDED REFRESH BUTTON FOR WEB USERS
        actions: kIsWeb
            ? [
                IconButton(
                  icon: const Icon(Icons.refresh_rounded),
                  tooltip: "Refresh Data",
                  onPressed: _handleRefresh,
                ),
                const SizedBox(width: 10),
              ]
            : null,
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
            // 📱 MOBILE LAYOUT
            return mainContent;
          }
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: primaryColor,
        elevation: 4,
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const StudentAdmissionScreen()),
        ),
        icon: const Icon(Icons.person_add_rounded, color: Colors.white),
        label: const Text(
          "ADMIT STUDENT",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  // --- UI PILLARS ---

  Widget _buildTopHeader(bool isDark, Color primaryColor) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
      decoration: BoxDecoration(
        color: primaryColor,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30)),
      ),
      child: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _schoolId == null
            ? null
            : _supabase
                  .from('students')
                  .stream(primaryKey: ['id'])
                  .eq('school_id', _schoolId!),
        builder: (context, snapshot) {
          int total = snapshot.data?.length ?? 0;
          int boys =
              snapshot.data?.where((s) => s['gender'] == 'Male').length ?? 0;
          int girls =
              snapshot.data?.where((s) => s['gender'] == 'Female').length ?? 0;

          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem("Total", total.toString()),
              _buildDivider(),
              _buildStatItem("Boys", boys.toString()),
              _buildDivider(),
              _buildStatItem("Girls", girls.toString()),
            ],
          );
        },
      ),
    );
  }

  Widget _buildClassOverviewCard(
    String className,
    List<Map<String, dynamic>> students,
    Color cardColor,
    Color textColor,
    bool isDark,
    Color primaryColor,
  ) {
    bool isLegacy = className == "Unassigned / Legacy Data";
    Color iconColor = isLegacy ? Colors.red : primaryColor;

    String searchClassKey = className.toLowerCase().replaceAll(' ', '');
    String formMasterName = isLegacy
        ? "Action Required (Update Profiles)"
        : (_formMasters[searchClassKey] ?? "Not Assigned");

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: isLegacy
              ? Colors.red.withOpacity(0.3)
              : (isDark
                    ? Colors.white.withOpacity(0.05)
                    : Colors.grey.shade200),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 12,
        ),
        leading: CircleAvatar(
          radius: 25,
          backgroundColor: iconColor.withOpacity(0.1),
          child: Icon(
            isLegacy ? Icons.warning_rounded : Icons.class_rounded,
            color: iconColor,
          ),
        ),
        title: Text(
          className.toUpperCase(),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: isLegacy ? Colors.red : textColor,
            letterSpacing: 1.0,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isLegacy ? formMasterName : "Form Master: $formMasterName",
                style: TextStyle(
                  fontSize: 12,
                  color: isLegacy
                      ? Colors.red[300]
                      : (isDark ? Colors.white54 : Colors.grey[600]),
                  fontWeight: isLegacy ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.people_alt_rounded, size: 14, color: iconColor),
                  const SizedBox(width: 4),
                  Text(
                    "${students.length} Students",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: iconColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        trailing: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.grey.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.arrow_forward_ios_rounded,
            color: isDark ? Colors.white54 : Colors.black54,
            size: 16,
          ),
        ),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => _ClassListScreen(
                className: className,
                students: students,
                allClasses:
                    _allClassesData, // 🚨 Pushing down the full class data
                cardColor: cardColor,
                textColor: textColor,
                isDark: isDark,
              ),
            ),
          ).then((_) {
            // 🚨 Refresh to update buckets accurately if students were promoted
            if (mounted) _handleRefresh();
          });
        },
      ),
    );
  }

  Widget _buildStudentCard(
    Map<String, dynamic> student,
    Color cardColor,
    Color textColor,
    bool isDark,
    Color primaryColor,
  ) {
    final String fullName = "${student['first_name']} ${student['last_name']}";
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade100,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Hero(
          tag: student['id'],
          child: CircleAvatar(
            radius: 25,
            backgroundColor: primaryColor.withOpacity(0.1),
            backgroundImage: student['passport_url'] != null
                ? NetworkImage(student['passport_url'])
                : null,
            child: student['passport_url'] == null
                ? Icon(Icons.person_rounded, color: primaryColor)
                : null,
          ),
        ),
        title: Text(
          fullName,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: textColor,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            "${student['admission_no'] ?? 'NO ID'} • ${student['gender']} • ${student['class_level']}",
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white54 : Colors.grey[600],
            ),
          ),
        ),
        trailing: Icon(
          Icons.chevron_right_rounded,
          color: isDark ? Colors.white24 : Colors.grey[300],
        ),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => StudentProfileScreen(
                name: fullName,
                id: student['id'],
                studentClass: student['class_level'] ?? "Unassigned",
                imagePath: student['passport_url'],
                parentPhone: student['parent_phone'],
                parentEmail: student['parent_email'],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w900,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildDivider() =>
      Container(height: 30, width: 1, color: Colors.white24);

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.person_search_rounded,
            size: 80,
            color: isDark ? Colors.white10 : Colors.grey[200],
          ),
          const SizedBox(height: 15),
          Text(
            "No students match your search",
            style: TextStyle(
              color: isDark ? Colors.white38 : Colors.grey[400],
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(bool isDark, Color primaryColor) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.wifi_off_rounded,
              size: 80,
              color: isDark ? Colors.white24 : Colors.grey[300],
            ),
            const SizedBox(height: 20),
            Text(
              "Connection Lost",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              "We couldn't connect to the server. Please check your internet connection and try again.",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark ? Colors.white54 : Colors.grey[600],
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                elevation: 0,
              ),
              onPressed: _handleRefresh,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text(
                "Refresh",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// DEDICATED CLASS ROSTER SCREEN (UPGRADED TO STATEFUL FOR MULTI-SELECT)
// ============================================================================
class _ClassListScreen extends StatefulWidget {
  final String className;
  final List<Map<String, dynamic>> students;
  final List<Map<String, dynamic>> allClasses;
  final Color cardColor;
  final Color textColor;
  final bool isDark;

  const _ClassListScreen({
    required this.className,
    required this.students,
    required this.allClasses,
    required this.cardColor,
    required this.textColor,
    required this.isDark,
  });

  @override
  State<_ClassListScreen> createState() => _ClassListScreenState();
}

class _ClassListScreenState extends State<_ClassListScreen> {
  final Set<String> _selectedStudentIds = {};
  bool _isSelecting = false;

  late List<Map<String, dynamic>> _localStudents;

  @override
  void initState() {
    super.initState();
    _localStudents = List<Map<String, dynamic>>.from(widget.students);
    _localStudents.sort(
      (a, b) => (a['first_name'] ?? '').toString().compareTo(
        (b['first_name'] ?? '').toString(),
      ),
    );
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selectedStudentIds.length == _localStudents.length) {
        _selectedStudentIds
            .clear(); // Unselect all if all are currently selected
      } else {
        _selectedStudentIds.addAll(
          _localStudents.map((s) => s['id'].toString()),
        );
      }
    });
  }

  void _toggleStudent(String id) {
    setState(() {
      if (_selectedStudentIds.contains(id)) {
        _selectedStudentIds.remove(id);
      } else {
        _selectedStudentIds.add(id);
      }
    });
  }

  void _showPromotionDialog(Color primaryColor) {
    String? selectedClassId;
    String? selectedClassName;
    bool isSaving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: widget.isDark
                  ? const Color(0xFF1E1E1E)
                  : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              title: const Text("Promote / Reassign"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Moving ${_selectedStudentIds.length} students to:"),
                  const SizedBox(height: 15),
                  Container(
                    decoration: BoxDecoration(
                      color: widget.isDark
                          ? Colors.white.withOpacity(0.05)
                          : Colors.grey[50],
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: widget.isDark
                            ? Colors.white10
                            : Colors.grey.shade300,
                      ),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: selectedClassId,
                        hint: const Padding(
                          padding: EdgeInsets.only(left: 10),
                          child: Text(
                            "Select Destination Class",
                            style: TextStyle(fontSize: 14),
                          ),
                        ),
                        items: widget.allClasses.map((c) {
                          return DropdownMenuItem<String>(
                            value: c['id'].toString(),
                            child: Padding(
                              padding: const EdgeInsets.only(left: 10),
                              child: Text(c['name'].toString()),
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          setDialogState(() {
                            selectedClassId = val;
                            selectedClassName = widget.allClasses
                                .firstWhere(
                                  (c) => c['id'].toString() == val,
                                )['name']
                                .toString();
                          });
                        },
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.pop(ctx),
                  child: const Text(
                    "Cancel",
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                  ),
                  onPressed: (isSaving || selectedClassId == null)
                      ? null
                      : () async {
                          setDialogState(() => isSaving = true);
                          try {
                            // 🚨 THE BATCH UPDATE ENGINE 🚨
                            await Supabase.instance.client
                                .from('students')
                                .update({
                                  'class_id': selectedClassId,
                                  'class_level': selectedClassName,
                                })
                                .inFilter('id', _selectedStudentIds.toList());

                            if (mounted) {
                              setState(() {
                                // Remove them from local view and reset selection
                                _localStudents.removeWhere(
                                  (s) => _selectedStudentIds.contains(
                                    s['id'].toString(),
                                  ),
                                );
                                _selectedStudentIds.clear();
                                _isSelecting = false;
                              });
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    "Successfully moved students to $selectedClassName",
                                  ),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          } catch (e) {
                            setDialogState(() => isSaving = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text("Failed to move students: $e"),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        },
                  child: isSaving
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          "Confirm",
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

  @override
  Widget build(BuildContext context) {
    Color primaryColor = Theme.of(context).primaryColor;
    Color bgColor = widget.isDark
        ? const Color(0xFF121212)
        : const Color(0xFFF8FAFC);

    Widget rosterContent = _localStudents.isEmpty
        ? Center(
            child: Text(
              "No students left in this class.",
              style: TextStyle(color: Colors.grey[500], fontSize: 16),
            ),
          )
        : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _localStudents.length,
            itemBuilder: (context, index) {
              final student = _localStudents[index];
              final String fullName =
                  "${student['first_name']} ${student['last_name']}";
              final String sId = student['id'].toString();
              final bool isSelected = _selectedStudentIds.contains(sId);

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: isSelected
                      ? primaryColor.withOpacity(0.1)
                      : widget.cardColor,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(
                    color: isSelected
                        ? primaryColor.withOpacity(0.5)
                        : (widget.isDark
                              ? Colors.white.withOpacity(0.05)
                              : Colors.grey.shade100),
                  ),
                ),
                child: ListTile(
                  leading: _isSelecting
                      ? Checkbox(
                          value: isSelected,
                          onChanged: (val) => _toggleStudent(sId),
                          activeColor: primaryColor,
                        )
                      : Hero(
                          tag: student['id'],
                          child: CircleAvatar(
                            backgroundColor: primaryColor.withOpacity(0.1),
                            backgroundImage: student['passport_url'] != null
                                ? NetworkImage(student['passport_url'])
                                : null,
                            child: student['passport_url'] == null
                                ? Icon(
                                    Icons.person_rounded,
                                    color: primaryColor,
                                  )
                                : null,
                          ),
                        ),
                  title: Text(
                    fullName,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: widget.textColor,
                    ),
                  ),
                  subtitle: Text(
                    "${student['admission_no'] ?? 'NO ID'} • ${student['gender']}",
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                  trailing: _isSelecting
                      ? null
                      : const Icon(
                          Icons.chevron_right_rounded,
                          color: Colors.grey,
                        ),
                  onTap: () {
                    if (_isSelecting) {
                      _toggleStudent(sId);
                    } else {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => StudentProfileScreen(
                            name: fullName,
                            id: student['id'],
                            studentClass:
                                student['class_level'] ?? "Unassigned",
                            imagePath: student['passport_url'],
                            parentPhone: student['parent_phone'],
                            parentEmail: student['parent_email'],
                          ),
                        ),
                      );
                    }
                  },
                  onLongPress: () {
                    if (!_isSelecting) {
                      setState(() {
                        _isSelecting = true;
                        _selectedStudentIds.add(sId);
                      });
                    }
                  },
                ),
              );
            },
          );

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(
          _isSelecting
              ? "${_selectedStudentIds.length} Selected"
              : "${widget.className.toUpperCase()} Roster",
        ),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        centerTitle: true,
        leading: _isSelecting
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() {
                  _isSelecting = false;
                  _selectedStudentIds.clear();
                }),
              )
            : null,
        actions: [
          if (_isSelecting)
            IconButton(
              icon: const Icon(Icons.select_all),
              tooltip: "Select All",
              onPressed: _toggleSelectAll,
            ),
          if (!_isSelecting && _localStudents.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.checklist_rtl_rounded),
              tooltip: "Multi-Select",
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
                    border: Border(
                      left: BorderSide(
                        color: widget.isDark
                            ? Colors.white10
                            : Colors.grey.shade200,
                        width: 1,
                      ),
                      right: BorderSide(
                        color: widget.isDark
                            ? Colors.white10
                            : Colors.grey.shade200,
                        width: 1,
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
