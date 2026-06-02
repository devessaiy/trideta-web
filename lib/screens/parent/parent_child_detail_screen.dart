import 'package:trideta_v2/utils/auth_error_handler.dart';
import 'package:trideta_v2/widgets/trideta_loader.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'package:trideta_v2/screens/parent/parent_financial_service.dart';
import 'package:trideta_v2/screens/parent/receipt_detail_view.dart';

class ParentChildDetailScreen extends StatefulWidget {
  final Map<String, dynamic> childData;

  const ParentChildDetailScreen({super.key, required this.childData});

  @override
  State<ParentChildDetailScreen> createState() =>
      _ParentChildDetailScreenState();
}

class _ParentChildDetailScreenState extends State<ParentChildDetailScreen>
    with SingleTickerProviderStateMixin, AuthErrorHandler {
  final _supabase = Supabase.instance.client;
  final _financialService = ParentFinancialService();
  late TabController _tabController;

  bool _isLoading = true;
  bool _isFinanceActivated = true;

  // Academics
  String _attendancePercentage = "N/A";
  String _gradeAverage = "N/A";
  List<Map<String, dynamic>> _subjectGrades = [];

  // Finances
  double _totalExpected = 0.0;
  double _totalPaid = 0.0;
  List<Map<String, dynamic>> _receipts = [];

  // PDF Engine
  bool _isGeneratingRecord = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchDetails();
  }

  // Helper to get brand color safely
  Color _getSchoolColor(Color fallback) {
    String? hexStr = widget.childData['schools']?['brand_color'];
    if (hexStr != null && hexStr.isNotEmpty) {
      try {
        hexStr = hexStr.replaceAll('#', '');
        if (hexStr.length == 6) hexStr = 'FF$hexStr';
        return Color(int.parse(hexStr, radix: 16));
      } catch (_) {}
    }
    return fallback;
  }

  Future<void> _fetchDetails() async {
    try {
      final String studentId = widget.childData['id'].toString();
      final String schoolId = widget.childData['school_id'].toString();
      final String sClass = widget.childData['class_level']?.toString() ?? '';
      final String sCategory =
          widget.childData['category']?.toString() ?? 'Regular';
      final String currentSession =
          widget.childData['schools']['current_session']?.toString() ?? '';

      // --- ACADEMICS ---
      final classAttRes = await _supabase
          .from('attendance')
          .select('date')
          .eq('class_level', sClass);
      final uniqueDates = classAttRes.map((r) => r['date'].toString()).toSet();
      int totalSchoolDays = uniqueDates.length;

      final stuAttRes = await _supabase
          .from('attendance')
          .select('status')
          .eq('student_id', studentId);
      int presentCount = stuAttRes
          .where((r) => r['status'] == 'Punctual' || r['status'] == 'Late')
          .length;

      if (totalSchoolDays > 0) {
        double attPct = (presentCount / totalSchoolDays) * 100;
        _attendancePercentage =
            "${attPct.toStringAsFixed(1)}% ($presentCount/$totalSchoolDays Days)";
      } else {
        _attendancePercentage = "No Class Records";
      }

      final scoresRes = await _supabase
          .from('exam_scores')
          .select('subject_name, total_score, grade')
          .eq('student_id', studentId);
      if (scoresRes.isNotEmpty) {
        double totalSum = 0;
        List<Map<String, dynamic>> parsedGrades = [];
        for (var score in scoresRes) {
          double tot = (score['total_score'] as num?)?.toDouble() ?? 0.0;
          totalSum += tot;
          parsedGrades.add({
            'subject': score['subject_name'].toString(),
            'score': tot.toStringAsFixed(0),
            'grade': score['grade'].toString(),
          });
        }
        _gradeAverage = "${(totalSum / scoresRes.length).toStringAsFixed(1)}%";
        parsedGrades.sort((a, b) => a['subject'].compareTo(b['subject']));
        _subjectGrades = parsedGrades;
      }

      // --- FINANCES ---
      final financialSummary = await _financialService.getFinancialSummary(
        schoolId: schoolId,
        studentId: studentId,
        sClass: sClass,
        sCategory: sCategory,
        session: currentSession,
      );

      final paymentsRes = await _supabase
          .from('transactions')
          .select()
          .eq('student_id', studentId)
          .order('created_at', ascending: false);

      final feeCheck = await _supabase
          .from('fee_structures')
          .select('id')
          .eq('school_id', schoolId)
          .limit(1);

      if (mounted) {
        setState(() {
          _totalExpected = financialSummary['expected']!;
          _totalPaid = financialSummary['paid']!;
          _receipts = List<Map<String, dynamic>>.from(paymentsRes);
          _isFinanceActivated = feeCheck.isNotEmpty;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Child Detail Fetch Error: $e");
      if (mounted) {
        setState(() => _isLoading = false);
        showAuthErrorDialog("Failed to load records. Check your connection.");
      }
    }
  }

  Future<void> _generateComprehensiveRecord() async {
    setState(() => _isGeneratingRecord = true);

    try {
      final schoolId = widget.childData['school_id'].toString();
      final studentId = widget.childData['id'].toString();

      final schoolData = await _supabase
          .from('schools')
          .select('name, address, logo_url')
          .eq('id', schoolId)
          .single();
      final termResults = await _supabase
          .from('term_results')
          .select()
          .eq('student_id', studentId)
          .order('academic_session', ascending: false);
      final attendanceData = await _supabase
          .from('attendance')
          .select('status')
          .eq('student_id', studentId);

      List<dynamic> financeData = [];
      try {
        financeData = await _supabase
            .from('transactions')
            .select()
            .eq('student_id', studentId)
            .order('created_at', ascending: false);
      } catch (_) {}

      int punctual = attendanceData
          .where((r) => r['status'] == 'Punctual')
          .length;
      int late = attendanceData.where((r) => r['status'] == 'Late').length;
      int absent = attendanceData.where((r) => r['status'] == 'Absent').length;
      int sick = attendanceData.where((r) => r['status'] == 'Sick').length;

      pw.ImageProvider? logoProvider;
      if (schoolData['logo_url'] != null) {
        try {
          logoProvider = await networkImage(schoolData['logo_url']);
        } catch (_) {}
      }

      pw.ImageProvider? studentPhotoProvider;
      final imagePath = widget.childData['passport_url'];
      if (imagePath != null && imagePath.startsWith('http')) {
        try {
          studentPhotoProvider = await networkImage(imagePath);
        } catch (_) {}
      }

      final pdf = pw.Document();

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (pw.Context context) => [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                if (logoProvider != null)
                  pw.Container(
                    width: 60,
                    height: 60,
                    child: pw.Image(logoProvider, fit: pw.BoxFit.contain),
                  )
                else
                  pw.SizedBox(width: 60, height: 60),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Text(
                        (schoolData['name'] ?? 'School').toUpperCase(),
                        style: pw.TextStyle(
                          fontSize: 20,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.blue900,
                        ),
                        textAlign: pw.TextAlign.center,
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        schoolData['address'] ?? '',
                        style: const pw.TextStyle(
                          fontSize: 10,
                          color: PdfColors.grey700,
                        ),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(width: 60),
              ],
            ),
            pw.SizedBox(height: 15),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.symmetric(vertical: 8),
              decoration: pw.BoxDecoration(
                color: PdfColors.blue800,
                borderRadius: pw.BorderRadius.circular(5),
              ),
              child: pw.Text(
                "COMPREHENSIVE STUDENT DOSSIER",
                style: pw.TextStyle(
                  color: PdfColors.white,
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 14,
                ),
                textAlign: pw.TextAlign.center,
              ),
            ),
            pw.SizedBox(height: 20),

            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400),
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Row(
                children: [
                  if (studentPhotoProvider != null)
                    pw.Container(
                      width: 50,
                      height: 50,
                      margin: const pw.EdgeInsets.only(right: 15),
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: PdfColors.grey400),
                        image: pw.DecorationImage(
                          image: studentPhotoProvider,
                          fit: pw.BoxFit.cover,
                        ),
                      ),
                    )
                  else
                    pw.Container(
                      width: 50,
                      height: 50,
                      margin: const pw.EdgeInsets.only(right: 15),
                      color: PdfColors.grey200,
                    ),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          "Name: ${widget.childData['first_name']?.toUpperCase() ?? ''} ${widget.childData['last_name']?.toUpperCase() ?? ''}",
                          style: pw.TextStyle(
                            fontSize: 12,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          "Admission No: ${widget.childData['admission_no'] ?? 'N/A'}",
                          style: const pw.TextStyle(fontSize: 11),
                        ),
                        pw.Text(
                          "Class: ${widget.childData['class_level']}",
                          style: const pw.TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        "Date Printed:",
                        style: const pw.TextStyle(
                          fontSize: 9,
                          color: PdfColors.grey,
                        ),
                      ),
                      pw.Text(
                        DateTime.now().toString().split(' ')[0],
                        style: pw.TextStyle(
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 25),

            pw.Text(
              "ACADEMIC HISTORY",
              style: pw.TextStyle(
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.blue800,
              ),
            ),
            pw.SizedBox(height: 8),
            if (termResults.isEmpty)
              pw.Text(
                "No term results recorded yet.",
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey),
              )
            else
              pw.TableHelper.fromTextArray(
                headers: [
                  'Session',
                  'Term',
                  'Class',
                  'Average Score',
                  'Position',
                ],
                data: termResults
                    .map(
                      (r) => [
                        r['academic_session'] ?? '',
                        r['term'] ?? '',
                        r['class_level'] ?? '',
                        "${r['average_score'] ?? 0}%",
                        "${r['position'] ?? '-'}${r['position_suffix'] ?? ''}",
                      ],
                    )
                    .toList(),
                headerStyle: pw.TextStyle(
                  color: PdfColors.white,
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 10,
                ),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColors.blueGrey600,
                ),
                cellStyle: const pw.TextStyle(fontSize: 10),
              ),
            pw.SizedBox(height: 25),

            pw.Text(
              "ATTENDANCE SUMMARY",
              style: pw.TextStyle(
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.blue800,
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                _buildPdfStatBox(
                  "Punctual",
                  punctual.toString(),
                  PdfColors.green700,
                ),
                _buildPdfStatBox("Late", late.toString(), PdfColors.orange700),
                _buildPdfStatBox("Absent", absent.toString(), PdfColors.red700),
                _buildPdfStatBox(
                  "Sick/Excused",
                  sick.toString(),
                  PdfColors.purple700,
                ),
              ],
            ),
            pw.SizedBox(height: 25),

            pw.Text(
              "FINANCIAL RECORDS",
              style: pw.TextStyle(
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.blue800,
              ),
            ),
            pw.SizedBox(height: 8),
            if (financeData.isEmpty)
              pw.Text(
                "No financial records found.",
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey),
              )
            else
              pw.TableHelper.fromTextArray(
                headers: [
                  'Date',
                  'Session/Term',
                  'Description',
                  'Amount Paid',
                  'Status',
                ],
                data: financeData
                    .map(
                      (f) => [
                        f['created_at']?.toString().split('T')[0] ?? '',
                        "${f['academic_session'] ?? ''}",
                        f['category'] ?? 'School Fees',
                        "NGN ${f['amount'] ?? 0}",
                        'Completed',
                      ],
                    )
                    .toList(),
                headerStyle: pw.TextStyle(
                  color: PdfColors.white,
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 10,
                ),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColors.blueGrey600,
                ),
                cellStyle: const pw.TextStyle(fontSize: 10),
              ),
          ],
        ),
      );

      final bytes = await pdf.save();

      if (mounted) {
        setState(() => _isGeneratingRecord = false);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => Scaffold(
              appBar: AppBar(title: const Text("Report Sheet / Dossier")),
              body: PdfPreview(
                build: (format) => bytes,
                pdfFileName: "${widget.childData['first_name']}_Report.pdf",
                allowPrinting: true,
                allowSharing: true,
              ),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isGeneratingRecord = false);
        showAuthErrorDialog("Error generating dossier: $e");
      }
    }
  }

  pw.Widget _buildPdfStatBox(String title, String val, PdfColor color) {
    return pw.Container(
      width: 100,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: color, width: 1.5),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(
              fontSize: 9,
              color: color,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 5),
          pw.Text(
            val,
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.black,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC);
    Color cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    Color primaryColor = Theme.of(context).primaryColor;
    Color schoolColor = _getSchoolColor(
      primaryColor,
    ); // 🚨 Uses School Brand Color

    String fName = widget.childData['first_name'] ?? '';
    String lName = widget.childData['last_name'] ?? '';
    String initial = fName.isNotEmpty ? fName[0] : '?';
    String passport = widget.childData['passport_url'] ?? '';

    double balance = _totalExpected - _totalPaid;
    if (balance < 0) balance = 0;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(
          "$fName's Records",
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        foregroundColor: isDark ? Colors.white : Colors.black,
        elevation: 0,
        centerTitle: true,
      ),
      body: Column(
        children: [
          // ─── PREMIUM GLASSY HEADER ───
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 30),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [schoolColor.withValues(alpha: 0.85), schoolColor],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(32),
              ),
              boxShadow: [
                BoxShadow(
                  color: schoolColor.withValues(alpha: 0.2),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: CircleAvatar(
                    radius: 40,
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                    backgroundImage: passport.isNotEmpty
                        ? NetworkImage(passport)
                        : null,
                    child: passport.isEmpty
                        ? Text(
                            initial,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 32,
                            ),
                          )
                        : null,
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "$fName $lName",
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: -0.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              widget.childData['class_level'] ?? 'Unassigned',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            "Session: ${widget.childData['schools']['current_session'] ?? 'N/A'}",
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ─── MODERN PILL TAB BAR ───
          Container(
            margin: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            decoration: BoxDecoration(
              color: isDark ? Colors.white10 : Colors.grey.shade200,
              borderRadius: BorderRadius.circular(16),
            ),
            child: TabBar(
              controller: _tabController,
              labelColor: isDark ? Colors.black : Colors.white,
              unselectedLabelColor: isDark
                  ? Colors.white70
                  : Colors.grey.shade600,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                color: isDark ? Colors.white : schoolColor,
                borderRadius: BorderRadius.circular(16),
              ),
              dividerColor: Colors.transparent, // Removes the ugly bottom line
              tabs: const [
                Tab(
                  child: Text(
                    "ACADEMICS",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
                Tab(
                  child: Text(
                    "FINANCES",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),

          // ─── TAB CONTENT ───
          Expanded(
            child: _isLoading
                ? Center(child: TridetaLoader(color: schoolColor))
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildAcademicTab(
                        isDark,
                        schoolColor,
                        cardColor,
                        balance,
                      ),
                      _buildFinanceTab(isDark, schoolColor, cardColor, balance),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildAcademicTab(
    bool isDark,
    Color schoolColor,
    Color cardColor,
    double balance,
  ) {
    bool isLocked = balance > 0;
    Color textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Expanded(
              child: _buildGlassyStatCard(
                "Attendance",
                _attendancePercentage,
                Icons.calendar_month_rounded,
                Colors.blue,
                cardColor,
                isDark,
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: _buildGlassyStatCard(
                "Average",
                _gradeAverage,
                Icons.auto_graph_rounded,
                Colors.purple,
                cardColor,
                isDark,
              ),
            ),
          ],
        ),
        const SizedBox(height: 30),

        Text(
          "SUBJECT GRADES",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12,
            color: Colors.grey.shade500,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 12),

        if (_subjectGrades.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(40.0),
              child: Text(
                "No scores recorded yet.",
                style: TextStyle(color: Colors.grey.shade500),
              ),
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark ? Colors.white10 : Colors.grey.shade200,
              ),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _subjectGrades.length,
              separatorBuilder: (context, index) => Divider(
                height: 1,
                color: isDark ? Colors.white10 : Colors.grey.shade100,
                indent: 20,
                endIndent: 20,
              ),
              itemBuilder: (context, index) {
                final gradeData = _subjectGrades[index];
                Color gColor = Colors.grey;
                if (gradeData['grade'] == 'A') gColor = Colors.green;
                if (gradeData['grade'] == 'B') gColor = Colors.blue;
                if (gradeData['grade'] == 'C') gColor = Colors.orange;
                if (gradeData['grade'] == 'P') gColor = Colors.purple;
                if (gradeData['grade'] == 'F') gColor = Colors.red;

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 4,
                  ),
                  title: Text(
                    gradeData['subject'],
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: textColor,
                    ),
                  ),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: gColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      "${gradeData['score']} (${gradeData['grade']})",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: gColor,
                        fontSize: 12,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

        const SizedBox(height: 30),

        Text(
          "REPORT SHEETS & RECORDS",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12,
            color: Colors.grey.shade500,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 12),

        Card(
          color: cardColor,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: isLocked
                  ? Colors.red.withValues(alpha: 0.3)
                  : schoolColor.withValues(alpha: 0.3),
              width: 1.5,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: isLocked
                ? () {
                    showAuthErrorDialog(
                      "Please clear the outstanding balance of ₦${balance.toStringAsFixed(0)} in the Finances tab to unlock this student's report sheet.",
                    );
                  }
                : (_isGeneratingRecord ? null : _generateComprehensiveRecord),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isLocked
                          ? Colors.red.withValues(alpha: 0.1)
                          : schoolColor.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isLocked
                          ? Icons.lock_outline_rounded
                          : Icons.picture_as_pdf_rounded,
                      color: isLocked ? Colors.red : schoolColor,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Full Academic Dossier",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: isLocked ? Colors.red : textColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isLocked
                              ? "Locked due to outstanding fees."
                              : "Download complete historic report sheet.",
                          style: TextStyle(
                            fontSize: 12,
                            color: isLocked
                                ? Colors.red.shade300
                                : Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _isGeneratingRecord
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: TridetaLoader(color: schoolColor),
                        )
                      : Icon(
                          isLocked
                              ? Icons.lock_rounded
                              : Icons.download_rounded,
                          color: isLocked ? Colors.red : schoolColor,
                        ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildFinanceTab(
    bool isDark,
    Color schoolColor,
    Color cardColor,
    double balance,
  ) {
    final formatCurrency = NumberFormat.currency(symbol: '₦');
    Color textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (!_isFinanceActivated)
          Container(
            margin: const EdgeInsets.only(bottom: 20),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  color: Colors.orange,
                  size: 28,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        "Financial Engine Not Activated",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange,
                          fontSize: 14,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        "The school administration has not yet published the fee structures.",
                        style: TextStyle(fontSize: 12, color: Colors.orange),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: balance > 0
                ? Colors.red.withValues(alpha: 0.05)
                : Colors.green.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: balance > 0
                  ? Colors.red.withValues(alpha: 0.3)
                  : Colors.green.withValues(alpha: 0.3),
              width: 1.5,
            ),
          ),
          child: Column(
            children: [
              Text(
                "CURRENT OUTSTANDING",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: balance > 0 ? Colors.red : Colors.green,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                formatCurrency.format(balance),
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w900,
                  color: balance > 0 ? Colors.red : Colors.green,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 30),

        Text(
          "PAYMENT HISTORY",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12,
            color: Colors.grey.shade500,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 12),

        if (_receipts.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(40.0),
              child: Text(
                "No payments made yet.",
                style: TextStyle(color: Colors.grey.shade500),
              ),
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark ? Colors.white10 : Colors.grey.shade200,
              ),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _receipts.length,
              separatorBuilder: (context, index) => Divider(
                height: 1,
                color: isDark ? Colors.white10 : Colors.grey.shade100,
                indent: 20,
                endIndent: 20,
              ),
              itemBuilder: (context, index) {
                final tx = _receipts[index];
                return InkWell(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ReceiptDetailView(tx: tx),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.receipt_long_rounded,
                            color: Colors.green,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tx['category'] ?? 'Fee Payment',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: textColor,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                DateFormat(
                                  'MMM d, yyyy',
                                ).format(DateTime.parse(tx['created_at'])),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          formatCurrency.format(tx['amount']),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildGlassyStatCard(
    String title,
    String val,
    IconData icon,
    Color color,
    Color cardColor,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
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
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade500,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            val,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
