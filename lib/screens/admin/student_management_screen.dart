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

  @override
  void initState() {
    super.initState();
    _fetchSchoolId();
  }

  // ===========================================================================
  // 🚨 LOGIC ENGINE: STRICTLY UNTOUCHED
  // ===========================================================================
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
    setState(() {});
  }

  // ===========================================================================
  // 🚨 PREMIUM RESPONSIVE UI
  // ===========================================================================
  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC);
    Color cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    Color textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    Color primaryColor = Theme.of(context).primaryColor;

    final Stream<List<Map<String, dynamic>>>? studentStream = _schoolId == null
        ? null
        : _supabase
              .from('students')
              .stream(primaryKey: ['id'])
              .eq('school_id', _schoolId!)
              .order('first_name', ascending: true);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text(
          "Student Management",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: bgColor,
        foregroundColor: textColor,
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false,
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
      body: LayoutBuilder(
        builder: (context, constraints) {
          bool isDesktop = constraints.maxWidth > 800;

          Widget mainContent = Column(
            children: [
              // ─── RESPONSIVE HEADERS ───
              if (isDesktop)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 25, 24, 0),
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: 5,
                          child: _buildTopHeader(isDark, primaryColor),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 4,
                          child: _buildSmartIdCard(
                            cardColor,
                            textColor,
                            isDark,
                            primaryColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                      child: _buildTopHeader(isDark, primaryColor),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                      child: _buildSmartIdCard(
                        cardColor,
                        textColor,
                        isDark,
                        primaryColor,
                      ),
                    ),
                  ],
                ),

              // ─── SEARCH FIELD ───
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 10),
                child: TextField(
                  onChanged: (val) => setState(() => _searchQuery = val),
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: InputDecoration(
                    hintText: "Search Classes or Students...",
                    hintStyle: TextStyle(
                      color: Colors.grey.shade500,
                      fontWeight: FontWeight.normal,
                    ),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      color: primaryColor,
                      size: 20,
                    ),
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
                    contentPadding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),

              // ─── DATA ENGINE ───
              Expanded(
                child: studentStream == null
                    ? Center(child: TridetaLoader(color: primaryColor))
                    : StreamBuilder<List<Map<String, dynamic>>>(
                        stream: studentStream,
                        builder: (context, snapshot) {
                          if (snapshot.hasError)
                            return _buildErrorState(isDark, primaryColor);
                          if (!snapshot.hasData)
                            return Center(
                              child: TridetaLoader(color: primaryColor),
                            );

                          final allStudents = snapshot.data!;

                          if (_searchQuery.isNotEmpty) {
                            final filteredStudents = allStudents.where((s) {
                              final name =
                                  "${s['first_name']} ${s['last_name']}"
                                      .toLowerCase();
                              final id = (s['admission_no'] ?? "")
                                  .toLowerCase();
                              final cls = (s['class_level'] ?? "")
                                  .toLowerCase();
                              return name.contains(
                                    _searchQuery.toLowerCase(),
                                  ) ||
                                  id.contains(_searchQuery.toLowerCase()) ||
                                  cls.contains(_searchQuery.toLowerCase());
                            }).toList();

                            if (filteredStudents.isEmpty)
                              return _buildEmptyState(isDark);

                            Widget searchList = ListView.builder(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 10,
                              ),
                              itemCount: filteredStudents.length,
                              itemBuilder: (context, index) =>
                                  _buildStudentCard(
                                    filteredStudents[index],
                                    cardColor,
                                    textColor,
                                    isDark,
                                    primaryColor,
                                  ),
                            );

                            return kIsWeb
                                ? searchList
                                : RefreshIndicator(
                                    onRefresh: _handleRefresh,
                                    color: primaryColor,
                                    child: searchList,
                                  );
                          }

                          Map<String, List<Map<String, dynamic>>> grouped = {};
                          for (String cls in _officialClassOrder) {
                            grouped[cls] = [];
                          }

                          List<Map<String, dynamic>> unassignedOrLegacy = [];

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

                          List<String> displayClasses = List.from(
                            _officialClassOrder,
                          );
                          if (unassignedOrLegacy.isNotEmpty) {
                            displayClasses.add("Unassigned / Legacy Data");
                            grouped["Unassigned / Legacy Data"] =
                                unassignedOrLegacy;
                          }

                          if (displayClasses.isEmpty)
                            return _buildEmptyState(isDark);

                          Widget classList = GridView.builder(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 10,
                            ),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: isDesktop ? 2 : 1,
                                  crossAxisSpacing: 16,
                                  mainAxisSpacing: 16,
                                  mainAxisExtent: 130,
                                ),
                            itemCount: displayClasses.length,
                            itemBuilder: (context, index) {
                              String cls = displayClasses[index];
                              List<Map<String, dynamic>> classRoster =
                                  grouped[cls]!;
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

          if (isDesktop) {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
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

  // --- COMPACT OVERFLOW-FREE WIDGETS ---

  Widget _buildTopHeader(bool isDark, Color primaryColor) {
    return Container(
      width: double
          .infinity, // 🚨 FIXED: Now stretches fully inside the Expanded/Padding
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [primaryColor.withValues(alpha: 0.85), primaryColor],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withValues(alpha: 0.25),
            blurRadius: 15,
            offset: const Offset(0, 6),
          ),
        ],
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.15),
          width: 1.5,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -25,
            top: -25,
            child: CircleAvatar(
              radius: 45,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
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
                    snapshot.data?.where((s) => s['gender'] == 'Male').length ??
                    0;
                int girls =
                    snapshot.data
                        ?.where((s) => s['gender'] == 'Female')
                        .length ??
                    0;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      "TOTAL ENROLLED",
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // 🚨 Increased from 32px to 42px
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        total.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 42,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -1.0,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 16,
                      runSpacing: 8,
                      children: [
                        _miniStatLabel(
                          "Boys",
                          boys.toString(),
                          Icons.boy_rounded,
                        ),
                        _miniStatLabel(
                          "Girls",
                          girls.toString(),
                          Icons.girl_rounded,
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniStatLabel(String title, String val, IconData icon) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white60, size: 16),
        const SizedBox(width: 4),
        Text(
          "$title: ",
          style: const TextStyle(
            color: Colors.white60,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
        // 🚨 Increased from 12px to 15px
        Text(
          val,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  Widget _buildSmartIdCard(
    Color cardColor,
    Color textColor,
    bool isDark,
    Color primaryColor,
  ) {
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const IdCardGeneratorScreen()),
      ),
      borderRadius: BorderRadius.circular(24),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
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
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.badge_rounded,
                color: Colors.orange,
                size: 28,
              ), // Increased icon size
            ),
            const SizedBox(height: 16),
            // Increased title font size to balance with the massive stats
            Text(
              "Smart ID",
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.w900,
                fontSize: 18,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "Bulk QR Cards",
              style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
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
    Color iconColor = isLegacy ? Colors.redAccent : primaryColor;

    String searchClassKey = className.toLowerCase().replaceAll(' ', '');
    String formMasterName = isLegacy
        ? "Action Required"
        : (_formMasters[searchClassKey] ?? "Not Assigned");

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isLegacy
              ? Colors.redAccent.withValues(alpha: 0.3)
              : (isDark ? Colors.white10 : Colors.grey.shade200),
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
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => _ClassListScreen(
                  className: className,
                  students: students,
                  allClasses: _allClassesData,
                  cardColor: cardColor,
                  textColor: textColor,
                  isDark: isDark,
                ),
              ),
            ).then((_) {
              if (mounted) _handleRefresh();
            });
          },
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isLegacy ? Icons.warning_rounded : Icons.class_rounded,
                    color: iconColor,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        className.toUpperCase(),
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 17,
                          color: isLegacy ? Colors.redAccent : textColor,
                          letterSpacing: -0.3,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        isLegacy
                            ? formMasterName
                            : "Form Master: $formMasterName",
                        style: TextStyle(
                          fontSize: 13,
                          color: isLegacy
                              ? Colors.redAccent
                              : Colors.grey.shade500,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: iconColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.people_alt_rounded,
                              size: 14,
                              color: iconColor,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              "${students.length} Students",
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                color: iconColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.grey.shade300,
                  size: 24,
                ),
              ],
            ),
          ),
        ),
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
        borderRadius: BorderRadius.circular(20),
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
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: Hero(
          tag: student['id'],
          child: CircleAvatar(
            radius: 24,
            backgroundColor: primaryColor.withValues(alpha: 0.1),
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
            fontSize: 15,
            color: textColor,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            "${student['admission_no'] ?? 'NO ID'} • ${student['gender']} • ${student['class_level']}",
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade500,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        trailing: Icon(
          Icons.chevron_right_rounded,
          color: Colors.grey.shade300,
          size: 20,
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

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.grey.shade100,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.person_search_rounded,
              size: 60,
              color: isDark ? Colors.white24 : Colors.grey[400],
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            "No students match your search",
            style: TextStyle(
              color: Colors.grey,
              fontSize: 16,
              fontWeight: FontWeight.w600,
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
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: primaryColor,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              onPressed: _handleRefresh,
              icon: const Icon(Icons.refresh_rounded, color: Colors.white),
              label: const Text(
                "Refresh",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// DEDICATED CLASS ROSTER SCREEN (POLISHED MODALS & CARDS)
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
        _selectedStudentIds.clear();
      } else {
        _selectedStudentIds.addAll(
          _localStudents.map((s) => s['id'].toString()),
        );
      }
    });
  }

  void _toggleStudent(String id) {
    setState(() {
      if (_selectedStudentIds.contains(id))
        _selectedStudentIds.remove(id);
      else
        _selectedStudentIds.add(id);
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
              backgroundColor: widget.cardColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              title: const Row(
                children: [
                  Icon(Icons.move_up_rounded, color: Colors.blue),
                  SizedBox(width: 10),
                  Text(
                    "Promote / Reassign",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Moving ${_selectedStudentIds.length} students to:",
                    style: TextStyle(
                      color: widget.isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    decoration: BoxDecoration(
                      color: widget.isDark
                          ? Colors.white.withValues(alpha: 0.05)
                          : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: widget.isDark
                            ? Colors.white10
                            : Colors.grey.shade200,
                      ),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        dropdownColor: widget.cardColor,
                        value: selectedClassId,
                        hint: const Padding(
                          padding: EdgeInsets.only(left: 16),
                          child: Text(
                            "Select Destination Class",
                            style: TextStyle(fontSize: 14),
                          ),
                        ),
                        items: widget.allClasses.map((c) {
                          return DropdownMenuItem<String>(
                            value: c['id'].toString(),
                            child: Padding(
                              padding: const EdgeInsets.only(left: 16),
                              child: Text(
                                c['name'].toString(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
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
              actionsPadding: const EdgeInsets.only(bottom: 20, right: 20),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.pop(ctx),
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
                  onPressed: (isSaving || selectedClassId == null)
                      ? null
                      : () async {
                          setDialogState(() => isSaving = true);
                          try {
                            await Supabase.instance.client
                                .from('students')
                                .update({
                                  'class_id': selectedClassId,
                                  'class_level': selectedClassName,
                                })
                                .inFilter('id', _selectedStudentIds.toList());

                            if (mounted) {
                              setState(() {
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
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          } catch (e) {
                            setDialogState(() => isSaving = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text("Failed to move students: $e"),
                                backgroundColor: Colors.red,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                  child: isSaving
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: TridetaLoader(color: Colors.white),
                        )
                      : const Text(
                          "CONFIRM",
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
            padding: const EdgeInsets.all(24),
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
                      ? primaryColor.withValues(alpha: 0.1)
                      : widget.cardColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected
                        ? primaryColor.withValues(alpha: 0.5)
                        : (widget.isDark
                              ? Colors.white.withValues(alpha: 0.05)
                              : Colors.grey.shade200),
                    width: 1.5,
                  ),
                  boxShadow: isSelected
                      ? []
                      : [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.02),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  leading: _isSelecting
                      ? Checkbox(
                          value: isSelected,
                          onChanged: (val) => _toggleStudent(sId),
                          activeColor: primaryColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                        )
                      : Hero(
                          tag: student['id'],
                          child: CircleAvatar(
                            radius: 24,
                            backgroundColor: primaryColor.withValues(
                              alpha: 0.1,
                            ),
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
                      fontSize: 15,
                      color: widget.textColor,
                    ),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      "${student['admission_no'] ?? 'NO ID'} • ${student['gender']}",
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: bgColor,
        foregroundColor: widget.textColor,
        elevation: 0,
        centerTitle: true,
        leading: _isSelecting
            ? IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => setState(() {
                  _isSelecting = false;
                  _selectedStudentIds.clear();
                }),
              )
            : null,
        actions: [
          if (_isSelecting)
            IconButton(
              icon: const Icon(Icons.select_all_rounded),
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
                    border: Border.symmetric(
                      vertical: BorderSide(
                        color: widget.isDark
                            ? Colors.white10
                            : Colors.grey.shade200,
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
