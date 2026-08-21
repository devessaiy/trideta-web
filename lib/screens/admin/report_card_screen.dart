import 'package:trideta_v2/utils/auth_error_handler.dart';
import 'package:trideta_v2/widgets/trideta_loader.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';

import 'package:trideta_v2/screens/admin/report_card_pdf_generator.dart';

class ReportCardScreen extends StatefulWidget {
  const ReportCardScreen({super.key});

  @override
  State<ReportCardScreen> createState() => _ReportCardScreenState();
}

class _ReportCardScreenState extends State<ReportCardScreen>
    with AuthErrorHandler {
  final _supabase = Supabase.instance.client;

  bool _isLoading = true;
  bool _isBulkGenerating = false;
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

  List<Map<String, dynamic>> _students = [];
  final Map<String, bool> _hasResultMap = {};

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

      int currentYr = DateTime.now().year;
      _globalSession =
          school['current_session'] ?? "$currentYr/${currentYr + 1}";
      _globalTerm = school['current_term'] ?? _terms[0];

      // 🚨 PREVENT CRASH: Ensure the dynamically fetched session is injected into the list
      if (!_sessions.contains(_globalSession)) {
        _sessions.add(_globalSession!);
      }

      List<String> fetchedClasses = [];
      _classNameToIdMap.clear();

      if (_userRole == 'admin' || _userRole == 'principal') {
        final classesData = await _supabase
            .from('classes')
            .select('id, name, list_order')
            .eq('school_id', _schoolId!)
            .order('list_order', ascending: true);
        for (var c in classesData) {
          String cName = c['name'].toString();
          _classNameToIdMap[cName] = c['id'].toString();
          fetchedClasses.add(cName);
        }
      } else {
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
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        showAuthErrorDialog("Failed to initialize. Check connection.");
      }
    }
  }

  Future<void> _fetchStudentsAndStatus() async {
    if (_selectedClass == null) return;
    setState(() => _isLoading = true);

    try {
      final studentsData = await _supabase
          .from('students')
          .select('id, first_name, last_name, admission_no')
          .eq('school_id', _schoolId!)
          .eq('class_id', _classNameToIdMap[_selectedClass]!)
          .order('first_name', ascending: true);

      final resultsData = await _supabase
          .from('term_results')
          .select('student_id')
          .eq('school_id', _schoolId!)
          .eq('academic_session', _selectedSession!)
          .eq('term', _selectedTerm!)
          .eq('class_id', _classNameToIdMap[_selectedClass]!);

      final Set<String> studentsWithResults = resultsData
          .map((r) => r['student_id'].toString())
          .toSet();

      _hasResultMap.clear();
      for (var student in studentsData) {
        String sId = student['id'].toString();
        _hasResultMap[sId] = studentsWithResults.contains(sId);
      }

      if (mounted) {
        setState(() {
          _students = List<Map<String, dynamic>>.from(studentsData);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        showAuthErrorDialog("Failed to load students.");
      }
    }
  }

  Future<void> _generatePDFForStudent(Map<String, dynamic> student) async {
    if (!_hasResultMap[student['id'].toString()]!) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Results are not ready! Please publish rankings first.",
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    String studentName = "${student['last_name']} ${student['first_name']}";

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TridetaLoader(color: Theme.of(context).primaryColor),
              const SizedBox(width: 20),
              const Text(
                "Generating result...",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      final bytes = await ReportCardPDFGenerator.generatePdfBytes(
        supabase: _supabase,
        studentId: student['id'].toString(),
        schoolId: _schoolId!,
        session: _selectedSession!,
        term: _selectedTerm!,
        className: _selectedClass!,
        studentName: studentName,
        admissionNo: student['admission_no']?.toString() ?? "N/A",
        format: PdfPageFormat.a4,
      );

      if (mounted) Navigator.pop(context);

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ReportCardPDFGenerator(
              studentId: student['id'].toString(),
              schoolId: _schoolId!,
              session: _selectedSession!,
              term: _selectedTerm!,
              className: _selectedClass!,
              studentName: studentName,
              admissionNo: student['admission_no']?.toString() ?? "N/A",
              precompiledPdfBytes: bytes,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      showAuthErrorDialog("Failed to generate: $e");
    }
  }

  Future<void> _bulkDownloadClassReports() async {
    setState(() => _isBulkGenerating = true);

    try {
      List<XFile> generatedPdfFiles = [];
      Directory? tempDir;

      // We only fetch a temporary directory if we are on a mobile device
      if (!kIsWeb) {
        tempDir = await getTemporaryDirectory();
      }

      for (var student in _students) {
        String sId = student['id'].toString();

        if (_hasResultMap[sId] == true) {
          String studentName =
              "${student['last_name'] ?? ''} ${student['first_name'] ?? ''}"
                  .trim();
          String admissionNo = student['admission_no']?.toString() ?? "N/A";

          Uint8List pdfBytes = await ReportCardPDFGenerator.generatePdfBytes(
            supabase: _supabase,
            studentId: sId,
            schoolId: _schoolId!,
            session: _selectedSession!,
            term: _selectedTerm!,
            className: _selectedClass!,
            studentName: studentName,
            admissionNo: admissionNo,
            format: PdfPageFormat.a4,
          );

          String safeName = studentName.replaceAll(
            RegExp(r'[^a-zA-Z0-9]'),
            '_',
          );
          String fileName = '${safeName}_ReportCard.pdf';

          if (kIsWeb) {
            generatedPdfFiles.add(
              XFile.fromData(
                pdfBytes,
                name: fileName,
                mimeType: 'application/pdf',
              ),
            );
          } else {
            File file = File('${tempDir!.path}/$fileName');
            await file.writeAsBytes(pdfBytes);
            generatedPdfFiles.add(XFile(file.path));
          }
        }
      }

      if (generatedPdfFiles.isNotEmpty) {
        await Share.shareXFiles(
          generatedPdfFiles,
          text: '$_selectedClass Report Cards - $_selectedTerm',
        );
      } else {
        if (mounted) {
          showAuthErrorDialog(
            "No results found!\n\nIt looks like the results for this class haven't been finalized yet. Please go to the 'Master Broadsheet' menu, select this class, and click 'Publish Rankings'.",
          );
        }
      }
    } catch (e) {
      debugPrint("💥 BULK GEN ERROR: $e");
      if (mounted) {
        showAuthErrorDialog("Developer Error Info:\n$e");
      }
    } finally {
      if (mounted) {
        setState(() => _isBulkGenerating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC);
    Color cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    Color primaryColor = Theme.of(context).primaryColor;
    Color textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);

    Widget mainContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 🚨 Dynamic Island / Notch Safe Header
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.only(left: 10, top: 16, bottom: 16, right: 24),
            child: Row(
              children: [
                BackButton(color: textColor),
                const SizedBox(width: 4),
                Text(
                  "Report Cards",
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
                "Select Class",
                _activeClasses,
                _selectedClass,
                (val) {
                  setState(() {
                    _selectedClass = val;
                    if (val != null) {
                      _selectedSession = _globalSession;
                      _selectedTerm = _globalTerm;
                    }
                    _students.clear();
                  });
                  _fetchStudentsAndStatus();
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
              : _selectedClass == null
              ? _buildPlaceholderState(isDark)
              : _students.isEmpty
              ? const Center(
                  child: Text(
                    "No students found in this class.",
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: _students.length,
                  separatorBuilder: (ctx, i) => Divider(
                    height: 1,
                    color: isDark ? Colors.white10 : Colors.grey.shade200,
                  ),
                  itemBuilder: (context, index) {
                    return _buildStudentCard(
                      _students[index],
                      cardColor,
                      isDark,
                      primaryColor,
                    );
                  },
                ),
        ),
      ],
    );

    return Scaffold(
      backgroundColor: bgColor,
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
                  child: mainContent,
                ),
              ),
            );
          } else {
            return mainContent;
          }
        },
      ),
      bottomNavigationBar: _students.isNotEmpty && _selectedClass != null
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: Container(
                    width: MediaQuery.of(context).size.width > 800 
                        ? 800 
                        : MediaQuery.of(context).size.width,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
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
                          onPressed: _isBulkGenerating ? null : _bulkDownloadClassReports,
                          icon: _isBulkGenerating
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: TridetaLoader(color: Colors.white),
                                )
                              : const Icon(Icons.inventory_2_rounded, color: Colors.white),
                          label: Text(
                            _isBulkGenerating ? "PACKING FILES..." : "BULK DOWNLOAD",
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
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

  Widget _buildInfoField(
    String label,
    String value,
    bool isDark,
  ) {
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

  Widget _buildStudentCard(
    Map<String, dynamic> student,
    Color cardColor,
    bool isDark,
    Color primaryColor,
  ) {
    String sId = student['id'].toString();
    bool hasResult = _hasResultMap[sId] ?? false;

    String fName = student['first_name']?.toString() ?? "";
    String initial = fName.isNotEmpty ? fName[0].toUpperCase() : "?";
    String displayFullName = "${student['last_name'] ?? 'Unknown'} $fName"
        .trim();

    return Container(
      color: isDark ? const Color(0xFF121212) : Colors.white,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: hasResult
              ? primaryColor.withValues(alpha: 0.1)
              : Colors.grey.withValues(alpha: 0.1),
          child: Text(
            initial,
            style: TextStyle(
              color: hasResult ? primaryColor : Colors.grey,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          displayFullName.toUpperCase(),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        subtitle: Text(
          hasResult ? "Result Computed & Ready" : "Pending Master Broadsheet",
          style: TextStyle(
            color: hasResult ? Colors.green : Colors.orange,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        trailing: IconButton.filled(
          onPressed: () => _generatePDFForStudent(student),
          icon: Icon(
            hasResult ? Icons.picture_as_pdf_rounded : Icons.lock_outline,
            size: 20,
          ),
          style: IconButton.styleFrom(
            backgroundColor: hasResult ? primaryColor : Colors.grey[300],
            foregroundColor: hasResult ? Colors.white : Colors.grey[600],
          ),
        ),
      ),
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
    if (items.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey[50],
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
            padding: const EdgeInsets.only(left: 10),
            child: Text(
              hint,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
          icon: Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Icon(Icons.arrow_drop_down, color: primaryColor),
          ),
          items: items
              .map(
                (e) => DropdownMenuItem(
                  value: e,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: Text(
                      e,
                      style: const TextStyle(
                        fontSize: 12,
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
            Icons.print_rounded,
            size: 80,
            color: isDark ? Colors.white10 : Colors.grey[200],
          ),
          const SizedBox(height: 15),
          Text(
            "Select a Class to view and\nprint student report cards.",
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