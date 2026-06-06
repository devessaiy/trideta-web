import 'package:flutter/material.dart';
import 'package:trideta_v2/widgets/trideta_loader.dart';

class ProfileRecordsTab extends StatelessWidget {
  final bool isGeneratingRecord;
  final VoidCallback onGenerateTap;
  final Color primaryColor;
  final Color cardColor;
  final bool isDark;

  const ProfileRecordsTab({
    super.key,
    required this.isGeneratingRecord,
    required this.onGenerateTap,
    required this.primaryColor,
    required this.cardColor,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 100),
      child: Container(
        padding: const EdgeInsets.all(30),
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
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.assignment_ind_rounded,
                size: 60,
                color: primaryColor,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              "Comprehensive Student Dossier",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              "Generate a complete, printable PDF record including historic term results, attendance records, and active biodata.",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey.shade500,
                height: 1.5,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: primaryColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: isGeneratingRecord ? null : onGenerateTap,
                icon: isGeneratingRecord
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: TridetaLoader(color: Colors.white),
                      )
                    : const Icon(
                        Icons.picture_as_pdf_rounded,
                        color: Colors.white,
                      ),
                label: Text(
                  isGeneratingRecord
                      ? "PACKAGING FILES..."
                      : "GENERATE FULL RECORD",
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
