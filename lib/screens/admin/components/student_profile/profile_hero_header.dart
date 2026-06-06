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
  final bool isDesktop; // 🚨 Receives the Desktop flag here!

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
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      // 🚨 Smart Layout: Clean card on Desktop, Edge-to-Edge gradient on Mobile
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
      decoration: isDesktop
          ? BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(20),
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
            )
          : BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  primaryColor.withValues(alpha: 0.05),
                  Colors.transparent,
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              border: Border(
                bottom: BorderSide(
                  color: isDark ? Colors.white10 : Colors.grey.shade200,
                ),
              ),
            ),
      child: Row(
        children: [
          Hero(
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
                radius: 40,
                backgroundColor: primaryColor.withValues(alpha: 0.1),
                backgroundImage: (displayImagePath.isNotEmpty)
                    ? (displayImagePath.startsWith('http')
                          ? NetworkImage(displayImagePath)
                          : FileImage(File(displayImagePath)) as ImageProvider)
                    : null,
                child: (displayImagePath.isEmpty)
                    ? Icon(Icons.person_rounded, size: 40, color: primaryColor)
                    : null,
              ),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  displayName,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: primaryColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        studentClass,
                        style: TextStyle(
                          color: primaryColor,
                          fontWeight: FontWeight.w900,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      admissionNo != null ? "ID: $admissionNo" : "Loading...",
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
