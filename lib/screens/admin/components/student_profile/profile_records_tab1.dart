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
    // 🚨 UI FIX: Pure Flat ListView Structure
    return ListView(
      padding: const EdgeInsets.only(bottom: 100),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 24, 24, 8),
          child: Text(
            "DOCUMENTS & EXPORTS",
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 12,
              color: Colors.grey,
              letterSpacing: 1.2,
            ),
          ),
        ),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 8,
          ),
          leading: const Icon(
            Icons.picture_as_pdf_rounded,
            color: Colors.redAccent,
            size: 28,
          ),
          title: const Text(
            "Comprehensive Dossier",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          subtitle: Text(
            "Generate historic results & biodata",
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
          ),
          trailing: isGeneratingRecord
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: TridetaLoader(color: primaryColor),
                )
              : Icon(Icons.download_rounded, color: primaryColor),
          onTap: isGeneratingRecord ? null : onGenerateTap,
        ),
        Padding(
          padding: const EdgeInsets.only(left: 72, right: 24),
          child: Divider(
            height: 1,
            color: isDark ? Colors.white10 : Colors.grey.shade200,
          ),
        ),
      ],
    );
  }
}
