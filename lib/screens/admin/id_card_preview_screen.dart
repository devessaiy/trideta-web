import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:screenshot/screenshot.dart';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'components/id_card_widget.dart';

class IdCardPreviewScreen extends StatefulWidget {
  final Map<String, dynamic> student;
  final String schoolName;
  final String schoolAddress;
  final String schoolPhone;
  final String schoolEmail;
  final String brandColorHex;

  const IdCardPreviewScreen({
    super.key,
    required this.student,
    required this.schoolName,
    required this.schoolAddress,
    required this.schoolPhone,
    required this.schoolEmail,
    required this.brandColorHex,
  });

  @override
  State<IdCardPreviewScreen> createState() => _IdCardPreviewScreenState();
}

class _IdCardPreviewScreenState extends State<IdCardPreviewScreen> {
  final ScreenshotController _screenshotController = ScreenshotController();
  bool _isSaving = false;

  Future<void> _downloadFullIdCard() async {
    setState(() => _isSaving = true);
    try {
      // 1. CAPTURE THE LIVE SCREEN WIDGET
      final Uint8List? imageBytes = await _screenshotController.capture(
        delay: const Duration(milliseconds: 100),
        // 🚨 PERFORMANCE FIX: Dropped to 1.5.
        // This generates a ~215 DPI image, which is perfectly crisp for a 54mm card
        // but stops the browser's CPU from choking.
        pixelRatio: 1.5,
      );

      if (imageBytes != null) {
        // 2. CONVERT TO A4 PDF
        final pdf = pw.Document();
        final pdfImage = pw.MemoryImage(imageBytes);

        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(30),
            build: (pw.Context context) {
              return pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.SizedBox(height: 20 * PdfPageFormat.mm),

                  pw.Text(
                    "TRIDETA ID CARD - PRINT SHEET",
                    style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 5),
                  pw.Text(
                    "Print this A4 document at exactly 100% scale (Do not select 'Fit to Page').",
                    style: const pw.TextStyle(
                      fontSize: 10,
                      color: PdfColors.grey700,
                    ),
                  ),
                  pw.Text(
                    "The cards below are strictly formatted to physical CR80 dimensions (54mm x 86mm).",
                    style: const pw.TextStyle(
                      fontSize: 10,
                      color: PdfColors.grey700,
                    ),
                  ),

                  pw.SizedBox(height: 40 * PdfPageFormat.mm),

                  pw.Container(
                    width: 111.6 * PdfPageFormat.mm,
                    height: 86 * PdfPageFormat.mm,
                    child: pw.Image(pdfImage, fit: pw.BoxFit.contain),
                  ),
                ],
              );
            },
          ),
        );

        final Uint8List pdfBytes = await pdf.save();
        final safeFileName = "${widget.student['first_name']}_ID_Card.pdf";

        // 3. SHARE / DOWNLOAD
        await Printing.sharePdf(bytes: pdfBytes, filename: safeFileName);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("PDF Downloaded successfully!"),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error: ${e.toString()}"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[200],
      appBar: AppBar(
        title: const Text(
          "ID Card Preview",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF007ACC),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: FittedBox(
            fit: BoxFit.contain,
            child: Screenshot(
              controller: _screenshotController,
              child: TridetaIdCard(
                student: widget.student,
                schoolName: widget.schoolName,
                schoolAddress: widget.schoolAddress,
                schoolPhone: widget.schoolPhone,
                schoolEmail: widget.schoolEmail,
                brandColorHex: widget.brandColorHex,
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(20),
        color: Colors.white,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF007ACC),
            padding: const EdgeInsets.symmetric(vertical: 15),
          ),
          onPressed: _isSaving ? null : _downloadFullIdCard,
          icon: _isSaving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : const Icon(Icons.picture_as_pdf, color: Colors.white),
          label: Text(
            _isSaving ? "Generating A4 PDF..." : "Download A4 Print Sheet",
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
        ),
      ),
    );
  }
}
