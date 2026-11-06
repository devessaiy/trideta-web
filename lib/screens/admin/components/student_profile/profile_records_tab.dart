import 'package:flutter/material.dart';
import 'package:trideta_v2/widgets/trideta_loader.dart';
import 'package:trideta_v2/widgets/trideta_ui_kit.dart';

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
    // Inline (non-scrolling) list: the whole profile page scrolls as one.
    return ListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text("DOCUMENTS & EXPORTS", style: PUi.sectionLabel(isDark)),
        ),
        PCard(
          radius: 26,
          padding: const EdgeInsets.all(16),
          onTap: isGeneratingRecord ? null : onGenerateTap,
          child: Row(
            children: [
              const PIconBadge(
                icon: Icons.picture_as_pdf_rounded,
                color: Colors.redAccent,
                size: 50,
                iconSize: 24,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Comprehensive Dossier",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15.5,
                        color: PUi.ink(isDark),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Generate historic results & biodata",
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: PUi.muted(isDark),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              isGeneratingRecord
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: TridetaLoader(color: primaryColor),
                    )
                  : Icon(Icons.download_rounded, color: primaryColor),
            ],
          ),
        ),
      ],
    );
  }
}
