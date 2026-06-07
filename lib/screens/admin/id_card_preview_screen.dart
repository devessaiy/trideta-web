import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:screenshot/screenshot.dart';
import 'package:file_saver/file_saver.dart';

// 🚨 IMPORT PDF PACKAGE
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

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
      // 1. Capture the widget as a high-res image
      final Uint8List?
      imageBytes = await _screenshotController.captureFromWidget(
        // 🚨 CRITICAL FIX: The Material wrapper prevents the red screen of death crash
        Material(
          color: Colors.transparent,
          child: TridetaIdCard(
            student: widget.student,
            schoolName: widget.schoolName,
            schoolAddress: widget.schoolAddress,
            schoolPhone: widget.schoolPhone,
            schoolEmail: widget.schoolEmail,
            brandColorHex: widget.brandColorHex,
          ),
        ),
        delay: const Duration(milliseconds: 200),
        pixelRatio: 3.0,
      );

      if (imageBytes != null) {
        // 2. Convert the image into a PDF Document
        final pdf = pw.Document();
        final pdfImage = pw.MemoryImage(imageBytes);

        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat
                .a4
                .landscape, // Landscape fits side-by-side perfectly
            margin: const pw.EdgeInsets.all(20),
            build: (pw.Context context) {
              return pw.Center(child: pw.Image(pdfImage));
            },
          ),
        );

        final Uint8List pdfBytes = await pdf.save();
        final safeFileName = "${widget.student['first_name']}_ID_Card";

        // 3. Save as a universal PDF
        await FileSaver.instance.saveFile(
          name: safeFileName,
          bytes: pdfBytes,
          file: "pdf",
          mimeType: MimeType.pdf,
        );

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
          const SnackBar(
            content: Text("Failed to save. Check permissions."),
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
          // 🚨 FITTED BOX squishes the side-by-side layout perfectly onto your phone screen
          child: FittedBox(
            fit: BoxFit.contain,
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
            _isSaving ? "Generating PDF..." : "Download as PDF",
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
        ),
      ),
    );
  }
}
