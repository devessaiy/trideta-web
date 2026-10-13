import 'package:trideta_v2/utils/auth_error_handler.dart';
import 'package:trideta_v2/services/holiday_gate.dart';
import 'package:trideta_v2/services/read_through.dart';
import 'package:trideta_v2/widgets/trideta_loader.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trideta_v2/services/app_activity_logger.dart'; // 🚨 INJECTED LOGGER
import 'package:trideta_v2/utils/resilient_request.dart';

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

  // School holiday control (admin only)
  bool _onHoliday = false;
  DateTime? _resumesOn;
  bool _holidayBusy = false;
  int _classesWithStudents = 0;
  int _classesPublished = 0;
  String? _schoolId;
  String _userRole = 'teacher';

  late List<String> _sessions;
  final List<String> _terms = ['1st Term', '2nd Term', '3rd Term'];
  String? _selectedSession;
  String? _selectedTerm;

  String? _globalSession;
  String? _globalTerm;

  String? _selectedClass;
  List<String> _activeClasses = [];

  final Map<String, String> _classNameToIdMap = {};

  List<String> _classSubjects = [];
  List<Map<String, dynamic>> _students = [];

  final Map<String, Map<String, dynamic>> _broadsheetData = {};

  @override
  void initState() {
    super.initState();
    _sessions = _generateDynamicSessions();
    _fetchInitialData();
  }

  List<String> _generateDynamicSessions() {
    int currentYear = DateTime.now().year;
    List<String> list = [];
    for (int i = 2020; i <= currentYear + 3; i++) {
      list.add("$i/${i + 1}");
    }
    return list;
  }

  Future<void> _fetchInitialData() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final profile = await readThrough(
        '350688ab|profiles|${user.id}',
        () async => await _supabase
            .from('profiles')
            .select('school_id, role')
            .eq('id', user.id)
            .single(),
        fresh: const Duration(minutes: 10),
      );

      _schoolId = profile['school_id'];
      _userRole = profile['role']?.toString().toLowerCase() ?? 'teacher';

      final school = await readThrough(
        'b6eeb681|schools|${_schoolId!}',
        () async => await _supabase
            .from('schools')
            .select('current_session, current_term')
            .eq('id', _schoolId!)
            .single(),
      );

      int currentYr = DateTime.now().year;
      _globalSession =
          school['current_session'] ?? "$currentYr/${currentYr + 1}";
      _globalTerm = school['current_term'] ?? _terms[0];

      if (!_sessions.contains(_globalSession)) {
        _sessions.add(_globalSession!);
      }

      List<String> fetchedClasses = [];
      _classNameToIdMap.clear();

      if (_userRole == 'admin' || _userRole == 'principal') {
        final classesData = await readThrough(
          '6a9467c4|classes|${_schoolId!}',
          () async => await _supabase
              .from('classes')
              .select('id, name, list_order')
              .eq('school_id', _schoolId!)
              .order('list_order', ascending: true),
          fresh: const Duration(minutes: 2),
        );
        for (var c in classesData) {
          String cName = c['name'].toString();
          _classNameToIdMap[cName] = c['id'].toString();
          fetchedClasses.add(cName);
        }
      } else {
        final assignments = await readThrough(
          'f97a3639|staff_assignments|${user.id}',
          () async => await _supabase
              .from('staff_assignments')
              .select('class_id')
              .eq('staff_id', user.id),
          fresh: const Duration(minutes: 2),
        );
        final Set<String> uniqueIds = {};
        for (var a in assignments) {
          if (a['class_id'] != null) uniqueIds.add(a['class_id'].toString());
        }
        if (uniqueIds.isNotEmpty) {
          final freshClasses = await readThrough(
            '4977419b|classes|${uniqueIds.toList()}',
            () async => await _supabase
                .from('classes')
                .select('id, name')
                .inFilter('id', uniqueIds.toList()),
            fresh: const Duration(minutes: 2),
          );
          for (var c in freshClasses) {
            String cName = c['name'].toString();
            _classNameToIdMap[cName] = c['id'].toString();
            fetchedClasses.add(cName);
          }
          fetchedClasses.sort();
        }
      }

      if (mounted) {
        setState(() {
          _selectedSession = _globalSession;
          _selectedTerm = _globalTerm;
          _activeClasses = fetchedClasses;
          _isLoading = false;
        });
        _loadHolidayStatus();
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
      final studentsData = await readThrough(
        '8411e4aa|students|${_schoolId!}|${_classNameToIdMap[_selectedClass]!}',
        () async => await _supabase
            .from('students')
            .select('id, first_name, last_name, admission_no')
            .eq('school_id', _schoolId!)
            .eq('class_id', _classNameToIdMap[_selectedClass]!)
            .order('first_name', ascending: true),
      );

      if (studentsData.isEmpty) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final scoresData = await readThrough(
        'a6aa6aff|exam_scores|${_schoolId!}|${_selectedSession!}|${_selectedTerm!}|${_classNameToIdMap[_selectedClass]!}',
        () async => await _supabase
            .from('exam_scores')
            .select('student_id, subject_name, total_score')
            .eq('school_id', _schoolId!)
            .eq('academic_session', _selectedSession!)
            .eq('term', _selectedTerm!)
            .eq('class_id', _classNameToIdMap[_selectedClass]!),
      );

      Set<String> uniqueSubjects = {};
      for (var score in scoresData) {
        if (score['subject_name'] != null) {
          uniqueSubjects.add(score['subject_name'].toString());
        }
      }
      List<String> subjectList = uniqueSubjects.toList();
      subjectList.sort();

      final termResultsData = await readThrough(
        '98e8374d|term_results|${_schoolId!}|${_selectedSession!}|${_selectedTerm!}|${_classNameToIdMap[_selectedClass]!}',
        () async => await _supabase
            .from('term_results')
            .select(
              'student_id, total_score, average_score, position, position_suffix',
            )
            .eq('school_id', _schoolId!)
            .eq('academic_session', _selectedSession!)
            .eq('term', _selectedTerm!)
            .eq('class_id', _classNameToIdMap[_selectedClass]!),
      );

      Map<String, dynamic> existingResults = {
        for (var item in termResultsData) item['student_id'].toString(): item,
      };

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

        for (String sub in subjectList) {
          tempGrid[sId]![sub] = null;
        }
      }

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

  Future<void> _computeAndSaveMasterBroadsheet() async {
    if (_selectedClass == null || _students.isEmpty) return;

    if (_userRole != 'admin' && _userRole != 'principal') {
      showAuthErrorDialog("Only administrators can Compute & Publish results.");
      return;
    }

    bool confirm = await _showConfirmDialog();
    if (!confirm) return;

    setState(() => _isComputing = true);

    try {
      List<String> rankedStudentIds = _broadsheetData.keys.toList();
      rankedStudentIds.sort((a, b) {
        double totalA = _broadsheetData[a]!['Total'];
        double totalB = _broadsheetData[b]!['Total'];
        return totalB.compareTo(totalA);
      });

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

      // ONE request for every student: all results are published together or
      // not at all, and repeating it is harmless (one row per student, session
      // and term). Principal remarks already saved are left untouched.
      final String stamp = DateTime.now().toIso8601String();
      final List<Map<String, dynamic>> rows = [
        for (final sId in rankedStudentIds)
          {
            'school_id': _schoolId,
            'student_id': sId,
            'academic_session': _selectedSession,
            'term': _selectedTerm,
            'class_id': _classNameToIdMap[_selectedClass],
            'class_level': _selectedClass,
            'total_score': _broadsheetData[sId]!['Total'],
            'average_score': _broadsheetData[sId]!['Average'],
            'position': int.parse(_broadsheetData[sId]!['Position']),
            'position_suffix': _getOrdinalSuffix(
              int.parse(_broadsheetData[sId]!['Position']),
            ),
            'updated_at': stamp,
          },
      ];
      await retryIdempotent(
        () async => await _supabase
            .from('term_results')
            .upsert(rows, onConflict: 'student_id, academic_session, term'),
        timeout: const Duration(seconds: 30),
      );

      // 🚨 INJECTED LOGGER
      if (_schoolId != null) {
        AppActivityLogger.log(
          schoolId: _schoolId!,
          module: 'academics',
          action: 'compute_broadsheet',
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Broadsheet Computed & Published Successfully!"),
            backgroundColor: Colors.green,
          ),
        );
        await _generateBroadsheet();
        _loadHolidayStatus();
      }
    } catch (e) {
      if (mounted) {
        showAuthErrorDialog("Failed during computation: $e");
      }
    } finally {
      if (mounted) setState(() => _isComputing = false);
    }
  }

  // ===========================================================================
  // SCHOOL HOLIDAY (declared by the admin once every class has been published)
  // ===========================================================================
  Future<void> _loadHolidayStatus() async {
    if (_userRole != 'admin' || _schoolId == null) return;
    try {
      final school = await retryRead(
        () async => await _supabase
            .from('schools')
            .select('is_on_holiday, holiday_resumes_on')
            .eq('id', _schoolId!)
            .single(),
        maxAttempts: 2,
        timeout: const Duration(seconds: 12),
      );

      final students = await retryRead(
        () async => await _supabase
            .from('students')
            .select('class_id')
            .eq('school_id', _schoolId!)
            .eq('is_active', true),
        maxAttempts: 2,
        timeout: const Duration(seconds: 15),
      );
      final published = await retryRead(
        () async => await _supabase
            .from('term_results')
            .select('class_id')
            .eq('school_id', _schoolId!)
            .eq('academic_session', _globalSession!)
            .eq('term', _globalTerm!),
        maxAttempts: 2,
        timeout: const Duration(seconds: 15),
      );

      final withStudents = <String>{
        for (final s in students)
          if (s['class_id'] != null) s['class_id'].toString(),
      };
      final publishedIds = <String>{
        for (final r in published)
          if (r['class_id'] != null) r['class_id'].toString(),
      };

      if (mounted) {
        setState(() {
          _onHoliday = school['is_on_holiday'] == true;
          _resumesOn = school['holiday_resumes_on'] == null
              ? null
              : DateTime.tryParse(school['holiday_resumes_on'].toString());
          _classesWithStudents = withStudents.length;
          _classesPublished = withStudents.intersection(publishedIds).length;
        });
      }
    } catch (e) {
      debugPrint("Holiday status load failed: $e");
    }
  }

  Future<DateTime?> _pickResumptionDate({DateTime? current}) {
    final today = HolidayGate.todayInNigeria;
    final first = today.add(const Duration(days: 1));
    final initial = (current != null && !current.isBefore(first))
        ? current
        : today.add(const Duration(days: 14));
    return showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: today.add(const Duration(days: 400)),
      helpText: 'RESUMPTION DATE',
    );
  }

  Future<void> _setHoliday(bool onHoliday) async {
    DateTime? date;
    if (onHoliday) {
      // The admin says when the school resumes. End of Term / End of Year can
      // only be run on or after that date.
      date = await _pickResumptionDate();
      if (date == null || !mounted) return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(onHoliday ? "Declare school holiday?" : "Cancel holiday?"),
        content: Text(
          onHoliday
              ? "The school will be on holiday until ${HolidayGate.formatDate(date!)}. Teachers cannot record attendance. On that date, run End of Term or End of Year to move the school to the new term and reopen attendance. Results can still be viewed and edited."
              : "Attendance will open again for teachers right away. Use this only if the holiday was declared by mistake.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Back"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(onHoliday ? "Declare holiday" : "Cancel holiday"),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _saveHoliday(
      {
        'is_on_holiday': onHoliday,
        'holiday_started_at': onHoliday
            ? DateTime.now().toUtc().toIso8601String()
            : null,
        'holiday_resumes_on': date == null ? null : HolidayGate.isoDate(date),
        'holiday_last_reminder_on': null,
      },
      onHoliday
          ? "School is now on holiday until ${HolidayGate.formatDate(date!)}."
          : "Holiday cancelled. Attendance is open again.",
    );
  }

  Future<void> _changeResumptionDate() async {
    final date = await _pickResumptionDate(current: _resumesOn);
    if (date == null || !mounted) return;
    await _saveHoliday({
      'holiday_resumes_on': HolidayGate.isoDate(date),
      'holiday_last_reminder_on': null,
    }, "Resumption date changed to ${HolidayGate.formatDate(date)}.");
  }

  Future<void> _saveHoliday(
    Map<String, dynamic> changes,
    String successMessage,
  ) async {
    setState(() => _holidayBusy = true);
    try {
      await retryIdempotent(
        () async => await _supabase
            .from('schools')
            .update(changes)
            .eq('id', _schoolId!),
        maxAttempts: 2,
      );
      await _loadHolidayStatus();
      if (mounted) {
        setState(() => _holidayBusy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(successMessage),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _holidayBusy = false);
        showAuthErrorDialog(
          "Could not update the holiday status. Please check your connection and try again.",
        );
      }
    }
  }

  Widget _buildHolidayCard(bool isDark, Color primaryColor) {
    final allPublished =
        _classesWithStudents > 0 && _classesPublished >= _classesWithStudents;

    Color accent;
    IconData icon;
    String title;
    String body;
    Widget? action;

    if (_onHoliday) {
      accent = Colors.orange.shade700;
      icon = Icons.beach_access_rounded;
      title = _resumesOn == null
          ? "School is on holiday"
          : "On holiday until ${HolidayGate.formatDate(_resumesOn!)}";
      body = _resumesOn == null
          ? "Set the date the school resumes. End of Term / End of Year can only be run on that date."
          : "Attendance is closed. On the resumption date, run End of Term or End of Year. That moves the school to the new term and reopens attendance.";
      action = Wrap(
        alignment: WrapAlignment.end,
        children: [
          TextButton(
            onPressed: _holidayBusy ? null : _changeResumptionDate,
            child: Text(_resumesOn == null ? "Set date" : "Change date"),
          ),
          TextButton(
            onPressed: _holidayBusy ? null : () => _setHoliday(false),
            child: const Text("Cancel holiday"),
          ),
        ],
      );
    } else if (allPublished) {
      accent = Colors.green.shade700;
      icon = Icons.check_circle_rounded;
      title = "All report cards are published";
      body =
          "$_classesPublished of $_classesWithStudents classes published. You can now declare the school on holiday and choose the resumption date.";
      action = ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
        ),
        onPressed: _holidayBusy ? null : () => _setHoliday(true),
        icon: const Icon(Icons.beach_access_rounded, size: 18),
        label: const Text("Declare School Holiday"),
      );
    } else {
      accent = Colors.grey.shade600;
      icon = Icons.hourglass_empty_rounded;
      title = "Holiday not available yet";
      body = _classesWithStudents == 0
          ? "There are no classes with students yet."
          : "Publish results for every class to unlock the holiday option ($_classesPublished of $_classesWithStudents classes published this term).";
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: accent, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: accent,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: isDark ? Colors.white70 : Colors.grey.shade700,
            ),
          ),
          if (action != null) ...[
            const SizedBox(height: 8),
            Align(alignment: Alignment.centerRight, child: action),
          ],
        ],
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC);
    Color cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    Color primaryColor = Theme.of(context).primaryColor;
    Color textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);

    bool isAdmin = _userRole == 'admin' || _userRole == 'principal';

    Widget mainContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.only(
              left: 10,
              top: 16,
              bottom: 16,
              right: 24,
            ),
            child: Row(
              children: [
                BackButton(color: textColor),
                const SizedBox(width: 4),
                Text(
                  "Master Broadsheet",
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: textColor,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
          ),
        ),

        if (_userRole == 'admin') _buildHolidayCard(isDark, primaryColor),

        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          decoration: BoxDecoration(
            color: cardColor,
            border: Border(
              bottom: BorderSide(
                color: isDark ? Colors.white10 : Colors.grey.shade200,
                width: 1,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _buildInfoField(
                      "Academic Session",
                      _selectedSession ?? "--",
                      isDark,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildInfoField(
                      "Current Term",
                      _selectedTerm ?? "--",
                      isDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _buildFilterDropdown(
                "Select Class to View Broadsheet",
                _activeClasses,
                _selectedClass,
                (val) {
                  setState(() {
                    _selectedClass = val;
                    if (val != null) {
                      _selectedSession = _globalSession;
                      _selectedTerm = _globalTerm;
                    }
                  });
                  _generateBroadsheet();
                },
                isDark,
                primaryColor,
              ),
            ],
          ),
        ),

        Expanded(
          child: _isLoading
              ? Center(child: TridetaLoader(color: primaryColor))
              : _students.isEmpty
              ? _buildPlaceholderState(isDark)
              : _buildBroadsheetGrid(isDark, primaryColor, cardColor),
        ),
      ],
    );

    return Scaffold(
      backgroundColor: bgColor,
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth > 1000) {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: Container(
                  decoration: BoxDecoration(
                    color: bgColor,
                    border: Border.symmetric(
                      vertical: BorderSide(
                        color: isDark ? Colors.white10 : Colors.grey.shade200,
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
      bottomNavigationBar: (_students.isNotEmpty && isAdmin)
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1200),
                  child: Container(
                    width: MediaQuery.of(context).size.width > 1200
                        ? 1200
                        : MediaQuery.of(context).size.width,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      color: cardColor,
                      border: Border(
                        top: BorderSide(
                          color: isDark ? Colors.white10 : Colors.grey.shade200,
                          width: 1,
                        ),
                      ),
                    ),
                    child: SafeArea(
                      child: SizedBox(
                        width: double.infinity,
                        height: 55,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: primaryColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: _isComputing
                              ? null
                              : _computeAndSaveMasterBroadsheet,
                          icon: _isComputing
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: TridetaLoader(color: Colors.white),
                                )
                              : const Icon(
                                  Icons.calculate,
                                  color: Colors.white,
                                ),
                          label: Text(
                            _isComputing ? "COMPUTING..." : "COMPUTE & PUBLISH",
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            )
          : null,
    );
  }

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
              return primaryColor.withValues(alpha: 0.1);
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

            ..._classSubjects.map((sub) {
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
                tooltip: sub,
              );
            }),

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

  Widget _buildInfoField(String label, String value, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade500,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _buildFilterDropdown(
    String hint,
    List<String> items,
    String? value,
    Function(String?)? onChanged,
    bool isDark,
    Color primaryColor,
  ) {
    bool isLocked = onChanged == null;
    return Container(
      decoration: BoxDecoration(
        color: isLocked
            ? (isDark ? Colors.white.withValues(alpha: 0.02) : Colors.grey[200])
            : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey[50]),
        borderRadius: BorderRadius.circular(10),
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
            child: Icon(
              isLocked ? Icons.lock_outline : Icons.arrow_drop_down,
              color: isLocked ? Colors.grey : primaryColor,
              size: isLocked ? 16 : 24,
            ),
          ),
          items: items
              .map(
                (e) => DropdownMenuItem(
                  value: e,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Text(
                      e,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isLocked ? Colors.grey : null,
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
