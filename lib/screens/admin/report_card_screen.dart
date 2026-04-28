import 'package:trideta_v2/utils/auth_error_handler.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb; // 🚨 Added to check for Web
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

  String? _selectedSession;
  String? _selectedTerm;
  String? _selectedClass;

  final List<String> _sessions = ['2024/2025', '2025/2026', '2026/2027'];
  final List<String> _terms = ['1st Term', '2nd Term', '3rd Term'];
  List<String> _activeClasses = [];

  // 🚨 ADDED: Hidden dictionary map to translate string names to UUIDs
  final Map<String, String> _classNameToIdMap = {};

  List<Map<String, dynamic>> _students = [];
  final Map<String, bool> _hasResultMap = {};

  @override
  void initState() {
    super.initState();
    _fetchInitialData();
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

      List<String> fetchedClasses = [];
      _classNameToIdMap.clear();

      if (_userRole == 'admin') {
        // Fetch IDs and Names, then map them together
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
        // Teacher Logic: Get assigned UUIDs, then get fresh names
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

  Future<void> _fetchStudentsAndStatus() async {
    if (_selectedClass == null) return;
    setState(() => _isLoading = true);

    try {
      final studentsData = await _supabase
          .from('students')
          .select('id, first_name, last_name, admission_no')
          .eq('school_id', _schoolId!)
          // 🚨 TRANSLATED TO UUID
          .eq('class_id', _classNameToIdMap[_selectedClass]!)
          .order('first_name', ascending: true);

      final resultsData = await _supabase
          .from('term_results')
          .select('student_id')
          .eq('school_id', _schoolId!)
          .eq('academic_session', _selectedSession!)
          .eq('term', _selectedTerm!)
          // 🚨 TRANSLATED TO UUID
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

  // 🚨 ANIMATED POPUP GENERATOR 🚨
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

    // 1. Show the Popup Dialog
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
              CircularProgressIndicator(color: Theme.of(context).primaryColor),
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
      // 2. Generate the PDF bytes in the background
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

      // 3. Close the Popup
      if (mounted) Navigator.pop(context);

      // 4. Navigate instantly to the Viewer using the pre-compiled bytes
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
              precompiledPdfBytes: bytes, // Pass bytes to load instantly!
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) Navigator.pop(context); // Close popup on error
      showAuthErrorDialog("Failed to generate: $e");
    }
  }

  Future<void> _bulkDownloadClassReports() async {
    // 🚨 WEB BROWSER SAFETY CHECK 🚨
    if (kIsWeb) {
      showAuthErrorDialog(
        "Web Browser Limitation!\n\nBulk Download requires access to a device's local folders to zip the files. Please open the App on your Android/iOS phone to use this feature.",
      );
      return;
    }

    setState(() => _isBulkGenerating = true);

    try {
      List<XFile> generatedPdfFiles = [];
      final tempDir = await getTemporaryDirectory();

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
          File file = File('${tempDir.path}/${safeName}_ReportCard.pdf');

          await file.writeAsBytes(pdfBytes);
          generatedPdfFiles.add(XFile(file.path));
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

    // 🚨 MAIN CONTENT EXTRACTED FOR LAYOUT BUILDER 🚨
    Widget mainContent = Column(
      children: [
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
                "Select Class",
                _activeClasses,
                _selectedClass,
                (val) {
                  setState(() => _selectedClass = val);
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
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _students.length,
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
      appBar: AppBar(
        title: const Text(
          "Report Cards",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 0,
      ),
      // 🚨 SHAPE-SHIFTER: LayoutBuilder Added
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
            // 📱 MOBILE LAYOUT (Full Width)
            return mainContent;
          }
        },
      ),
      floatingActionButton: _students.isNotEmpty && _selectedClass != null
          ? FloatingActionButton.extended(
              backgroundColor: primaryColor,
              onPressed: _isBulkGenerating ? null : _bulkDownloadClassReports,
              icon: _isBulkGenerating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.inventory_2_rounded, color: Colors.white),
              label: Text(
                _isBulkGenerating ? "PACKING FILES..." : "BULK DOWNLOAD",
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          : null,
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
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: hasResult
              ? primaryColor.withOpacity(0.1)
              : Colors.grey.withOpacity(0.1),
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
