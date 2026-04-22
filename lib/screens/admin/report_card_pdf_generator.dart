import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class ReportCardPDFGenerator extends StatefulWidget {
  final String studentId;
  final String schoolId;
  final String session;
  final String term;
  final String className;
  final String studentName;
  final String admissionNo;
  final Uint8List? precompiledPdfBytes;

  const ReportCardPDFGenerator({
    super.key,
    required this.studentId,
    required this.schoolId,
    required this.session,
    required this.term,
    required this.className,
    required this.studentName,
    required this.admissionNo,
    this.precompiledPdfBytes,
  });

  @override
  State<ReportCardPDFGenerator> createState() => _ReportCardPDFGeneratorState();

  static Future<Uint8List> generatePdfBytes({
    required SupabaseClient supabase,
    required String studentId,
    required String schoolId,
    required String session,
    required String term,
    required String className,
    required String studentName,
    required String admissionNo,
    required PdfPageFormat format,
  }) async {
    // 1. Fetch all required data
    final schoolData = await supabase
        .from('schools')
        .select('name, address, contact_phone, logo_url, brand_color')
        .eq('id', schoolId)
        .single();

    final resultData = await supabase
        .from('term_results')
        .select()
        .eq('student_id', studentId)
        .eq('academic_session', session)
        .eq('term', term)
        .maybeSingle();

    final scoresData = await supabase
        .from('exam_scores')
        .select()
        .eq('student_id', studentId)
        .eq('academic_session', session)
        .eq('term', term)
        .order('subject_name', ascending: true);

    final affectiveData = await supabase
        .from('affective_traits')
        .select()
        .eq('student_id', studentId)
        .eq('academic_session', session)
        .eq('term', term)
        .maybeSingle();

    final studentData = await supabase
        .from('students')
        .select('id, passport_url')
        .eq('id', studentId)
        .single();

    final classCountRes = await supabase
        .from('students')
        .select('id')
        .eq('school_id', schoolId)
        .eq('class_level', className);
    final int classTotal = classCountRes.length;

    // 2. Determine head title (Headmaster vs Principal)
    String clsLower = className.toLowerCase();
    String headTitle = "Principal";

    bool isSecondary =
        clsLower.contains('jss') ||
        clsLower.contains('sss') ||
        clsLower.contains('senior') ||
        clsLower.contains('junior') ||
        clsLower.contains('sec');

    if (clsLower.contains('primary') ||
        clsLower.contains('nursery') ||
        clsLower.contains('pre') ||
        clsLower.contains('creche') ||
        clsLower.contains('kg') ||
        clsLower.contains('kinder')) {
      headTitle = "Headmaster";
    } else if (isSecondary) {
      headTitle = "Principal";
    } else if (clsLower.contains('basic')) {
      if (clsLower.contains('7') ||
          clsLower.contains('8') ||
          clsLower.contains('9')) {
        headTitle = "Principal";
      } else {
        headTitle = "Headmaster";
      }
    }

    // 3. Parse brand color or use default
    PdfColor primaryColor = PdfColors.blue900;
    PdfColor accentColor = PdfColors.blue800;
    PdfColor lightAccent = PdfColors.blue100;

    if (schoolData['brand_color'] != null) {
      try {
        String brandColorHex = schoolData['brand_color'].toString().replaceAll(
          '#',
          '',
        );
        if (brandColorHex.length == 6) {
          int colorValue = int.parse(brandColorHex, radix: 16);
          int r = (colorValue >> 16) & 0xFF;
          int g = (colorValue >> 8) & 0xFF;
          int b = colorValue & 0xFF;

          primaryColor = PdfColor(r / 255, g / 255, b / 255);
          accentColor = PdfColor(
            (r * 0.85) / 255,
            (g * 0.85) / 255,
            (b * 0.85) / 255,
          );
          lightAccent = PdfColor(
            (r + (255 - r) * 0.9) / 255,
            (g + (255 - g) * 0.9) / 255,
            (b + (255 - b) * 0.9) / 255,
          );
        }
      } catch (e) {}
    }

    // 4. Load Dual Fonts
    final englishFont = await PdfGoogleFonts.openSansRegular();
    final englishFontBold = await PdfGoogleFonts.openSansBold();
    final arabicFont = await PdfGoogleFonts.notoSansArabicRegular();
    final arabicFontBold = await PdfGoogleFonts.notoSansArabicBold();

    final pdfTheme = pw.ThemeData.withFont(
      base: englishFont,
      bold: englishFontBold,
      fontFallback: [arabicFont],
    );

    // 5. Smart Arabic Detector & Explicit Font Shaper
    bool containsArabic(String text) {
      return RegExp(
        r'[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF]',
      ).hasMatch(text);
    }

    pw.Widget smartText(
      String text,
      pw.TextStyle style, {
      pw.TextAlign? align,
    }) {
      bool isRtl = containsArabic(text);

      pw.TextStyle finalStyle = style;
      if (isRtl) {
        bool isBold = style.fontWeight == pw.FontWeight.bold;
        finalStyle = style.copyWith(
          font: isBold ? arabicFontBold : arabicFont,
          fontFallback: [englishFont],
        );
      }

      return pw.Text(
        text,
        style: finalStyle,
        textAlign: align ?? (isRtl ? pw.TextAlign.right : pw.TextAlign.left),
        textDirection: isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr,
      );
    }

    // 6. Load Images
    pw.ImageProvider? logoProvider;
    if (schoolData['logo_url'] != null) {
      try {
        logoProvider = await networkImage(schoolData['logo_url']);
      } catch (e) {}
    }

    pw.ImageProvider? studentPhotoProvider;
    if (studentData['passport_url'] != null &&
        studentData['passport_url'].toString().isNotEmpty) {
      try {
        studentPhotoProvider = await networkImage(studentData['passport_url']);
      } catch (e) {}
    }

    // 7. UI Builders
    pw.Widget buildHeader() {
      return pw.Column(
        children: [
          pw.Container(
            width: double.infinity,
            height: 3,
            decoration: pw.BoxDecoration(
              gradient: pw.LinearGradient(
                colors: [primaryColor, accentColor, primaryColor],
              ),
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Container(width: 80),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    if (logoProvider != null)
                      pw.Container(
                        width: 50,
                        height: 50,
                        margin: const pw.EdgeInsets.only(bottom: 6),
                        child: pw.Image(logoProvider, fit: pw.BoxFit.contain),
                      ),

                    smartText(
                      (schoolData['name'] ?? 'OUR SCHOOL').toUpperCase(),
                      pw.TextStyle(
                        fontSize: 22,
                        fontWeight: pw.FontWeight.bold,
                        color: primaryColor,
                        letterSpacing: 1.2,
                      ),
                      align: pw.TextAlign.center,
                    ),

                    pw.SizedBox(height: 4),

                    if (schoolData['address'] != null)
                      smartText(
                        schoolData['address'],
                        pw.TextStyle(fontSize: 9, color: PdfColors.grey800),
                        align: pw.TextAlign.center,
                      ),

                    if (schoolData['contact_phone'] != null)
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(top: 2),
                        child: pw.Text(
                          "☎ ${schoolData['contact_phone']}",
                          style: const pw.TextStyle(
                            fontSize: 9,
                            color: PdfColors.grey700,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              pw.Container(width: 80),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 20),
            decoration: pw.BoxDecoration(
              gradient: pw.LinearGradient(colors: [primaryColor, accentColor]),
              borderRadius: pw.BorderRadius.circular(6),
              boxShadow: const [
                pw.BoxShadow(
                  color: PdfColors.grey300,
                  offset: PdfPoint(0, 2),
                  blurRadius: 4,
                ),
              ],
            ),
            child: pw.Text(
              "OFFICIAL TERMINAL REPORT CARD",
              style: pw.TextStyle(
                color: PdfColors.white,
                fontWeight: pw.FontWeight.bold,
                fontSize: 13,
                letterSpacing: 1.5,
              ),
              textAlign: pw.TextAlign.center,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Container(width: double.infinity, height: 2, color: lightAccent),
        ],
      );
    }

    pw.Widget buildInfoBanner() {
      String positionStr =
          resultData != null &&
              resultData['position'] != null &&
              resultData['position'] > 0
          ? "${resultData['position']}${resultData['position_suffix']} out of $classTotal"
          : "N/A";
      String averageStr =
          resultData != null && resultData['average_score'] != null
          ? "${(resultData['average_score'] as num).toStringAsFixed(1)}%"
          : "N/A";

      return pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          color: lightAccent,
          border: pw.Border.all(color: primaryColor, width: 1.5),
          borderRadius: pw.BorderRadius.circular(8),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                if (studentPhotoProvider != null)
                  pw.Container(
                    width: 50,
                    height: 50,
                    margin: const pw.EdgeInsets.only(right: 12),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: primaryColor, width: 2),
                      borderRadius: pw.BorderRadius.circular(6),
                      image: pw.DecorationImage(
                        image: studentPhotoProvider,
                        fit: pw.BoxFit.cover,
                      ),
                    ),
                  ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(
                      children: [
                        pw.Text(
                          "Name: ",
                          style: const pw.TextStyle(
                            fontSize: 10,
                            color: PdfColors.grey700,
                          ),
                        ),
                        smartText(
                          studentName,
                          pw.TextStyle(
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                            color: primaryColor,
                          ),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 3),
                    pw.Row(
                      children: [
                        pw.Text(
                          "Admission No: ",
                          style: const pw.TextStyle(
                            fontSize: 9,
                            color: PdfColors.grey700,
                          ),
                        ),
                        pw.Text(
                          admissionNo,
                          style: pw.TextStyle(
                            fontSize: 9,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 3),
                    pw.Row(
                      children: [
                        pw.Text(
                          "Class: ",
                          style: const pw.TextStyle(
                            fontSize: 9,
                            color: PdfColors.grey700,
                          ),
                        ),
                        smartText(
                          className,
                          pw.TextStyle(
                            fontSize: 9,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Row(
                  children: [
                    pw.Text(
                      "Session: ",
                      style: const pw.TextStyle(
                        fontSize: 9,
                        color: PdfColors.grey700,
                      ),
                    ),
                    pw.Text(
                      session,
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 3),
                pw.Row(
                  children: [
                    pw.Text(
                      "Term: ",
                      style: const pw.TextStyle(
                        fontSize: 9,
                        color: PdfColors.grey700,
                      ),
                    ),
                    pw.Text(
                      term,
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 3),
                pw.Row(
                  children: [
                    pw.Text(
                      "Position: ",
                      style: const pw.TextStyle(
                        fontSize: 9,
                        color: PdfColors.grey700,
                      ),
                    ),
                    pw.Text(
                      positionStr,
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                        color: primaryColor,
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 3),
                pw.Row(
                  children: [
                    pw.Text(
                      "Average: ",
                      style: const pw.TextStyle(
                        fontSize: 9,
                        color: PdfColors.grey700,
                      ),
                    ),
                    pw.Text(
                      averageStr,
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                        color: primaryColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      );
    }

    pw.Widget buildCognitiveTable() {
      List<pw.TableRow> rows = [];

      rows.add(
        pw.TableRow(
          decoration: pw.BoxDecoration(
            gradient: pw.LinearGradient(colors: [primaryColor, accentColor]),
          ),
          children: [
            // Reduced vertical padding to compress table
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(
                vertical: 4,
                horizontal: 8,
              ),
              child: pw.Text(
                "SUBJECT",
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(
                vertical: 4,
                horizontal: 8,
              ),
              child: pw.Text(
                "CA",
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
                textAlign: pw.TextAlign.center,
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(
                vertical: 4,
                horizontal: 8,
              ),
              child: pw.Text(
                "EXAM",
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
                textAlign: pw.TextAlign.center,
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(
                vertical: 4,
                horizontal: 8,
              ),
              child: pw.Text(
                "TOTAL",
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
                textAlign: pw.TextAlign.center,
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(
                vertical: 4,
                horizontal: 8,
              ),
              child: pw.Text(
                "GRADE",
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
                textAlign: pw.TextAlign.center,
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(
                vertical: 4,
                horizontal: 8,
              ),
              child: pw.Text(
                "REMARK",
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
                textAlign: pw.TextAlign.center,
              ),
            ),
          ],
        ),
      );

      for (int i = 0; i < scoresData.length; i++) {
        final score = scoresData[i];
        bool isEven = i % 2 == 0;

        num att = score['ca_attendance'] ?? 0;
        num ass = score['ca_assignment'] ?? 0;
        num mid = score['ca_midterm'] ?? 0;
        num caTotal = att + ass + mid;

        bool hasCa =
            score['ca_attendance'] != null ||
            score['ca_assignment'] != null ||
            score['ca_midterm'] != null;
        String caDisplay = hasCa
            ? (caTotal % 1 == 0
                  ? caTotal.toInt().toString()
                  : caTotal.toStringAsFixed(1))
            : '-';

        num examVal = score['exam_score'] ?? 0;
        String examDisplay = score['exam_score'] != null
            ? (examVal % 1 == 0
                  ? examVal.toInt().toString()
                  : examVal.toStringAsFixed(1))
            : '-';

        num totalVal = score['total_score'] ?? 0;
        String totalDisplay = score['total_score'] != null
            ? (totalVal % 1 == 0
                  ? totalVal.toInt().toString()
                  : totalVal.toStringAsFixed(1))
            : '-';

        rows.add(
          pw.TableRow(
            decoration: pw.BoxDecoration(
              color: isEven ? PdfColors.white : lightAccent,
            ),
            children: [
              // Reduced vertical padding to compress rows for 18 subjects
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(
                  vertical: 4,
                  horizontal: 8,
                ),
                child: smartText(
                  score['subject_name'] ?? '',
                  const pw.TextStyle(fontSize: 9),
                ),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(
                  vertical: 4,
                  horizontal: 8,
                ),
                child: pw.Text(
                  caDisplay,
                  style: const pw.TextStyle(fontSize: 9),
                  textAlign: pw.TextAlign.center,
                ),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(
                  vertical: 4,
                  horizontal: 8,
                ),
                child: pw.Text(
                  examDisplay,
                  style: const pw.TextStyle(fontSize: 9),
                  textAlign: pw.TextAlign.center,
                ),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(
                  vertical: 4,
                  horizontal: 8,
                ),
                child: pw.Text(
                  totalDisplay,
                  style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                    color: primaryColor,
                  ),
                  textAlign: pw.TextAlign.center,
                ),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(
                  vertical: 4,
                  horizontal: 8,
                ),
                child: pw.Text(
                  score['grade'] ?? '-',
                  style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                  ),
                  textAlign: pw.TextAlign.center,
                ),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(
                  vertical: 4,
                  horizontal: 8,
                ),
                child: pw.Text(
                  score['remark'] ?? '-',
                  style: pw.TextStyle(
                    fontSize: 8,
                    fontStyle: pw.FontStyle.italic,
                  ),
                  textAlign: pw.TextAlign.center,
                ),
              ),
            ],
          ),
        );
      }

      return pw.Container(
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: primaryColor, width: 1.5),
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.ClipRRect(
          horizontalRadius: 6,
          verticalRadius: 6,
          child: pw.Table(
            border: const pw.TableBorder(
              horizontalInside: pw.BorderSide(
                color: PdfColors.grey300,
                width: 0.5,
              ),
              verticalInside: pw.BorderSide(
                color: PdfColors.grey300,
                width: 0.5,
              ),
            ),
            columnWidths: const {
              0: pw.FlexColumnWidth(3),
              1: pw.FlexColumnWidth(1),
              2: pw.FlexColumnWidth(1),
              3: pw.FlexColumnWidth(1),
              4: pw.FlexColumnWidth(1),
              5: pw.FlexColumnWidth(2),
            },
            children: rows,
          ),
        ),
      );
    }

    pw.Widget buildAffectiveArea() {
      pw.Widget traitRow(String trait, String score) {
        return pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 4),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(trait, style: const pw.TextStyle(fontSize: 9)),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 1,
                ),
                decoration: pw.BoxDecoration(
                  color: lightAccent,
                  borderRadius: pw.BorderRadius.circular(4),
                  border: pw.Border.all(color: primaryColor, width: 0.5),
                ),
                child: pw.Text(
                  score,
                  style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                    color: primaryColor,
                  ),
                ),
              ),
            ],
          ),
        );
      }

      pw.Widget remarkBox(String title, String remark) {
        return pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            color: PdfColors.grey50,
            border: pw.Border.all(color: primaryColor, width: 1),
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                title,
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: primaryColor,
                ),
              ),
              pw.SizedBox(height: 4),
              smartText(
                remark,
                pw.TextStyle(
                  fontSize: 9,
                  fontStyle: pw.FontStyle.italic,
                  color: PdfColors.grey800,
                ),
              ),
            ],
          ),
        );
      }

      return pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            flex: 2,
            child: pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: PdfColors.white,
                border: pw.Border.all(color: primaryColor, width: 1.5),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      vertical: 3,
                      horizontal: 6,
                    ),
                    decoration: pw.BoxDecoration(
                      color: lightAccent,
                      borderRadius: pw.BorderRadius.circular(4),
                    ),
                    child: pw.Text(
                      "AFFECTIVE DOMAIN (1-5)",
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                        color: primaryColor,
                      ),
                    ),
                  ),
                  pw.SizedBox(height: 8),
                  traitRow(
                    "Punctuality",
                    affectiveData?['punctuality']?.toString() ?? '-',
                  ),
                  traitRow(
                    "Neatness",
                    affectiveData?['neatness']?.toString() ?? '-',
                  ),
                  traitRow(
                    "Honesty",
                    affectiveData?['honesty']?.toString() ?? '-',
                  ),
                  traitRow(
                    "Peer Relationship",
                    affectiveData?['peer_relationship']?.toString() ?? '-',
                  ),
                  traitRow(
                    "Manual Dexterity",
                    affectiveData?['manual_dexterity']?.toString() ?? '-',
                  ),
                ],
              ),
            ),
          ),
          pw.SizedBox(width: 15),
          pw.Expanded(
            flex: 3,
            child: pw.Column(
              children: [
                remarkBox(
                  "Form Master's Remark:",
                  affectiveData?['class_teacher_remark'] ?? "Awaiting Remark.",
                ),
                pw.SizedBox(height: 8),
                remarkBox(
                  "$headTitle's Remark:",
                  resultData?['principal_remark'] ?? "Awaiting Remark.",
                ),
              ],
            ),
          ),
        ],
      );
    }

    pw.Widget buildSignatures() {
      return pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 12, horizontal: 20),
        decoration: pw.BoxDecoration(
          color: lightAccent,
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Container(
                  width: 160,
                  height: 35,
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(
                      bottom: pw.BorderSide(
                        color: PdfColors.grey700,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  "Class Teacher's Signature",
                  style: pw.TextStyle(
                    fontSize: 8,
                    color: PdfColors.grey700,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  "Date: _______________",
                  style: const pw.TextStyle(
                    fontSize: 7,
                    color: PdfColors.grey600,
                  ),
                ),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Container(
                  width: 160,
                  height: 35,
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(
                      bottom: pw.BorderSide(
                        color: PdfColors.grey700,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  "$headTitle's Signature",
                  style: pw.TextStyle(
                    fontSize: 8,
                    color: PdfColors.grey700,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  "Date: _______________",
                  style: const pw.TextStyle(
                    fontSize: 7,
                    color: PdfColors.grey600,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    // 8. Generate MultiPage PDF Document
    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: format,
        theme: pdfTheme,
        // Reduced page margins to allow more vertical space for 18 subjects
        margin: const pw.EdgeInsets.symmetric(vertical: 24, horizontal: 30),
        build: (pw.Context context) {
          return [
            buildHeader(),
            pw.SizedBox(height: 10),
            buildInfoBanner(),
            pw.SizedBox(height: 10),
            buildCognitiveTable(),
            pw.SizedBox(height: 10),
            buildAffectiveArea(),
            pw.SizedBox(height: 15),
            buildSignatures(),
            pw.SizedBox(height: 10),
            pw.Center(
              child: pw.Text(
                "This is an official document generated by the school management system",
                style: pw.TextStyle(
                  fontSize: 7,
                  color: PdfColors.grey500,
                  fontStyle: pw.FontStyle.italic,
                ),
              ),
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }
}

class _ReportCardPDFGeneratorState extends State<ReportCardPDFGenerator> {
  final _supabase = Supabase.instance.client;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          "${widget.studentName}'s Report",
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: PdfPreview(
        build: (format) async {
          if (widget.precompiledPdfBytes != null) {
            return widget.precompiledPdfBytes!;
          }
          return ReportCardPDFGenerator.generatePdfBytes(
            supabase: _supabase,
            studentId: widget.studentId,
            schoolId: widget.schoolId,
            session: widget.session,
            term: widget.term,
            className: widget.className,
            studentName: widget.studentName,
            admissionNo: widget.admissionNo,
            format: format,
          );
        },
        allowPrinting: true,
        allowSharing: true,
        canChangeOrientation: false,
        canChangePageFormat: false,
        initialPageFormat: PdfPageFormat.a4,
        pdfFileName:
            "${widget.studentName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}_Report_Card_${widget.term.replaceAll(' ', '')}.pdf",
      ),
    );
  }
}
