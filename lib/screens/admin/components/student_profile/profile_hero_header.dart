import 'dart:io';
import 'package:flutter/material.dart';
import 'package:trideta_v2/widgets/trideta_ui_kit.dart';

class ProfileHeroHeader extends StatelessWidget {
  final String id;
  final String displayName;
  final String studentClass;
  final String? admissionNo;
  final String displayImagePath;
  final Color primaryColor;
  final Color cardColor;
  final bool isDark;
  final bool isDesktop;

  // 🚨 UI FIX: Added callback to allow the preview/edit dialog
  final VoidCallback? onImageTap;

  const ProfileHeroHeader({
    super.key,
    required this.id,
    required this.displayName,
    required this.studentClass,
    this.admissionNo,
    required this.displayImagePath,
    required this.primaryColor,
    required this.cardColor,
    required this.isDark,
    required this.isDesktop,
    this.onImageTap,
  });

  @override
  Widget build(BuildContext context) {
    return PCard(
      radius: 30,
      padding: const EdgeInsets.fromLTRB(20, 26, 20, 24),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: onImageTap,
              child: Hero(
                tag: id,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: primaryColor.withValues(alpha: 0.4),
                      width: 2,
                    ),
                  ),
                  child: CircleAvatar(
                    radius: 62,
                    backgroundColor: PUi.tint(primaryColor, isDark, 0.12),
                    backgroundImage: (displayImagePath.isNotEmpty)
                        ? (displayImagePath.startsWith('http')
                              ? NetworkImage(displayImagePath)
                              : FileImage(File(displayImagePath))
                                    as ImageProvider)
                        : null,
                    child: (displayImagePath.isEmpty)
                        ? Icon(
                            Icons.person_rounded,
                            size: 50,
                            color: primaryColor,
                          )
                        : null,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              displayName,
              style: PUi.title(isDark, size: 26),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                PPill(text: studentClass, color: primaryColor),
                PPill(
                  text: "ID: ${admissionNo ?? 'N/A'}",
                  color: PUi.muted(isDark),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              "Tap photo to preview or change",
              style: TextStyle(
                fontSize: 11.5,
                color: primaryColor,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
