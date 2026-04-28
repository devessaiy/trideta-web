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

  // 🚨 ADDED: Hidden dictionary map to translate string names to UUIDs
  final Map<String, String> _classNameToIdMap = {};

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
  // 1. INITIALIZATION & DATA FETCHING
  // ===========================================================================

  // 🚨 REWRITTEN: Populates the dictionary and the dropdown
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
      _classNameToIdMap.clear();

      if (_userRole == 'admin') {
        final classesData = await _supabase
            .from('classes')
            .select('id, name')
            .eq('school_id', _schoolId!)
            .order('list_order', ascending: true);
        for (var c in classesData) {
          _classNameToIdMap[c['name'].toString()] = c['id'].toString();
          fetchedClasses.add(c['name'].toString());
        }
      } else {
        // Teachers only see classes they are assigned to
        final assignments = await _supabase
            .from('staff_assignments')
            .select('class_id')
            .eq('staff_id', user.id);
        final Set<String> uniqueIds = {};
        for (var a in assignments) {
          if (a['class_id'] != null) uniqueIds.add(a['class_id'].toString());
        }
        if (uniqueIds.isNotEmpty) {
          final freshClasses = await _supabase
              .from('classes')
              .select('id, name')
              .inFilter('id', uniqueIds.toList());
          for (var c in freshClasses) {
            _classNameToIdMap[c['name'].toString()] = c['id'].toString();
            fetchedClasses.add(c['name'].toString());
          }
          fetchedClasses.sort();
        }
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

    setState(() {
      _isLoading = true;
      _students.clear();
      _classSubjects.clear();
      _broadsheetData.clear();
    });

    await _fetchBroadsheetData();
  }

  Future<void> _fetchBroadsheetData() async {
    try {
      // 1. Get all active students in the selected class
      final studentsData = await _supabase
          .from('students')
          .select('id, first_name, last_name, admission_no')
          .eq('school_id', _schoolId!)
          // 🚨 TRANSLATED TO UUID
          .eq('class_id', _classNameToIdMap[_selectedClass]!)
          .order('first_name', ascending: true);

      if (studentsData.isEmpty) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      // 2. Fetch ALL exam scores for this class + session + term
      final scoresData = await _supabase
          .from('exam_scores')
          .select('student_id, subject_name, total_score')
          .eq('school_id', _schoolId!)
          .eq('academic_session', _selectedSession!)
          .eq('term', _selectedTerm!)
          // 🚨 TRANSLATED TO UUID
          .eq('class_id', _classNameToIdMap[_selectedClass]!);

      // 3. Extract unique subjects taught in this class
      Set<String> uniqueSubjects = {};
      for (var score in scoresData) {
        if (score['subject_name'] != null) {
          uniqueSubjects.add(score['subject_name'].toString());
        }
      }
      List<String> subjectList = uniqueSubjects.toList();
      subjectList.sort();

      // 4. Fetch existing published positions/averages (if any)
      final termResultsData = await _supabase
          .from('term_results')
          .select(
            'student_id, total_score, average_score, position, position_suffix',
          )
          .eq('school_id', _schoolId!)
          .eq('academic_session', _selectedSession!)
          .eq('term', _selectedTerm!)
          // 🚨 TRANSLATED TO UUID
          .eq('class_id', _classNameToIdMap[_selectedClass]!);

      Map<String, dynamic> existingResults = {
        for (var item in termResultsData) item['student_id'].toString(): item,
      };

      // 5. Structure the Grid Data
      Map<String, Map<String, dynamic>> tempGrid = {};

      for (var student in studentsData) {
        String sId = student['id'].toString();

        tempGrid[sId] = {
          'id': sId,
          'name': "${student['last_name']} ${student['first_name']}",
          'admission_no': student['admission_no'] ?? 'N/A',
          'Total': 0.0,
          'Average': 0.0,
          'Position': existingResults[sId]?['position']?.toString() ?? '-',
          'PositionSuffix': existingResults[sId]?['position_suffix'] ?? '',
        };

        // Initialize all subjects with null (meaning no score entered yet)
        for (String sub in subjectList) {
          tempGrid[sId]![sub] = null;
        }
      }

      // 6. Populate grid with scores and compute raw totals
      for (var score in scoresData) {
        String sId = score['student_id'].toString();
        String subject = score['subject_name'].toString();
        double totalScore =
            double.tryParse(score['total_score']?.toString() ?? '0') ?? 0;

        if (tempGrid.containsKey(sId)) {
          tempGrid[sId]![subject] = totalScore;
          tempGrid[sId]!['Total'] =
              (tempGrid[sId]!['Total'] as double) + totalScore;
        }
      }

      // Compute simple averages locally for display (before official publish)
      for (var sId in tempGrid.keys) {
        int subjectsTaken = 0;
        for (String sub in subjectList) {
          if (tempGrid[sId]![sub] != null) subjectsTaken++;
        }
        if (subjectsTaken > 0) {
          tempGrid[sId]!['Average'] =
              (tempGrid[sId]!['Total'] as double) / subjectsTaken;
        }
      }

      if (mounted) {
        setState(() {
          _classSubjects = subjectList;
          _students = List<Map<String, dynamic>>.from(studentsData);
          _broadsheetData.addAll(tempGrid);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        showAuthErrorDialog("Failed to load Broadsheet.");
      }
    }
  }

  // ===========================================================================
  // 2. COMPUTATION & PUBLISHING LOGIC
  // ===========================================================================

  Future<void> _computeAndSaveMasterBroadsheet() async {
    if (_selectedClass == null || _students.isEmpty) return;

    // Admin authorization check
    if (_userRole != 'admin') {
      showAuthErrorDialog("Only administrators can Compute & Publish results.");
      return;
    }

    bool confirm = await _showConfirmDialog();
    if (!confirm) return;

    setState(() => _isComputing = true);

    try {
      // 1. Sort students by Total Score (Descending) to find positions
      List<String> rankedStudentIds = _broadsheetData.keys.toList();
      rankedStudentIds.sort((a, b) {
        double totalA = _broadsheetData[a]!['Total'];
        double totalB = _broadsheetData[b]!['Total'];
        return totalB.compareTo(totalA); // Highest first
      });

      // 2. Assign positions (handling ties properly)
      int currentRank = 1;
      int nextRank = 1;
      double previousScore = -1.0;

      for (int i = 0; i < rankedStudentIds.length; i++) {
        String sId = rankedStudentIds[i];
        double score = _broadsheetData[sId]!['Total'];

        if (score != previousScore) {
          currentRank = nextRank;
        }

        _broadsheetData[sId]!['Position'] = currentRank.toString();
        _broadsheetData[sId]!['PositionSuffix'] = _getOrdinalSuffix(
          currentRank,
        );

        previousScore = score;
        nextRank++;
      }

      // 3. Save to `term_results` table so Parents/Report Cards can see it
      for (String sId in rankedStudentIds) {
        var stData = _broadsheetData[sId]!;
        int position = int.parse(stData['Position']);

        // Check if record exists
        final existing = await _supabase
            .from('term_results')
            .select('id')
            .eq('student_id', sId)
            .eq('academic_session', _selectedSession!)
            .eq('term', _selectedTerm!)
            .maybeSingle();

        if (existing == null) {
          // Insert
          await _supabase.from('term_results').insert({
            'school_id': _schoolId,
            'student_id': sId,
            'academic_session': _selectedSession,
            'term': _selectedTerm,
            // 🚨 TRANSLATED TO UUID
            'class_id': _classNameToIdMap[_selectedClass],
            'class_level': _selectedClass, // Kept for readable db records
            'total_score': stData['Total'],
            'average_score': stData['Average'],
            'position': position,
            'position_suffix': _getOrdinalSuffix(position),
            'updated_at': DateTime.now().toIso8601String(),
          });
        } else {
          // Update
          await _supabase
              .from('term_results')
              .update({
                'total_score': stData['Total'],
                'average_score': stData['Average'],
                'position': position,
                'position_suffix': _getOrdinalSuffix(position),
                'updated_at': DateTime.now().toIso8601String(),
              })
              .eq('student_id', sId)
              .eq('academic_session', _selectedSession!)
              .eq('term', _selectedTerm!)
              // 🚨 TRANSLATED TO UUID
              .eq('class_id', _classNameToIdMap[_selectedClass]!);
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Broadsheet Computed & Published Successfully!"),
            backgroundColor: Colors.green,
          ),
        );
        // Refresh grid to show new positions
        await _generateBroadsheet();
      }
    } catch (e) {
      if (mounted) {
        showAuthErrorDialog("Failed during computation: $e");
      }
    } finally {
      if (mounted) setState(() => _isComputing = false);
    }
  }

  String _getOrdinalSuffix(int number) {
    if (number >= 11 && number <= 13) {
      return 'th';
    }
    switch (number % 10) {
      case 1:
        return 'st';
      case 2:
        return 'nd';
      case 3:
        return 'rd';
      default:
        return 'th';
    }
  }

  Future<bool> _showConfirmDialog() async {
    bool? res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Compute & Publish?"),
        content: const Text(
          "This will lock in the total scores, calculate class positions, and officially publish the results to parent portals and report cards. Continue?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              "Yes, Compute",
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    return res ?? false;
  }

  // ===========================================================================
  // 3. UI BUILDING
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

        // 2. DATATABLE SPREADSHEET
        Expanded(
          child: _isLoading
              ? Center(child: CircularProgressIndicator(color: primaryColor))
              : _students.isEmpty
              ? _buildPlaceholderState(isDark)
              : _buildBroadsheetGrid(isDark, primaryColor, cardColor),
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
        elevation: 0,
        actions: [
          if (_students.isNotEmpty && _userRole == 'admin')
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: primaryColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: _isComputing
                    ? null
                    : _computeAndSaveMasterBroadsheet,
                icon: _isComputing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.calculate, size: 18),
                label: Text(
                  _isComputing ? "Computing..." : "Compute & Publish",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth > 1000) {
            // DESKTOP/WEB LAYOUT: Center it and add margins
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 20),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(
                      color: isDark ? Colors.white10 : Colors.grey.shade200,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(15),
                    child: mainContent,
                  ),
                ),
              ),
            );
          } else {
            // MOBILE/TABLET LAYOUT: Full width
            return mainContent;
          }
        },
      ),
    );
  }

  // ===========================================================================
  // 4. WIDGET HELPERS
  // ===========================================================================

  Widget _buildBroadsheetGrid(
    bool isDark,
    Color primaryColor,
    Color cardColor,
  ) {
    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(
            isDark ? Colors.white10 : Colors.grey[200],
          ),
          dataRowColor: WidgetStateProperty.resolveWith<Color>((
            Set<WidgetState> states,
          ) {
            if (states.contains(WidgetState.selected)) {
              return primaryColor.withOpacity(0.1);
            }
            return cardColor;
          }),
          border: TableBorder.all(
            color: isDark ? Colors.white10 : Colors.grey.shade300,
            width: 1,
          ),
          columnSpacing: 25,
          horizontalMargin: 20,
          columns: [
            const DataColumn(
              label: Text("SN", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            const DataColumn(
              label: Text(
                "Name",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),

            // Dynamic Subject Columns
            ..._classSubjects.map((sub) {
              // Extract first 4 letters for compact header
              String compactTitle = sub.length > 5
                  ? sub.substring(0, 5).toUpperCase()
                  : sub.toUpperCase();
              return DataColumn(
                label: Text(
                  compactTitle,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: primaryColor,
                  ),
                ),
                tooltip: sub, // Full name on hover
              );
            }),

            // Summary Columns
            const DataColumn(
              label: Text(
                "TOTAL",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
            ),
            const DataColumn(
              label: Text(
                "AVG",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.purple,
                ),
              ),
            ),
            const DataColumn(
              label: Text(
                "POS",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
            ),
          ],
          rows: List<DataRow>.generate(_students.length, (index) {
            String sId = _students[index]['id'].toString();
            var rowData = _broadsheetData[sId]!;

            return DataRow(
              cells: [
                DataCell(Text("${index + 1}")),
                DataCell(
                  SizedBox(
                    width: 150,
                    child: Text(
                      rowData['name'],
                      style: const TextStyle(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),

                // Dynamic Subject Scores
                ..._classSubjects.map((sub) {
                  var score = rowData[sub];
                  return DataCell(
                    Center(
                      child: Text(
                        score != null ? score.toStringAsFixed(0) : "-",
                        style: TextStyle(
                          color: score == null ? Colors.grey : null,
                          fontWeight: score != null
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  );
                }),

                // Summary Data Cells
                DataCell(
                  Text(
                    (rowData['Total'] as double).toStringAsFixed(1),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                ),
                DataCell(
                  Text(
                    (rowData['Average'] as double).toStringAsFixed(1),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.purple,
                    ),
                  ),
                ),
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        rowData['Position'],
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        rowData['PositionSuffix'],
                        style: const TextStyle(color: Colors.red, fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }),
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
