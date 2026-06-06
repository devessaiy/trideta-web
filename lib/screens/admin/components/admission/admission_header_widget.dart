import 'dart:typed_data';
import 'package:flutter/material.dart';

class AdmissionHeaderWidget extends StatelessWidget {
  final Uint8List? webImage;
  final VoidCallback onPickImage;
  final String generatedID;
  final Color primaryColor;
  final bool isDark;
  final Color textColor;

  const AdmissionHeaderWidget({
    super.key,
    required this.webImage,
    required this.onPickImage,
    required this.generatedID,
    required this.primaryColor,
    required this.isDark,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        children: [
          GestureDetector(
            onTap: onPickImage,
            child: Stack(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.05),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: primaryColor.withValues(alpha: 0.2),
                      width: 2,
                    ),
                  ),
                  child: CircleAvatar(
                    radius: 65,
                    backgroundColor: isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.white,
                    backgroundImage: webImage != null
                        ? MemoryImage(webImage!)
                        : null,
                    child: webImage == null
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.add_a_photo_rounded,
                                size: 32,
                                color: primaryColor.withValues(alpha: 0.7),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "Upload",
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: primaryColor.withValues(alpha: 0.7),
                                ),
                              ),
                            ],
                          )
                        : null,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 25),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2C2C2C) : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark ? Colors.white10 : Colors.grey.shade300,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.tag_rounded, size: 16, color: Colors.grey.shade500),
                const SizedBox(width: 8),
                Text(
                  generatedID,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: textColor,
                    letterSpacing: 2.0,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
