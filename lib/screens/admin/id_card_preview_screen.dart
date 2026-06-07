import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:screenshot/screenshot.dart';
import 'package:gal/gal.dart';
import 'package:file_saver/file_saver.dart'; // 🚨 Pure Flutter file saving
import 'package:flutter/foundation.dart' show kIsWeb;

import 'components/id_card_widget.dart';

class IdCardPreviewScreen extends StatefulWidget {
  final Map<String, dynamic> student;
  final String schoolName;
  // 🚨 THIS IS WHAT WAS MISSING: Declaring the variables!
  final String schoolAddress;
  final String schoolPhone;
  final String schoolEmail;

  const IdCardPreviewScreen({
    super.key,
    required this.student,
    required this.schoolName,
    required this.schoolAddress,
    required this.schoolPhone,
    required this.schoolEmail,
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
      final Uint8List imageBytes = await _screenshotController
          .captureFromWidget(
            TridetaIdCard(
              student: widget.student,
              schoolName: widget.schoolName,
              schoolAddress: widget.schoolAddress,
              schoolPhone: widget.schoolPhone,
              schoolEmail: widget.schoolEmail,
            ),
            delay: const Duration(milliseconds: 200),
            pixelRatio: 2.0,
          );

      if (imageBytes != null) {
        final safeFileName = "${widget.student['first_name']}_A4_ID_Sheet";

        if (kIsWeb) {
          // 🚨 PURE FLUTTER WEB DOWNLOAD
          await FileSaver.instance.saveFile(
            name: safeFileName,
            bytes: imageBytes,
            fileExtension: "png",
            mimeType: MimeType.png,
          );

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  "A4 Image downloaded! Check your browser downloads.",
                ),
                backgroundColor: Colors.green,
              ),
            );
          }
        } else {
          // 🚨 MOBILE GALLERY LOGIC
          if (!await Gal.hasAccess(toAlbum: true)) {
            await Gal.requestAccess(toAlbum: true);
          }
          await Gal.putImageBytes(imageBytes);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("A4 Sheet saved to Gallery!"),
                backgroundColor: Colors.green,
              ),
            );
          }
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
      backgroundColor: Colors.grey[800],
      appBar: AppBar(
        title: const Text(
          "A4 Print Preview",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF007ACC),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: FittedBox(
            fit: BoxFit.contain,
            child: TridetaIdCard(
              student: widget.student,
              schoolName: widget.schoolName,
              schoolAddress: widget.schoolAddress,
              schoolPhone: widget.schoolPhone,
              schoolEmail: widget.schoolEmail,
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
              ? const CircularProgressIndicator(color: Colors.white)
              : const Icon(Icons.print, color: Colors.white),
          label: Text(
            _isSaving ? "Processing..." : "Download A4 Print Sheet",
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
        ),
      ),
    );
  }
}
