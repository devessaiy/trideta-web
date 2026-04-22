import 'package:trideta_v2/utils/auth_error_handler.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MasterBroadsheetScreen extends StatefulWidget {
  const MasterBroadsheetScreen({super.key});

  @override
  State<MasterBroadsheetScreen> createState() => _MasterBroadsheetScreenState();
}

class _MasterBroadsheetScreenState extends State<MasterBroadsheetScreen>
    with AuthErrorHandler {
  final _supabase = Supabase.instance.client;

  bool _isLoading = true;
  bool _isComputing = false;
  String? _schoolId;
  String _userRole = 'teacher';

  // --- FILTERS ---
  String? _selectedSession;
  String? _selectedTerm;
  String? _selectedClass;

  final List<String> _sessions = ['2024/2025', '2025/2026', '2026/2027'];
  final List<String> _terms = ['1st Term', '2nd Term', '3rd Term'];
  List<String> _activeClasses = [];

  // --- BROADSHEET DATA ---
  List<String> _classSubjects = []; // Grid Columns
  List<Map<String, dynamic>> _students = []; // Grid Rows

  // Map of Student ID -> Their Computed Data
  final Map<String, Map<String, dynamic>> _broadsheetData = {};

  @override
  void initState() {
    super.initState();
    _fetchInitialData();
  }

  // ===========================================================================
  // 1. DATA FETCHING & RBAC
  // ===========================================================================

  Future<void> _fetchInitialData() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final profile = await _supabase
          .from('profiles')
          .select('school_id, role')
          .eq('id', user.id)
          .single();

      _schoolId = profile['school_id'];
      _userRole = profile['role']?.toString().toLowerCase() ?? 'teacher';

      final school = await _supabase
          .from('schools')
          .select('current_session, current_term')
          .eq('id', _schoolId!)
          .single();

      List<String> fetchedClasses = [];

      if (_userRole == 'admin') {
        final classesData = await _supabase
            .from('classes')
            .select('name')
            .eq('school_id', _schoolId!)
            .order('list_order', ascending: true);
        fetchedClasses = classesData.map((c) => c['name'].toString()).toList();
      } else {
        // Teachers only see classes they are assigned to (as subject or form master)
        final assignments = await _supabase
            .from('staff_assignments')
            .select('class_assigned')
            .eq('staff_id', user.id);
        fetchedClasses = assignments
            .map((a) => a['class_assigned'].toString())
            .toSet()
            .toList();
        fetchedClasses.sort();
      }

      if (mounted) {
        setState(() {
          _selectedSession = school['current_session'] ?? _sessions[1];
          _selectedTerm = school['current_term'] ?? _terms[0];
          _activeClasses = fetchedClasses;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        showAuthErrorDialog("Failed to initialize. Check connection.");
      }
    }
  }

  Future<void> _generateBroadsheet() async {
    if (_selectedClass == null) return;

    setState(() => _isLoading = true);

    try {
      // 1. Get all subjects offered in this class (for the table headers)
      final subjectsData = await _supabase
          .from('class_subjects')
          .select('subject_name')
          .eq('school_id', _schoolId!)
          .eq('class_name', _selectedClass!);

      _classSubjects =
          subjectsData.map((s) => s['subject_name'].toString()).toList()
            ..sort();

      // 2. Get all students in this class
      final studentsData = await _supabase
          .from('students')
          .select('id, first_name, last_name, admission_no')
          .eq('school_id', _schoolId!)
          .eq('class_level', _selectedClass!)
          .order('first_name', ascending: true);

      _students = List<Map<String, dynamic>>.from(studentsData);

      // 3. Get ALL exam scores for this class, session, and term
      final scoresData = await _supabase
          .from('exam_scores')
          .select('student_id, subject_name, total_score')
          .eq('school_id', _schoolId!)
          .eq('class_level', _selectedClass!)
          .eq('academic_session', _selectedSession!)
          .eq('term', _selectedTerm!);

      // Group scores by Student ID
      Map<String, Map<String, double>> studentScores = {};
      for (var score in scoresData) {
        String sId = score['student_id'].toString();
        String subject = score['subject_name'].toString();
        double total = (score['total_score'] ?? 0).toDouble();

        studentScores.putIfAbsent(sId, () => {});
        studentScores[sId]![subject] = total;
      }

      // 4. Build the initial unranked broadsheet data
      _broadsheetData.clear();

      for (var student in _students) {
        String sId = student['id'].toString();
        var scores = studentScores[sId] ?? {};

        double grandTotal = 0;
        int subjectsTaken = 0;

        scores.forEach((key, value) {
          grandTotal += value;
          subjectsTaken++;
        });

        double average = subjectsTaken > 0 ? (grandTotal / subjectsTaken) : 0.0;

        _broadsheetData[sId] = {
          'scores': scores,
          'grand_total': grandTotal,
          'average': average,
          'subjects_taken': subjectsTaken,
          'position': 0, // Will compute next
          'suffix': '',
        };
      }

      // 5. Instantly compute rankings locally
      _computeRankingsLocally();

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        showAuthErrorDialog("Failed to generate broadsheet.");
      }
    }
  }

  // ===========================================================================
  // 2. THE RANKING ENGINE (Math & Ties)
  // ===========================================================================

  void _computeRankingsLocally() {
    // Create a list of students to sort by average
    List<Map<String, dynamic>> rankingList = _students.map((s) {
      String sId = s['id'].toString();
      return {'id': sId, 'average': _broadsheetData[sId]!['average'] as double};
    }).toList();

    // Sort descending (highest average first)
    rankingList.sort((a, b) => b['average'].compareTo(a['average']));

    int currentRank = 1;
    for (int i = 0; i < rankingList.length; i++) {
      // Handle ties (If average is exactly the same as the previous person, they share the rank)
      if (i > 0 && rankingList[i]['average'] == rankingList[i - 1]['average']) {
        // Keep currentRank the same
      } else {
        currentRank =
            i + 1; // Actual position (e.g., if two 1sts, next person is 3rd)
      }

      String sId = rankingList[i]['id'];

      // Only rank students who actually took exams
      if (rankingList[i]['average'] > 0) {
        _broadsheetData[sId]!['position'] = currentRank;
        _broadsheetData[sId]!['suffix'] = _getPositionSuffix(currentRank);
      } else {
        _broadsheetData[sId]!['position'] = 0; // Unranked / Absent
        _broadsheetData[sId]!['suffix'] = '-';
      }
    }
  }

  String _getPositionSuffix(int number) {
    if (number == 0) return "";
    if (number >= 11 && number <= 13) return "th";
    switch (number % 10) {
      case 1:
        return "st";
      case 2:
        return "nd";
      case 3:
        return "rd";
      default:
        return "th";
    }
  }

  // ===========================================================================
  // 3. DATABASE PUBLISHING
  // ===========================================================================

  Future<void> _publishRankingsToDatabase() async {
    setState(() => _isComputing = true);

    try {
      List<Map<String, dynamic>> upsertPayload = [];

      for (var student in _students) {
        String sId = student['id'].toString();
        var data = _broadsheetData[sId]!;

        if (data['average'] > 0) {
          upsertPayload.add({
            'school_id': _schoolId,
            'student_id': sId,
            'academic_session': _selectedSession,
            'term': _selectedTerm,
            'class_level': _selectedClass,
            'total_score': data['grand_total'],
            'average_score': data['average'],
            'position': data['position'],
            'position_suffix': data['suffix'],
            'updated_at': DateTime.now().toIso8601String(),
          });
        }
      }

      if (upsertPayload.isNotEmpty) {
        // Upsert into the new term_results table
        await _supabase
            .from('term_results')
            .upsert(
              upsertPayload,
              onConflict: 'student_id, academic_session, term',
            );
      }

      if (mounted) {
        setState(() => _isComputing = false);
        showSuccessDialog(
          "Rankings Published!",
          "Class positions have been successfully computed and saved. Report cards are now ready for printing.",
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isComputing = false);
        showAuthErrorDialog("Failed to publish rankings to database.");
      }
    }
  }

  // ===========================================================================
  // 4. UI BUILDERS
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC);
    Color cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    Color primaryColor = Theme.of(context).primaryColor;

    // 🚨 MAIN CONTENT EXTRACTED FOR LAYOUT BUILDER
    Widget mainContent = Column(
      children: [
        // 1. FILTER HEADER
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: cardColor,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _buildFilterDropdown(
                      "Session",
                      _sessions,
                      _selectedSession,
                      (val) {
                        setState(() {
                          _selectedSession = val;
                          _students.clear();
                        });
                      },
                      isDark,
                      primaryColor,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildFilterDropdown(
                      "Term",
                      _terms,
                      _selectedTerm,
                      (val) {
                        setState(() {
                          _selectedTerm = val;
                          _students.clear();
                        });
                      },
                      isDark,
                      primaryColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              _buildFilterDropdown(
                "Select Class to View Broadsheet",
                _activeClasses,
                _selectedClass,
                (val) {
                  setState(() => _selectedClass = val);
                  _generateBroadsheet(); // Automatically loads the grid!
                },
                isDark,
                primaryColor,
              ),
            ],
          ),
        ),

        // 2. SPREADSHEET GRID AREA
        Expanded(
          child: _isLoading
              ? Center(child: CircularProgressIndicator(color: primaryColor))
              : _selectedClass == null
              ? _buildPlaceholderState(isDark)
              : _students.isEmpty
              ? const Center(
                  child: Text(
                    "No students found in this class.",
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : _buildBroadsheetGrid(isDark, primaryColor),
        ),
      ],
    );

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text(
          "Master Broadsheet",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 0,
      ),
      // 🚨 SHAPE-SHIFTER: LayoutBuilder
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth > 800) {
            // 💻 DESKTOP LAYOUT (Constrained broad column for data grid)
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 1200,
                ), // Massive 1200px width for broadsheet!
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
      // 3. FLOATING ACTION BUTTON
      floatingActionButton: _students.isNotEmpty && _selectedClass != null
          ? FloatingActionButton.extended(
              backgroundColor: primaryColor,
              onPressed: _isComputing ? null : _publishRankingsToDatabase,
              icon: _isComputing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(
                      Icons.workspace_premium_rounded,
                      color: Colors.white,
                    ),
              label: Text(
                _isComputing ? "PUBLISHING..." : "PUBLISH RANKINGS",
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          : null,
    );
  }

  // --- SPREADSHEET BUILDER ---
  Widget _buildBroadsheetGrid(bool isDark, Color primaryColor) {
    Color headerColor = isDark ? Colors.grey[900]! : Colors.grey[100]!;
    Color textColor = isDark ? Colors.white : Colors.black87;

    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(headerColor),
          columnSpacing: 25,
          dataRowMaxHeight: 60,
          columns: [
            DataColumn(
              label: Text(
                "Student Name",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: primaryColor,
                ),
              ),
            ),

            // Dynamic Subject Columns
            ..._classSubjects.map(
              (sub) => DataColumn(
                label: Text(
                  sub.length > 5
                      ? sub.substring(0, 5).toUpperCase()
                      : sub.toUpperCase(),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[600],
                    fontSize: 12,
                  ),
                ),
              ),
            ),

            DataColumn(
              label: Text(
                "TOTAL",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: primaryColor,
                ),
              ),
            ),
            DataColumn(
              label: Text(
                "AVG",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: primaryColor,
                ),
              ),
            ),
            DataColumn(
              label: Text(
                "POS",
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: Colors.orange[700],
                ),
              ),
            ),
          ],
          rows: _students.map((student) {
            String sId = student['id'].toString();
            var data = _broadsheetData[sId]!;
            var scores = data['scores'] as Map<String, double>;

            return DataRow(
              cells: [
                // 1. Name Cell
                DataCell(
                  SizedBox(
                    width: 150,
                    child: Text(
                      "${student['last_name']} ${student['first_name']}",
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),

                // 2. Dynamic Subject Score Cells
                ..._classSubjects.map((sub) {
                  double score = scores[sub] ?? 0.0;
                  return DataCell(
                    Text(
                      score > 0 ? score.toInt().toString() : '-',
                      style: TextStyle(
                        color: score < 45 && score > 0
                            ? Colors.red
                            : (isDark ? Colors.white70 : Colors.black87),
                        fontWeight: score < 45
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  );
                }),

                // 3. Computed Cells (Total, Avg, Position)
                DataCell(
                  Text(
                    data['grand_total'].toInt().toString(),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                DataCell(
                  Text(
                    data['average'].toStringAsFixed(1),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),

                // Position Cell with styling
                DataCell(
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: data['position'] == 1
                          ? Colors.orange.withOpacity(0.2) // Gold for 1st
                          : data['position'] == 2
                          ? Colors.grey.withOpacity(0.2) // Silver for 2nd
                          : Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      data['position'] > 0
                          ? "${data['position']}${data['suffix']}"
                          : "N/A",
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: data['position'] == 1
                            ? Colors.orange[700]
                            : primaryColor,
                      ),
                    ),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildFilterDropdown(
    String hint,
    List<String> items,
    String? value,
    Function(String?) onChanged,
    bool isDark,
    Color primaryColor,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade300,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: value,
          hint: Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Text(
              hint,
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ),
          icon: Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Icon(Icons.arrow_drop_down, color: primaryColor),
          ),
          items: items
              .map(
                (e) => DropdownMenuItem(
                  value: e,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Text(
                      e,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
          onChanged: onChanged,
          dropdownColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        ),
      ),
    );
  }

  Widget _buildPlaceholderState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.table_chart_rounded,
            size: 80,
            color: isDark ? Colors.white10 : Colors.grey[200],
          ),
          const SizedBox(height: 15),
          Text(
            "Select a class to generate\nthe master broadsheet.",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isDark ? Colors.white38 : Colors.grey[400],
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}
