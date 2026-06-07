import 'package:flutter/material.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:qr_flutter/qr_flutter.dart';

class TridetaIdCard extends StatelessWidget {
  final Map<String, dynamic> student;
  final String schoolName;

  // 🚨 NEW VARIABLES ADDED TO THE CONSTRUCTOR HERE
  final String schoolAddress;
  final String schoolPhone;
  final String schoolEmail;

  const TridetaIdCard({
    super.key,
    required this.student,
    required this.schoolName,
    required this.schoolAddress,
    required this.schoolPhone,
    required this.schoolEmail,
  });

  // 🚨 FORMATTER: Abbreviates last name if total length is > 15 chars to keep it centered
  String _formatName(String first, String last) {
    if ((first.length + last.length) > 15) {
      return "$first ${last.isNotEmpty ? last[0] + '.' : ''}".toUpperCase();
    }
    return "$first $last".toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    // 🚨 A4 PAPER SIZING LOGIC 🚨
    // A standard CR80 ID Card is 54mm x 86mm. A4 Paper is 210mm x 297mm.
    // If our digital card width is 300px, then exactly scaled A4 dimensions are 1166px by 1650px.
    return Container(
      width: 1166,
      height: 1650,
      color: Colors.white, // The white A4 background
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            "PRINT ON A4 PAPER AT 100% SCALE (DO NOT 'FIT TO PAGE')",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 40),

          // Front Card wrapped in a dashed cutting border
          Container(
            padding: const EdgeInsets.all(1),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey, style: BorderStyle.solid),
            ),
            child: _buildFrontCard(),
          ),

          const SizedBox(height: 60), // Gap between front and back
          // Back Card wrapped in a dashed cutting border
          Container(
            padding: const EdgeInsets.all(1),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey, style: BorderStyle.solid),
            ),
            child: _buildBackCard(),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // FRONT OF ID CARD
  // ==========================================
  Widget _buildFrontCard() {
    final String firstName = student['first_name']?.toString() ?? '';
    final String lastName = student['last_name']?.toString() ?? '';
    final String formattedName = _formatName(firstName, lastName);

    final String admissionNo = student['admission_no']?.toString() ?? 'N/A';
    final String? passportUrl = student['passport_url'];
    final String role = student['class_level'] ?? 'STUDENT';
    const Color brandBlue = Color(0xFF007ACC);

    return Container(
      width: 300,
      height: 478, // Exact CR80 ratio (300 x 1.592)
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Background slant
          Positioned(
            top: 150,
            left: -50,
            right: -50,
            child: Transform.rotate(
              angle: -0.15,
              child: Container(height: 200, color: Colors.grey.shade100),
            ),
          ),

          // Top Black Header
          ClipPath(
            clipper: TopSlantClipper(),
            child: Container(
              height: 120,
              color: Colors.black,
              padding: const EdgeInsets.only(top: 25, left: 15, right: 15),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.school, color: Colors.white, size: 28),
                  const SizedBox(width: 8),
                  // FULL NAME LOGIC: Flexible wrapper prevents overflow
                  Expanded(
                    child: Text(
                      schoolName.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        height: 1.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Bottom Blue Footer
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: ClipPath(
              clipper: BottomSlantClipper(),
              child: Container(
                height: 110,
                color: brandBlue,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      "Batch ID $admissionNo",
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Container(
                      height: 35,
                      width: 200,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: BarcodeWidget(
                        barcode: Barcode.code128(),
                        data: admissionNo,
                        drawText: false,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 15),
                  ],
                ),
              ),
            ),
          ),

          // Center Profile Info
          Positioned(
            top: 90,
            left: 0,
            right: 0,
            child: Column(
              children: [
                Container(
                  width: 130,
                  height: 130,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: brandBlue, width: 4),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: passportUrl != null && passportUrl.startsWith('http')
                        ? Image.network(
                            passportUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (c, e, s) => const Icon(
                              Icons.person,
                              size: 60,
                              color: Colors.grey,
                            ),
                          )
                        : const Icon(
                            Icons.person,
                            size: 60,
                            color: Colors.grey,
                          ),
                  ),
                ),
                const SizedBox(height: 15),
                // CENTERED FORMATTED NAME
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    formattedName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: Colors.black,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    role.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 15),
                const Text(
                  "Valid until 31 DEC 2026",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // BACK OF ID CARD
  // ==========================================
  Widget _buildBackCard() {
    final String admissionNo = student['admission_no']?.toString() ?? 'N/A';
    const Color brandBlue = Color(0xFF007ACC);

    return Container(
      width: 300,
      height: 478,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          ClipPath(
            clipper: TopSlantClipper(),
            child: Container(height: 100, color: Colors.black),
          ),

          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: ClipPath(
              clipper: BottomSlantClipper(),
              child: Container(
                height: 150,
                color: brandBlue,
                padding: const EdgeInsets.only(left: 20, right: 20, bottom: 20),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "IN CASE OF LOSS",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      "If found, please return this card to the school administration office. Unauthorized use of this card is strictly prohibited.",
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          Positioned(
            top: 100,
            left: 20,
            right: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  schoolName.toUpperCase(),
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 8),
                // 🚨 REAL DATA INJECTED HERE
                Text(
                  "$schoolAddress\nPhone: $schoolPhone\nEmail: $schoolEmail",
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.black87,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 25),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: QrImageView(
                    data: admissionNo,
                    version: QrVersions.auto,
                    size: 90.0,
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

// Custom Clippers
class TopSlantClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height);
    path.lineTo(size.width, size.height - 30);
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class BottomSlantClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.moveTo(0, 30);
    path.lineTo(size.width, 0);
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
