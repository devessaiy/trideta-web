// import 'package:flutter/material.dart';
// import 'package:barcode_widget/barcode_widget.dart';
// import 'package:qr_flutter/qr_flutter.dart';

// class TridetaIdCard extends StatelessWidget {
//   final Map<String, dynamic> student;
//   final String schoolName;

//   const TridetaIdCard({
//     super.key,
//     required this.student,
//     required this.schoolName,
//   });

//   // Helper to get the 3-letter abbreviation
//   String _getAbbreviation(String name) {
//     return name
//         .split(' ')
//         .map((e) => e.isNotEmpty ? e[0].toUpperCase() : '')
//         .take(3)
//         .join();
//   }

//   @override
//   Widget build(BuildContext context) {
//     // We render both the front and back stacked vertically so the downloaded image contains both
//     return Container(
//       color: Colors.white, // Background of the final exported image
//       padding: const EdgeInsets.all(20),
//       child: Column(
//         mainAxisSize: MainAxisSize.min,
//         children: [
//           _buildFrontCard(),
//           const SizedBox(height: 20), // Gap between front and back
//           _buildBackCard(),
//         ],
//       ),
//     );
//   }

//   // ==========================================
//   // FRONT OF ID CARD
//   // ==========================================
//   Widget _buildFrontCard() {
//     final String firstName =
//         student['first_name']?.toString().toUpperCase() ?? '';
//     final String lastName =
//         student['last_name']?.toString().toUpperCase() ?? '';
//     final String admissionNo = student['admission_no']?.toString() ?? 'N/A';
//     final String? passportUrl = student['passport_url'];
//     final String role = student['class_level'] ?? 'STUDENT';
//     const Color brandBlue = Color(
//       0xFF007ACC,
//     ); // Replacing the yellow with Trideta Blue

//     return Container(
//       width: 300,
//       height: 480,
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(16),
//         border: Border.all(color: Colors.grey.shade300),
//         boxShadow: const [
//           BoxShadow(
//             color: Colors.black12,
//             blurRadius: 10,
//             offset: Offset(0, 4),
//           ),
//         ],
//       ),
//       clipBehavior: Clip.antiAlias,
//       child: Stack(
//         children: [
//           // 1. Light Grey Diagonal Accent Background
//           Positioned(
//             top: 150,
//             left: -50,
//             right: -50,
//             child: Transform.rotate(
//               angle: -0.15, // Slanted accent
//               child: Container(height: 200, color: Colors.grey.shade100),
//             ),
//           ),

//           // 2. Top Black Slanted Header
//           ClipPath(
//             clipper: TopSlantClipper(),
//             child: Container(
//               height: 120,
//               color: Colors.black,
//               padding: const EdgeInsets.only(top: 25, left: 20),
//               child: Row(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   const Icon(Icons.school, color: Colors.white, size: 28),
//                   const SizedBox(width: 8),
//                   Text(
//                     _getAbbreviation(schoolName),
//                     style: const TextStyle(
//                       color: Colors.white,
//                       fontSize: 22,
//                       fontWeight: FontWeight.bold,
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//           ),

//           // 3. Bottom Blue Slanted Footer
//           Positioned(
//             bottom: 0,
//             left: 0,
//             right: 0,
//             child: ClipPath(
//               clipper: BottomSlantClipper(),
//               child: Container(
//                 height: 110,
//                 color: brandBlue,
//                 child: Column(
//                   mainAxisAlignment: MainAxisAlignment.end,
//                   children: [
//                     Text(
//                       "Batch ID $admissionNo",
//                       style: const TextStyle(
//                         color: Colors.white,
//                         fontWeight: FontWeight.bold,
//                         fontSize: 12,
//                       ),
//                     ),
//                     const SizedBox(height: 5),
//                     // Traditional Barcode
//                     Container(
//                       height: 35,
//                       width: 200,
//                       padding: const EdgeInsets.symmetric(
//                         horizontal: 10,
//                         vertical: 2,
//                       ),
//                       decoration: BoxDecoration(
//                         color: Colors.white,
//                         borderRadius: BorderRadius.circular(4),
//                       ),
//                       child: BarcodeWidget(
//                         barcode: Barcode.code128(),
//                         data: admissionNo,
//                         drawText: false,
//                         color: Colors.black,
//                       ),
//                     ),
//                     const SizedBox(height: 15),
//                   ],
//                 ),
//               ),
//             ),
//           ),

//           // 4. Center Profile Info
//           Positioned(
//             top: 90,
//             left: 0,
//             right: 0,
//             child: Column(
//               children: [
//                 // Profile Picture with Blue Border
//                 Container(
//                   width: 130,
//                   height: 130,
//                   decoration: BoxDecoration(
//                     color: Colors.white,
//                     borderRadius: BorderRadius.circular(24),
//                     border: Border.all(color: brandBlue, width: 4),
//                   ),
//                   child: ClipRRect(
//                     borderRadius: BorderRadius.circular(20),
//                     child: passportUrl != null
//                         ? Image.network(
//                             passportUrl,
//                             fit: BoxFit.cover,
//                             errorBuilder: (c, e, s) => const Icon(
//                               Icons.person,
//                               size: 60,
//                               color: Colors.grey,
//                             ),
//                           )
//                         : const Icon(
//                             Icons.person,
//                             size: 60,
//                             color: Colors.grey,
//                           ),
//                   ),
//                 ),
//                 const SizedBox(height: 15),
//                 // Name
//                 Text(
//                   "$firstName $lastName",
//                   style: const TextStyle(
//                     fontSize: 22,
//                     fontWeight: FontWeight.w900,
//                     color: Colors.black,
//                   ),
//                 ),
//                 const SizedBox(height: 8),
//                 // Role Pill
//                 Container(
//                   padding: const EdgeInsets.symmetric(
//                     horizontal: 24,
//                     vertical: 6,
//                   ),
//                   decoration: BoxDecoration(
//                     color: Colors.black,
//                     borderRadius: BorderRadius.circular(20),
//                   ),
//                   child: Text(
//                     role.toUpperCase(),
//                     style: const TextStyle(
//                       color: Colors.white,
//                       fontWeight: FontWeight.bold,
//                       letterSpacing: 1.5,
//                       fontSize: 12,
//                     ),
//                   ),
//                 ),
//                 const SizedBox(height: 15),
//                 // Expiry
//                 const Text(
//                   "Valid until 31 DEC 2026",
//                   style: TextStyle(
//                     fontSize: 12,
//                     fontWeight: FontWeight.bold,
//                     color: Colors.black87,
//                   ),
//                 ),
//               ],
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   // ==========================================
//   // BACK OF ID CARD
//   // ==========================================
//   Widget _buildBackCard() {
//     final String admissionNo = student['admission_no']?.toString() ?? 'N/A';
//     const Color brandBlue = Color(0xFF007ACC);

//     return Container(
//       width: 300,
//       height: 480,
//       decoration: BoxDecoration(
//         color: Colors.grey.shade100, // Light ash background
//         borderRadius: BorderRadius.circular(16),
//         border: Border.all(color: Colors.grey.shade300),
//         boxShadow: const [
//           BoxShadow(
//             color: Colors.black12,
//             blurRadius: 10,
//             offset: Offset(0, 4),
//           ),
//         ],
//       ),
//       clipBehavior: Clip.antiAlias,
//       child: Stack(
//         children: [
//           // 1. Top Black Slanted Header
//           ClipPath(
//             clipper: TopSlantClipper(),
//             child: Container(height: 100, color: Colors.black),
//           ),

//           // 2. Bottom Blue Slanted Footer
//           Positioned(
//             bottom: 0,
//             left: 0,
//             right: 0,
//             child: ClipPath(
//               clipper: BottomSlantClipper(),
//               child: Container(
//                 height: 150,
//                 color: brandBlue,
//                 padding: const EdgeInsets.only(left: 20, right: 20, bottom: 20),
//                 child: const Column(
//                   mainAxisAlignment: MainAxisAlignment.end,
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     Text(
//                       "IN CASE OF LOSS",
//                       style: TextStyle(
//                         color: Colors.white,
//                         fontWeight: FontWeight.bold,
//                         fontSize: 12,
//                       ),
//                     ),
//                     SizedBox(height: 4),
//                     Text(
//                       "If found, please return this card to the school administration office. Unauthorized use of this card is strictly prohibited.",
//                       style: TextStyle(
//                         color: Colors.white70,
//                         fontSize: 10,
//                         height: 1.4,
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//             ),
//           ),

//           // 3. Middle Content (School Info & QR)
//           Positioned(
//             top: 100,
//             left: 20,
//             right: 20,
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Text(
//                   schoolName.toUpperCase(),
//                   style: const TextStyle(
//                     fontWeight: FontWeight.w900,
//                     fontSize: 14,
//                   ),
//                 ),
//                 const SizedBox(height: 8),
//                 const Text(
//                   "123 Main Street, School District\nPhone: +234 (000) 123 4567\nEmail: info@school.edu",
//                   style: TextStyle(
//                     fontSize: 11,
//                     color: Colors.black87,
//                     height: 1.5,
//                   ),
//                 ),
//                 const SizedBox(height: 25),
//                 // QR Code
//                 Container(
//                   padding: const EdgeInsets.all(8),
//                   decoration: BoxDecoration(
//                     color: Colors.white,
//                     borderRadius: BorderRadius.circular(12),
//                     border: Border.all(color: Colors.grey.shade300),
//                   ),
//                   child: QrImageView(
//                     data: admissionNo,
//                     version: QrVersions.auto,
//                     size: 90.0,
//                   ),
//                 ),
//               ],
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }

// // ==========================================
// // CUSTOM CLIPPERS FOR THE SLANTED SHAPES
// // ==========================================
// class TopSlantClipper extends CustomClipper<Path> {
//   @override
//   Path getClip(Size size) {
//     final path = Path();
//     path.lineTo(0, size.height); // Left side goes full height
//     path.lineTo(size.width, size.height - 30); // Right side slants up
//     path.lineTo(size.width, 0);
//     path.close();
//     return path;
//   }

//   @override
//   bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
// }

// class BottomSlantClipper extends CustomClipper<Path> {
//   @override
//   Path getClip(Size size) {
//     final path = Path();
//     path.moveTo(0, 30); // Left side starts lower (slants down)
//     path.lineTo(size.width, 0); // Right side starts higher
//     path.lineTo(size.width, size.height);
//     path.lineTo(0, size.height);
//     path.close();
//     return path;
//   }

//   @override
//   bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
// }
