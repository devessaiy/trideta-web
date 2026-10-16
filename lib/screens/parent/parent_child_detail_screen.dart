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
import 'package:trideta_v2/screens/parent/parent_ui_kit.dart';

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

      // 🚨 FIXED: Fetch real-time active session and term directly from the database!
      final schoolData = await _supabase
          .from('schools')
          .select('current_session, current_term')
          .eq('id', schoolId)
          .single();

      final String currentSession =
          schoolData['current_session']?.toString() ?? '';
      final String currentTerm =
          schoolData['current_term']?.toString() ?? '1st Term';

      // --- ACADEMICS ---
      // 🚨 RESTORED: Now safely queries the new database columns!
      final classAttRes = await _supabase
          .from('attendance')
          .select('date')
          .eq('class_level', sClass)
          .eq('academic_session', currentSession)
          .eq('term', currentTerm);
      final uniqueDates = classAttRes.map((r) => r['date'].toString()).toSet();
      int totalSchoolDays = uniqueDates.length;

      final stuAttRes = await _supabase
          .from('attendance')
          .select('status')
          .eq('student_id', studentId)
          .eq('academic_session', currentSession)
          .eq('term', currentTerm);
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

      // 🚨 FIXED: Filter exam scores precisely by active Session and Term
      final scoresRes = await _supabase
          .from('exam_scores')
          .select('subject_name, total_score, grade')
          .eq('student_id', studentId)
          .eq('academic_session', currentSession)
          .eq('term', currentTerm);

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
      } else {
        _subjectGrades = [];
        _gradeAverage = "N/A";
      }

      // --- FINANCES ---
      final financialSummary = await _financialService.getFinancialSummary(
        schoolId: schoolId,
        studentId: studentId,
        sClass: sClass,
        sCategory: sCategory,
        session: currentSession, // Works perfectly with the service logic
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
          .select(
            'name, address, logo_url, current_session, current_term',
          ) // 🚨 Fetched dynamically
          .eq('id', schoolId)
          .single();

      final String currentSession =
          schoolData['current_session']?.toString() ?? '';
      final String currentTerm =
          schoolData['current_term']?.toString() ?? '1st Term';

      final termResults = await _supabase
          .from('term_results')
          .select()
          .eq('student_id', studentId)
          .order('academic_session', ascending: false);

      final attendanceData = await _supabase
          .from('attendance')
          .select('status')
          .eq('student_id', studentId)
          .eq('academic_session', currentSession)
          .eq('term', currentTerm);

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

  // ===========================================================================
  // 🖼️ UI ONLY — presentation below. Data fetching, the PDF dossier engine and
  // the fee lock rule above/inside are untouched.
  // ===========================================================================
  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color primaryColor = Theme.of(context).primaryColor;
    Color schoolColor = _getSchoolColor(primaryColor);

    String fName = widget.childData['first_name'] ?? '';
    String lName = widget.childData['last_name'] ?? '';
    String initial = fName.isNotEmpty ? fName[0] : '?';
    String passport = widget.childData['passport_url'] ?? '';

    double balance = _totalExpected - _totalPaid;
    if (balance < 0) balance = 0;

    // Pushed on phones (can go back) vs embedded in the desktop split view.
    final bool canGoBack = Navigator.of(context).canPop();

    return Scaffold(
      backgroundColor: PUi.bg(isDark),
      body: PBackdrop(
        accent: schoolColor,
        child: SafeArea(
          bottom: false,
          child: LayoutBuilder(
            builder: (context, c) {
              final bool wide = c.maxWidth >= 760;
              final double hPad = wide ? 32.0 : 20.0;

              return Column(
                children: [
                  if (canGoBack)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 20, 0),
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: () => Navigator.maybePop(context),
                            style: IconButton.styleFrom(
                              backgroundColor: PUi.surface(isDark),
                              side: BorderSide(color: PUi.border(isDark)),
                              minimumSize: const Size(44, 44),
                            ),
                            icon: Icon(
                              Icons.arrow_back_rounded,
                              color: PUi.ink(isDark),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              "$fName's Records",
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 17,
                                color: PUi.ink(isDark),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1000),
                        child: Column(
                          children: [
                            // ─── HERO ───
                            Padding(
                              padding: EdgeInsets.fromLTRB(
                                hPad,
                                canGoBack ? 12 : (wide ? 28 : 16),
                                hPad,
                                0,
                              ),
                              child: _buildHero(
                                fName,
                                lName,
                                initial,
                                passport,
                                schoolColor,
                              ),
                            ),

                            // ─── PILL TABS ───
                            Container(
                              margin: EdgeInsets.fromLTRB(hPad, 18, hPad, 0),
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                color: PUi.surfaceAlt(isDark),
                                borderRadius: BorderRadius.circular(40),
                              ),
                              child: TabBar(
                                controller: _tabController,
                                labelColor: Colors.white,
                                unselectedLabelColor: PUi.muted(isDark),
                                indicatorSize: TabBarIndicatorSize.tab,
                                indicator: BoxDecoration(
                                  color: schoolColor,
                                  borderRadius: BorderRadius.circular(40),
                                ),
                                dividerColor: Colors.transparent,
                                splashBorderRadius: BorderRadius.circular(40),
                                labelStyle: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                ),
                                unselectedLabelStyle: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                                tabs: const [
                                  Tab(height: 42, text: "Academics"),
                                  Tab(height: 42, text: "Finances"),
                                ],
                              ),
                            ),

                            // ─── TAB CONTENT ───
                            Expanded(
                              child: _isLoading
                                  ? Center(
                                      child: TridetaLoader(color: schoolColor),
                                    )
                                  : TabBarView(
                                      controller: _tabController,
                                      children: [
                                        _buildAcademicTab(
                                          isDark,
                                          schoolColor,
                                          balance,
                                          wide,
                                          hPad,
                                        ),
                                        _buildFinanceTab(
                                          isDark,
                                          schoolColor,
                                          balance,
                                          wide,
                                          hPad,
                                        ),
                                      ],
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHero(
    String fName,
    String lName,
    String initial,
    String passport,
    Color schoolColor,
  ) {
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [schoolColor.withValues(alpha: 0.88), schoolColor],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: schoolColor.withValues(alpha: 0.26),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -6,
            bottom: -4,
            width: 150,
            child: IgnorePointer(
              child: AspectRatio(
                aspectRatio: 300 / 190,
                child: CustomPaint(
                  painter: PScenePainter(
                    scene: PScene.hero,
                    line: Colors.white.withValues(alpha: 0.35),
                    tint: Colors.white.withValues(alpha: 0.07),
                    paper: schoolColor,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                PAvatar(
                  initial: initial,
                  imageUrl: passport,
                  radius: 36,
                  ringColor: Colors.white,
                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                  initialColor: Colors.white,
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "$fName $lName",
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.6,
                          height: 1.1,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(30),
                            ),
                            child: Text(
                              widget.childData['class_level'] ?? 'Unassigned',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 11.5,
                              ),
                            ),
                          ),
                          Text(
                            "Session: ${widget.childData['schools']?['current_session'] ?? 'N/A'}",
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
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
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // ACADEMICS
  // ---------------------------------------------------------------------------
  Widget _buildAcademicTab(
    bool isDark,
    Color schoolColor,
    double balance,
    bool wide,
    double hPad,
  ) {
    final stats = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _buildStatCard(
            "Attendance",
            _attendancePercentage,
            Icons.calendar_month_rounded,
            schoolColor,
            isDark,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _buildStatCard(
            "Average",
            _gradeAverage,
            Icons.auto_graph_rounded,
            schoolColor,
            isDark,
          ),
        ),
      ],
    );

    final grades = _buildGradesSection(isDark, schoolColor);
    final dossier = _buildDossierSection(isDark, schoolColor, balance);

    final padding = EdgeInsets.fromLTRB(hPad, 22, hPad, 32);

    if (wide) {
      return SingleChildScrollView(
        padding: padding,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 3, child: grades),
            const SizedBox(width: 24),
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [stats, const SizedBox(height: 24), dossier],
              ),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: padding,
      children: [stats, const SizedBox(height: 26), grades, const SizedBox(height: 26), dossier],
    );
  }

  Widget _buildGradesSection(bool isDark, Color schoolColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("SUBJECT GRADES", style: PUi.sectionLabel(isDark)),
        const SizedBox(height: 12),
        if (_subjectGrades.isEmpty)
          PCard(
            radius: 26,
            padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
            child: SizedBox(
              width: double.infinity,
              child: Center(
                child: Text(
                  "No scores recorded yet.",
                  style: TextStyle(color: PUi.muted(isDark)),
                ),
              ),
            ),
          )
        else
          PCard(
            radius: 26,
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (int index = 0; index < _subjectGrades.length; index++) ...[
                  if (index > 0)
                    Divider(
                      height: 1,
                      color: PUi.border(isDark),
                      indent: 20,
                      endIndent: 20,
                    ),
                  _buildGradeRow(_subjectGrades[index], isDark),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildGradeRow(Map<String, dynamic> gradeData, bool isDark) {
    Color gColor = Colors.grey;
    if (gradeData['grade'] == 'A') gColor = Colors.green;
    if (gradeData['grade'] == 'B') gColor = Colors.blue;
    if (gradeData['grade'] == 'C') gColor = Colors.orange;
    if (gradeData['grade'] == 'P') gColor = Colors.purple;
    if (gradeData['grade'] == 'F') gColor = Colors.red;

    final double scoreValue =
        (double.tryParse(gradeData['score'].toString()) ?? 0)
            .clamp(0, 100)
            .toDouble();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  gradeData['subject'],
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                    color: PUi.ink(isDark),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              PPill(
                text: "${gradeData['score']} (${gradeData['grade']})",
                color: gColor,
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: scoreValue / 100,
              minHeight: 5,
              backgroundColor: PUi.tint(gColor, isDark, 0.1),
              valueColor: AlwaysStoppedAnimation<Color>(gColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDossierSection(bool isDark, Color schoolColor, double balance) {
    bool isLocked = balance > 0;
    final Color accent = isLocked ? Colors.red : schoolColor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("REPORT SHEETS & RECORDS", style: PUi.sectionLabel(isDark)),
        const SizedBox(height: 12),
        PCard(
          radius: 26,
          borderColor: accent.withValues(alpha: 0.4),
          borderWidth: 1.5,
          onTap: isLocked
              ? () {
                  showAuthErrorDialog(
                    "Please clear the outstanding balance of ₦${balance.toStringAsFixed(0)} in the Finances tab to unlock this student's report sheet.",
                  );
                }
              : (_isGeneratingRecord ? null : _generateComprehensiveRecord),
          child: Row(
            children: [
              PIconBadge(
                icon: isLocked
                    ? Icons.lock_outline_rounded
                    : Icons.picture_as_pdf_rounded,
                color: accent,
                size: 50,
                iconSize: 24,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Full Academic Dossier",
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: isLocked ? Colors.red : PUi.ink(isDark),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isLocked
                          ? "Locked due to outstanding fees."
                          : "Download complete historic report sheet.",
                      style: TextStyle(
                        fontSize: 12.5,
                        color: isLocked
                            ? Colors.red.shade300
                            : PUi.muted(isDark),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _isGeneratingRecord
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: TridetaLoader(color: schoolColor),
                    )
                  : Icon(
                      isLocked ? Icons.lock_rounded : Icons.download_rounded,
                      color: accent,
                    ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // FINANCES
  // ---------------------------------------------------------------------------
  Widget _buildFinanceTab(
    bool isDark,
    Color schoolColor,
    double balance,
    bool wide,
    double hPad,
  ) {
    final formatCurrency = NumberFormat.currency(symbol: '₦');
    final bool owing = balance > 0;
    final Color statusColor = owing ? Colors.red : Colors.green;

    final Widget notice = !_isFinanceActivated
        ? Container(
            margin: const EdgeInsets.only(bottom: 20),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  color: Colors.orange,
                  size: 28,
                ),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Financial Engine Not Activated",
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Colors.orange,
                          fontSize: 14,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        "The school administration has not yet published the fee structures.",
                        style: TextStyle(fontSize: 12.5, color: Colors.orange),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          )
        : const SizedBox.shrink();

    final Widget outstanding = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: PUi.tint(statusColor, isDark, 0.07),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: statusColor.withValues(alpha: 0.35),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PIconBadge(
                icon: owing
                    ? Icons.account_balance_wallet_rounded
                    : Icons.verified_rounded,
                color: statusColor,
                size: 44,
                iconSize: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  "CURRENT OUTSTANDING",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: statusColor,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              formatCurrency.format(balance),
              style: TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.w800,
                color: statusColor,
                letterSpacing: -1,
              ),
            ),
          ),
        ],
      ),
    );

    final Widget history = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("PAYMENT HISTORY", style: PUi.sectionLabel(isDark)),
        const SizedBox(height: 12),
        if (_receipts.isEmpty)
          PCard(
            radius: 26,
            padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
            child: SizedBox(
              width: double.infinity,
              child: Center(
                child: Text(
                  "No payments made yet.",
                  style: TextStyle(color: PUi.muted(isDark)),
                ),
              ),
            ),
          )
        else
          PCard(
            radius: 26,
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (int index = 0; index < _receipts.length; index++) ...[
                  if (index > 0)
                    Divider(
                      height: 1,
                      color: PUi.border(isDark),
                      indent: 20,
                      endIndent: 20,
                    ),
                  _buildReceiptRow(_receipts[index], isDark, formatCurrency),
                ],
              ],
            ),
          ),
      ],
    );

    final padding = EdgeInsets.fromLTRB(hPad, 22, hPad, 32);

    if (wide) {
      return SingleChildScrollView(
        padding: padding,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [notice, outstanding],
              ),
            ),
            const SizedBox(width: 24),
            Expanded(flex: 3, child: history),
          ],
        ),
      );
    }

    return ListView(
      padding: padding,
      children: [notice, outstanding, const SizedBox(height: 26), history],
    );
  }

  Widget _buildReceiptRow(
    Map<String, dynamic> tx,
    bool isDark,
    NumberFormat formatCurrency,
  ) {
    return InkWell(
      borderRadius: BorderRadius.circular(26),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ReceiptDetailView(tx: tx)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            const PIconBadge(
              icon: Icons.receipt_long_rounded,
              color: Colors.green,
              size: 44,
              iconSize: 20,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tx['category'] ?? 'Fee Payment',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14.5,
                      color: PUi.ink(isDark),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    DateFormat(
                      'MMM d, yyyy',
                    ).format(DateTime.parse(tx['created_at'])),
                    style: TextStyle(fontSize: 12, color: PUi.muted(isDark)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              formatCurrency.format(tx['amount']),
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: Colors.green,
                fontSize: 15,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, color: PUi.muted(isDark)),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    String val,
    IconData icon,
    Color color,
    bool isDark,
  ) {
    // "92.5% (37/40 Days)" is shown as a big value with a small caption.
    String main = val;
    String? sub;
    final int cut = val.indexOf(' (');
    if (cut > 0 && val.endsWith(')')) {
      main = val.substring(0, cut);
      sub = val.substring(cut + 2, val.length - 1);
    }

    return PCard(
      radius: 26,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PIconBadge(icon: icon, color: color, size: 42, iconSize: 20),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              fontSize: 12.5,
              color: PUi.muted(isDark),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              main,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
                color: PUi.ink(isDark),
              ),
            ),
          ),
          if (sub != null) ...[
            const SizedBox(height: 2),
            Text(
              sub,
              style: TextStyle(fontSize: 12, color: PUi.muted(isDark)),
            ),
          ],
        ],
      ),
    );
  }
}
