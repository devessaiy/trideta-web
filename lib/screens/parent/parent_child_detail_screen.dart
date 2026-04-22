import 'package:trideta_v2/utils/auth_error_handler.dart';
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

  // 🚨 NEW: Engine Activation Tracker
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

      // 🚨 NEW: Check if the school has ANY fees registered
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
          _isFinanceActivated = feeCheck.isNotEmpty; // Updates the tracker!
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

    String fName = widget.childData['first_name'] ?? '';

    double balance = _totalExpected - _totalPaid;
    if (balance < 0) balance = 0;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(
          "$fName's Records",
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(30),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 10,
                ),
              ],
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 45,
                  backgroundColor: primaryColor.withOpacity(0.1),
                  backgroundImage:
                      widget.childData['passport_url'] != null &&
                          widget.childData['passport_url'].toString().isNotEmpty
                      ? NetworkImage(widget.childData['passport_url'])
                      : null,
                  child:
                      widget.childData['passport_url'] == null ||
                          widget.childData['passport_url'].toString().isEmpty
                      ? Icon(
                          Icons.person_rounded,
                          size: 40,
                          color: primaryColor,
                        )
                      : null,
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "${widget.childData['first_name']} ${widget.childData['last_name']}",
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: primaryColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          widget.childData['class_level'] ?? 'Unassigned',
                          style: TextStyle(
                            color: primaryColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Session: ${widget.childData['schools']['current_session'] ?? 'N/A'}",
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Container(
            color: cardColor,
            child: TabBar(
              controller: _tabController,
              labelColor: primaryColor,
              unselectedLabelColor: Colors.grey,
              indicatorColor: primaryColor,
              indicatorWeight: 3,
              tabs: const [
                Tab(text: "ACADEMICS"),
                Tab(text: "FINANCES"),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator(color: primaryColor))
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildAcademicTab(isDark, primaryColor, balance),
                      _buildFinanceTab(
                        isDark,
                        primaryColor,
                        cardColor,
                        balance,
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildAcademicTab(bool isDark, Color primaryColor, double balance) {
    bool isLocked = balance > 0;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                "Attendance",
                _attendancePercentage,
                Icons.calendar_month,
                Colors.blue,
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: _buildStatCard(
                "Average",
                _gradeAverage,
                Icons.auto_graph_rounded,
                Colors.purple,
              ),
            ),
          ],
        ),
        const SizedBox(height: 25),
        const Text(
          "SUBJECT GRADES",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12,
            color: Colors.grey,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 10),

        if (_subjectGrades.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 20),
            child: Center(
              child: Text(
                "No scores recorded yet.",
                style: TextStyle(color: Colors.grey),
              ),
            ),
          )
        else
          ..._subjectGrades.map((gradeData) {
            Color gColor = Colors.grey;
            if (gradeData['grade'] == 'A') gColor = Colors.green;
            if (gradeData['grade'] == 'B') gColor = Colors.blue;
            if (gradeData['grade'] == 'C') gColor = Colors.orange;
            if (gradeData['grade'] == 'P') gColor = Colors.purple;
            if (gradeData['grade'] == 'F') gColor = Colors.red;

            return ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                gradeData['subject'],
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              trailing: Text(
                "${gradeData['score']} (${gradeData['grade']})",
                style: TextStyle(fontWeight: FontWeight.bold, color: gColor),
              ),
            );
          }),

        const SizedBox(height: 30),

        const Text(
          "REPORT SHEETS & RECORDS",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12,
            color: Colors.grey,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        Card(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
            side: BorderSide(
              color: isLocked
                  ? Colors.red.withOpacity(0.3)
                  : primaryColor.withOpacity(0.3),
            ),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.all(15),
            leading: CircleAvatar(
              backgroundColor: isLocked
                  ? Colors.red.withOpacity(0.1)
                  : primaryColor.withOpacity(0.1),
              child: Icon(
                isLocked
                    ? Icons.lock_outline_rounded
                    : Icons.picture_as_pdf_rounded,
                color: isLocked ? Colors.red : primaryColor,
              ),
            ),
            title: Text(
              "Full Academic Dossier",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: isLocked
                    ? Colors.red
                    : (isDark ? Colors.white : Colors.black87),
              ),
            ),
            subtitle: Text(
              isLocked
                  ? "Locked due to outstanding fees."
                  : "Download complete historic report sheet.",
              style: TextStyle(
                fontSize: 11,
                color: isLocked
                    ? Colors.red[300]
                    : (isDark ? Colors.white54 : Colors.grey[600]),
              ),
            ),
            trailing: _isGeneratingRecord
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    isLocked ? Icons.lock_rounded : Icons.download_rounded,
                    color: isLocked ? Colors.red : primaryColor,
                  ),
            onTap: isLocked
                ? () {
                    showAuthErrorDialog(
                      "Please clear the outstanding balance of ₦${balance.toStringAsFixed(0)} in the Finances tab to unlock this student's report sheet.",
                    );
                  }
                : (_isGeneratingRecord ? null : _generateComprehensiveRecord),
          ),
        ),
      ],
    );
  }

  Widget _buildFinanceTab(
    bool isDark,
    Color primaryColor,
    Color cardColor,
    double balance,
  ) {
    final formatCurrency = NumberFormat.currency(symbol: '₦');

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // 🚨 NEW: FINANCIAL ENGINE WARNING BANNER
        if (!_isFinanceActivated)
          Container(
            margin: const EdgeInsets.only(bottom: 20),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Colors.orange.withOpacity(0.3)),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  color: Colors.orange,
                  size: 28,
                ),
                SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                        "The school administration has not yet published the fee structures. Please check back later.",
                        style: TextStyle(fontSize: 12, color: Colors.orange),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: balance > 0
                ? Colors.red.withOpacity(0.1)
                : Colors.green.withOpacity(0.1),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: balance > 0
                  ? Colors.red.withOpacity(0.3)
                  : Colors.green.withOpacity(0.3),
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
                ),
              ),
              const SizedBox(height: 5),
              Text(
                formatCurrency.format(balance),
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  color: balance > 0 ? Colors.red : Colors.green,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 25),
        const Text(
          "PAYMENT HISTORY",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12,
            color: Colors.grey,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 10),

        if (_receipts.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 20),
            child: Center(
              child: Text(
                "No payments made yet.",
                style: TextStyle(color: Colors.grey),
              ),
            ),
          )
        else
          ..._receipts.map((tx) {
            return Card(
              color: cardColor,
              margin: const EdgeInsets.only(bottom: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: isDark ? Colors.white10 : Colors.grey.shade200,
                ),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ReceiptDetailView(tx: tx),
                    ),
                  );
                },
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.green.withOpacity(0.1),
                    child: const Icon(
                      Icons.receipt_long,
                      color: Colors.green,
                      size: 20,
                    ),
                  ),
                  title: Text(
                    tx['category'] ?? 'Fee Payment',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  subtitle: Text(
                    "Tap to view receipt • ${DateFormat('dd MMM yyyy').format(DateTime.parse(tx['created_at']))}",
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: Text(
                    formatCurrency.format(tx['amount']),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildStatCard(String title, String val, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.grey,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 5),
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
