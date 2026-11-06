import 'dart:io';
import 'package:flutter/material.dart';

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
    // 🚨 UI FIX: Completely flattened the header, vertically stacked matching WhatsApp
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(top: 20, bottom: 30),
      color: cardColor,
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
                    color: primaryColor.withValues(alpha: 0.3),
                    width: 2,
                  ),
                ),
                child: CircleAvatar(
                  radius: 65, // Massive WhatsApp-style avatar
                  backgroundColor: primaryColor.withValues(alpha: 0.1),
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
          const SizedBox(height: 16),
          Text(
            displayName,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            "$studentClass  •  ID: ${admissionNo ?? 'N/A'}",
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade500,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            "Tap photo to preview or change",
            style: TextStyle(
              fontSize: 11,
              color: primaryColor,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
