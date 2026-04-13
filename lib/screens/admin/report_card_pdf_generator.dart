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
    final schoolData = await supabase
        .from('schools')
        .select('name, address, contact_phone, logo_url')
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

    // 🚨 SMARTER HEADMASTER VS PRINCIPAL LOGIC 🚨
    String clsLower = className.toLowerCase();
    String headTitle = "Principal"; // Default

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
      // Basic 1-6 = Primary (Headmaster), Basic 7-9 = JSS (Principal)
      if (clsLower.contains('7') ||
          clsLower.contains('8') ||
          clsLower.contains('9')) {
        headTitle = "Principal";
      } else {
        headTitle = "Headmaster";
      }
    }

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

    pw.Widget buildHeader() {
      return pw.Column(
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              if (logoProvider != null)
                pw.Container(
                  width: 70,
                  height: 70,
                  child: pw.Image(logoProvider, fit: pw.BoxFit.contain),
                )
              else
                pw.SizedBox(width: 70, height: 70),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Text(
                      (schoolData['name'] ?? 'OUR SCHOOL').toUpperCase(),
                      style: pw.TextStyle(
                        fontSize: 22,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.blue900,
                      ),
                      textAlign: pw.TextAlign.center,
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      schoolData['address'] ?? 'School Address',
                      style: const pw.TextStyle(
                        fontSize: 10,
                        color: PdfColors.grey700,
                      ),
                    ),
                    pw.Text(
                      schoolData['contact_phone'] ?? '',
                      style: const pw.TextStyle(
                        fontSize: 10,
                        color: PdfColors.grey700,
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(width: 70),
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
              "OFFICIAL TERMINAL REPORT CARD",
              style: pw.TextStyle(
                color: PdfColors.white,
                fontWeight: pw.FontWeight.bold,
                fontSize: 14,
              ),
              textAlign: pw.TextAlign.center,
            ),
          ),
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
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey400),
          borderRadius: pw.BorderRadius.circular(8),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Row(
              children: [
                if (studentPhotoProvider != null)
                  pw.Container(
                    width: 50,
                    height: 50,
                    margin: const pw.EdgeInsets.only(right: 12),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey400),
                      borderRadius: pw.BorderRadius.circular(4),
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
                          style: pw.TextStyle(
                            color: PdfColors.grey600,
                            fontSize: 11,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.Text(
                          studentName.toUpperCase(),
                          style: pw.TextStyle(
                            fontSize: 11,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 5),
                    pw.Row(
                      children: [
                        pw.Text(
                          "Admission No: ",
                          style: pw.TextStyle(
                            color: PdfColors.grey600,
                            fontSize: 11,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.Text(
                          admissionNo,
                          style: pw.TextStyle(
                            fontSize: 11,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 5),
                    pw.Row(
                      children: [
                        pw.Text(
                          "Class: ",
                          style: pw.TextStyle(
                            color: PdfColors.grey600,
                            fontSize: 11,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.Text(
                          className,
                          style: pw.TextStyle(
                            fontSize: 11,
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
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  children: [
                    pw.Text(
                      "Session: ",
                      style: pw.TextStyle(
                        color: PdfColors.grey600,
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      session,
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 5),
                pw.Row(
                  children: [
                    pw.Text(
                      "Term: ",
                      style: pw.TextStyle(
                        color: PdfColors.grey600,
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      term,
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  "CLASS POSITION",
                  style: pw.TextStyle(
                    fontSize: 9,
                    color: PdfColors.grey600,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  positionStr,
                  style: pw.TextStyle(
                    fontSize: 16,
                    color: PdfColors.red800,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 5),
                pw.Text(
                  "TERM AVERAGE",
                  style: pw.TextStyle(
                    fontSize: 9,
                    color: PdfColors.grey600,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  averageStr,
                  style: pw.TextStyle(
                    fontSize: 14,
                    color: PdfColors.blue800,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    pw.Widget buildCognitiveTable() {
      final headers = [
        'SUBJECTS',
        'ATT\n(5)',
        'ASS\n(10)',
        'MID\n(25)',
        'CA\n(40)',
        'EXAM\n(60)',
        'TOTAL\n(100)',
        'GRD',
        'REMARK',
      ];
      final tableData = scoresData.map((s) {
        num att = s['ca_attendance'] as num? ?? 0;
        num ass = s['ca_assignment'] as num? ?? 0;
        num mid = s['ca_midterm'] as num? ?? 0;
        num caTotal = att + ass + mid;
        num exam = s['exam_score'] as num? ?? 0;
        num total = s['total_score'] as num? ?? 0;
        return [
          s['subject_name'] ?? '',
          s['ca_attendance'] != null ? att.toInt().toString() : '-',
          s['ca_assignment'] != null ? ass.toInt().toString() : '-',
          s['ca_midterm'] != null ? mid.toInt().toString() : '-',
          caTotal.toInt().toString(),
          s['exam_score'] != null ? exam.toInt().toString() : '-',
          s['total_score'] != null ? total.toInt().toString() : '-',
          s['grade'] ?? '-',
          s['remark'] ?? '-',
        ];
      }).toList();

      return pw.TableHelper.fromTextArray(
        headers: headers,
        data: tableData,
        headerStyle: pw.TextStyle(
          color: PdfColors.white,
          fontWeight: pw.FontWeight.bold,
          fontSize: 9,
        ),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.blue800),
        cellStyle: const pw.TextStyle(fontSize: 10),
        cellAlignment: pw.Alignment.center,
        cellAlignments: {0: pw.Alignment.centerLeft},
        border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
        rowDecoration: const pw.BoxDecoration(
          border: pw.Border(
            bottom: pw.BorderSide(color: PdfColors.grey200, width: 0.5),
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
              pw.Text(trait, style: const pw.TextStyle(fontSize: 10)),
              pw.Text(
                score,
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
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
            border: pw.Border.all(color: PdfColors.grey400),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                title,
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.blue800,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                remark,
                style: pw.TextStyle(
                  fontSize: 10,
                  fontStyle: pw.FontStyle.italic,
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
                border: pw.Border.all(color: PdfColors.grey400),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    "AFFECTIVE DOMAIN (1-5)",
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.blue800,
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
                pw.SizedBox(height: 10),
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
      return pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            children: [
              pw.Container(
                width: 150,
                decoration: const pw.BoxDecoration(
                  border: pw.Border(
                    bottom: pw.BorderSide(color: PdfColors.black, width: 1),
                  ),
                ),
              ),
              pw.SizedBox(height: 5),
              pw.Text(
                "Class Teacher's Signature & Date",
                style: const pw.TextStyle(
                  fontSize: 9,
                  color: PdfColors.grey700,
                ),
              ),
            ],
          ),
          pw.Column(
            children: [
              pw.Container(
                width: 150,
                decoration: const pw.BoxDecoration(
                  border: pw.Border(
                    bottom: pw.BorderSide(color: PdfColors.black, width: 1),
                  ),
                ),
              ),
              pw.SizedBox(height: 5),
              pw.Text(
                "$headTitle's Signature & Date",
                style: const pw.TextStyle(
                  fontSize: 9,
                  color: PdfColors.grey700,
                ),
              ),
            ],
          ),
        ],
      );
    }

    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        pageFormat: format,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.FittedBox(
            fit: pw.BoxFit.scaleDown,
            alignment: pw.Alignment.topCenter,
            child: pw.Container(
              width: format.availableWidth,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  buildHeader(),
                  pw.SizedBox(height: 20),
                  buildInfoBanner(),
                  pw.SizedBox(height: 20),
                  buildCognitiveTable(),
                  pw.SizedBox(height: 20),
                  buildAffectiveArea(),
                  pw.SizedBox(height: 40),
                  buildSignatures(),
                ],
              ),
            ),
          );
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
