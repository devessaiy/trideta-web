import 'package:trideta_v2/utils/auth_error_handler.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trideta_v2/main.dart'; // To access the global appColorNotifier

// 🚨 PDF PACKAGES FOR ID GENERATION
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:trideta_v2/widgets/trideta_loader.dart';

class IdCardGeneratorScreen extends StatefulWidget {
  const IdCardGeneratorScreen({super.key});

  @override
  State<IdCardGeneratorScreen> createState() => _IdCardGeneratorScreenState();
}

class _IdCardGeneratorScreenState extends State<IdCardGeneratorScreen>
    with AuthErrorHandler {
  final _supabase = Supabase.instance.client;

  bool _isLoadingConfig = true;
  bool _isLoadingStudents = false;
  bool _isGenerating = false;

  String? _schoolId;
  String _schoolName = "Trideta School";
  String _schoolAddress = "Return to School Administration";
  String _schoolEmail = "";
  String _schoolPhone = "";
  String? _schoolLogoUrl;

  List<String> _activeClasses = [];
  String? _selectedClass;
  List<Map<String, dynamic>> _students = [];

  // Standard CR80 ID Card physical dimensions (54mm x 86mm)
  final double _cardWidth = 54 * PdfPageFormat.mm;
  final double _cardHeight = 86 * PdfPageFormat.mm;

  @override
  void initState() {
    super.initState();
    _fetchConfig();
  }

  Future<void> _fetchConfig() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final profile = await _supabase
          .from('profiles')
          .select('school_id')
          .eq('id', user.id)
          .single();

      _schoolId = profile['school_id'];

      if (_schoolId != null) {
        final schoolData = await _supabase
            .from('schools')
            .select('name, logo_url, address, contact_email, contact_phone')
            .eq('id', _schoolId!)
            .single();

        _schoolName = schoolData['name'] ?? "Trideta School";
        _schoolLogoUrl = schoolData['logo_url'];
        _schoolAddress =
            schoolData['address'] ?? "Return to School Administration";
        _schoolEmail = schoolData['contact_email'] ?? "";
        _schoolPhone = schoolData['contact_phone'] ?? "";

        final classData = await _supabase
            .from('classes')
            .select('name')
            .eq('school_id', _schoolId!)
            .order('list_order', ascending: true);

        _activeClasses = classData.map((c) => c['name'].toString()).toList();

        if (_activeClasses.isNotEmpty) {
          _selectedClass = _activeClasses.first;
          await _fetchStudentsForClass(_selectedClass!);
        }
      }
    } catch (e) {
      debugPrint("Failed to load config: $e");
    } finally {
      if (mounted) setState(() => _isLoadingConfig = false);
    }
  }

  Future<void> _fetchStudentsForClass(String className) async {
    setState(() => _isLoadingStudents = true);
    try {
      final res = await _supabase
          .from('students')
          .select('id, first_name, last_name, admission_no, passport_url')
          .eq('school_id', _schoolId!)
          .eq('class_level', className)
          .order('first_name', ascending: true);

      if (mounted) {
        setState(() {
          _students = List<Map<String, dynamic>>.from(res);
        });
      }
    } catch (e) {
      debugPrint("Failed to load students: $e");
    } finally {
      if (mounted) setState(() => _isLoadingStudents = false);
    }
  }

  // ============================================================================
  // 🚨 PRIMARY: INDIVIDUAL ID CARD (CENTERED ON A4)
  // ============================================================================
  Future<void> _generateIndividualId(Map<String, dynamic> student) async {
    setState(() => _isGenerating = true);
    try {
      pw.ImageProvider? schoolLogo;
      if (_schoolLogoUrl != null && _schoolLogoUrl!.isNotEmpty) {
        try {
          schoolLogo = await networkImage(_schoolLogoUrl!);
        } catch (_) {}
      }

      pw.ImageProvider? studentPhoto;
      if (student['passport_url'] != null &&
          student['passport_url'].toString().startsWith('http')) {
        try {
          studentPhoto = await networkImage(student['passport_url']);
        } catch (_) {}
      }

      // 🔥 Fetch global brand color
      final schoolColorVal = appColorNotifier.value;
      final schoolBrandColor = PdfColor.fromInt(schoolColorVal.toARGB32());

      final pdf = pw.Document();

      // Page 1: The Front
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return pw.Center(
              child: _buildIdCardFront(
                student,
                _schoolName,
                schoolLogo,
                studentPhoto,
                _cardWidth,
                _cardHeight,
                schoolBrandColor,
              ),
            );
          },
        ),
      );

      // Page 2: The Back
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return pw.Center(
              child: _buildIdCardBack(
                student,
                _schoolName,
                _schoolAddress,
                _schoolEmail,
                _schoolPhone,
                _cardWidth,
                _cardHeight,
                schoolBrandColor,
              ),
            );
          },
        ),
      );

      final bytes = await pdf.save();
      String fileName = "${student['first_name']}_ID_Card.pdf".replaceAll(
        ' ',
        '_',
      );

      if (mounted) {
        setState(() => _isGenerating = false);
        await Printing.sharePdf(bytes: bytes, filename: fileName);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Downloading $fileName..."),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isGenerating = false);
        showAuthErrorDialog("Error generating ID card: $e");
      }
    }
  }

  // ============================================================================
  // 🚨 SECONDARY: BULK ID CARD GENERATOR (A4 3x3 GRID - ALTERNATING FRONT/BACK)
  // ============================================================================
  Future<void> _generateBulkIdCards() async {
    if (_students.isEmpty) {
      showAuthErrorDialog(
        "No students found in $_selectedClass to bulk generate.",
      );
      return;
    }
    setState(() => _isGenerating = true);

    try {
      pw.ImageProvider? schoolLogo;
      if (_schoolLogoUrl != null && _schoolLogoUrl!.isNotEmpty) {
        try {
          schoolLogo = await networkImage(_schoolLogoUrl!);
        } catch (_) {}
      }

      Map<String, pw.ImageProvider> studentPhotos = {};
      for (var student in _students) {
        String? photoUrl = student['passport_url'];
        if (photoUrl != null &&
            photoUrl.isNotEmpty &&
            photoUrl.startsWith('http')) {
          try {
            studentPhotos[student['id']] = await networkImage(photoUrl);
          } catch (_) {}
        }
      }

      // 🔥 Fetch global brand color
      final schoolColorVal = appColorNotifier.value;
      final schoolBrandColor = PdfColor.fromInt(schoolColorVal.toARGB32());

      final pdf = pw.Document();
      final int chunkSize = 9;

      for (var i = 0; i < _students.length; i += chunkSize) {
        final chunk = _students.sublist(
          i,
          i + chunkSize > _students.length ? _students.length : i + chunkSize,
        );

        // A4 PAGE 1: FRONTS
        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(30),
            build: (pw.Context context) {
              return pw.Wrap(
                spacing: 15,
                runSpacing: 15,
                children: chunk.map((student) {
                  return _buildIdCardFront(
                    student,
                    _schoolName,
                    schoolLogo,
                    studentPhotos[student['id']],
                    _cardWidth,
                    _cardHeight,
                    schoolBrandColor,
                  );
                }).toList(),
              );
            },
          ),
        );

        // A4 PAGE 2: BACKS
        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(30),
            build: (pw.Context context) {
              return pw.Wrap(
                spacing: 15,
                runSpacing: 15,
                children: chunk.map((student) {
                  return _buildIdCardBack(
                    student,
                    _schoolName,
                    _schoolAddress,
                    _schoolEmail,
                    _schoolPhone,
                    _cardWidth,
                    _cardHeight,
                    schoolBrandColor,
                  );
                }).toList(),
              );
            },
          ),
        );
      }

      final bytes = await pdf.save();
      String fileName = "${_selectedClass}_Bulk_IDs.pdf".replaceAll(' ', '_');

      if (mounted) {
        setState(() => _isGenerating = false);
        await Printing.sharePdf(bytes: bytes, filename: fileName);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isGenerating = false);
        showAuthErrorDialog("Error generating bulk ID cards: $e");
      }
    }
  }

  // ============================================================================
  // 🚨 REDESIGNED FRONT CARD BUILDER (Aesthetic Adaptation)
  // ============================================================================
  pw.Widget _buildIdCardFront(
    Map<String, dynamic> student,
    String schoolName,
    pw.ImageProvider? schoolLogo,
    pw.ImageProvider? studentPhoto,
    double width,
    double height,
    PdfColor brandAccent, // dynamic brand color
  ) {
    String firstName = student['first_name']?.toString() ?? '';
    String lastName = student['last_name']?.toString() ?? '';
    String studentName = "$firstName $lastName";
    String admissionNo = student['admission_no']?.toString() ?? 'N/A';

    final schoolColorVal = appColorNotifier.value;
    final hsv = HSVColor.fromColor(schoolColorVal);

    // Create lighter/darker variations for depth and geometric styling
    final lightColor = PdfColor.fromInt(
      hsv.withAlpha(0.2).toColor().toARGB32(),
    );
    final fadedColor = PdfColor.fromInt(
      hsv.withAlpha(0.6).toColor().toARGB32(),
    );
    final darkColor = PdfColor.fromInt(hsv.withValue(0.4).toColor().toARGB32());

    const textPrimary = PdfColor.fromInt(0xFF212121); // Charcoal for info

    final double photoD = 58.0; // main central photo diameter

    return pw.Container(
      width: width,
      height: height,
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: pw.BorderRadius.circular(10),
        border: pw.Border.all(color: PdfColors.grey200, width: 0.5),
      ),
      child: pw.Stack(
        children: [
          // ─── 1. MODERN GEOMETRIC BACKGROUND ───
          pw.Positioned.fill(
            child: pw.Container(
              decoration: const pw.BoxDecoration(
                borderRadius: pw.BorderRadius.all(pw.Radius.circular(10)),
                gradient: pw.LinearGradient(
                  begin: pw.Alignment.topCenter,
                  end: pw.Alignment.bottomCenter,
                  colors: [PdfColors.white, PdfColor.fromInt(0xFFFAFAFA)],
                ),
              ),
            ),
          ),

          // Stylized central wave background layer (light tone)
          pw.Positioned(
            top: height * 0.25,
            left: -width * 0.1,
            right: -width * 0.1,
            child: pw.Container(
              height: height * 0.5,
              decoration: pw.BoxDecoration(
                color: lightColor,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(50)),
              ),
            ),
          ),

          // Small decorative geometric accent shapes
          pw.Positioned(
            top: 20,
            right: 10,
            child: pw.Container(width: 8, height: 8, color: fadedColor),
          ),
          pw.Positioned(
            bottom: height * 0.15,
            left: width * 0.05,
            child: pw.Container(width: 12, height: 12, color: lightColor),
          ),

          // ─── 2. SCHOOL HEADER ───
          pw.Positioned(
            top: 10,
            left: 0,
            right: 0,
            child: pw.Column(
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                if (schoolLogo != null)
                  pw.Container(
                    width: 22,
                    height: 22,
                    margin: const pw.EdgeInsets.only(bottom: 2),
                    child: pw.Image(schoolLogo, fit: pw.BoxFit.contain),
                  ),
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 10),
                  child: pw.Text(
                    schoolName.toUpperCase(),
                    style: pw.TextStyle(
                      color: textPrimary,
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 8,
                    ),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
                pw.SizedBox(height: 1),
                pw.Text(
                  "STUDENT ID",
                  style: pw.TextStyle(
                    color: brandAccent,
                    fontSize: 5.5,
                    fontWeight: pw.FontWeight.bold,
                  ),
                  textAlign: pw.TextAlign.center,
                ),
              ],
            ),
          ),

          // ─── 3. CENTRAL STYLIZED PHOTO ───
          pw.Positioned(
            top:
                (height - photoD) /
                2.3, // Centered vertically, slight offset up
            left: (width - photoD) / 2,
            child: pw.Container(
              width: photoD,
              height: photoD,
              decoration: pw.BoxDecoration(
                shape: pw.BoxShape.circle,
                color: PdfColors.white,
                border: pw.Border.all(color: fadedColor, width: 2.5),
                boxShadow: [
                  pw.BoxShadow(
                    color: PdfColor.fromInt(
                      hsv.withAlpha(0.25).toColor().toARGB32(),
                    ),
                    blurRadius: 10,
                    spreadRadius: 2,
                    offset: const PdfPoint(0, 5),
                  ),
                ],
              ),
              child: pw.ClipOval(
                child: studentPhoto != null
                    ? pw.Image(studentPhoto, fit: pw.BoxFit.cover)
                    : pw.Container(
                        color: PdfColors.grey100,
                        child: pw.Center(
                          child: pw.Text(
                            "${firstName.isNotEmpty ? firstName[0] : ''}${lastName.isNotEmpty ? lastName[0] : ''}",
                            style: pw.TextStyle(
                              fontSize: 20,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.grey500,
                            ),
                          ),
                        ),
                      ),
              ),
            ),
          ),

          // Small decorative geometric accent shapes next to photo
          pw.Positioned(
            top: (height - photoD) / 2.3 - 5,
            left: (width - photoD) / 2 - 5,
            child: pw.Container(
              width: 8,
              height: 8,
              decoration: pw.BoxDecoration(
                color: darkColor,
                shape: pw.BoxShape.circle,
              ),
            ),
          ),
          pw.Positioned(
            top: (height - photoD) / 2.3 + photoD - 5,
            left: (width - photoD) / 2 + photoD - 5,
            child: pw.Container(width: 10, height: 10, color: fadedColor),
          ),

          // ─── 4. STUDENT NAME + ID ROW ───
          pw.Positioned(
            bottom: 25,
            left: 0,
            right: 0,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 10),
                  child: pw.Text(
                    studentName.toUpperCase(),
                    style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 10.5,
                      color: textPrimary,
                    ),
                    textAlign: pw.TextAlign.center,
                    maxLines: 1,
                  ),
                ),
                pw.SizedBox(height: 1.5),

                // Class and ID number row
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Text(
                      _selectedClass ?? "",
                      style: pw.TextStyle(fontSize: 7.5, color: fadedColor),
                    ),
                    pw.Container(
                      width: 4,
                      height: 4,
                      margin: const pw.EdgeInsets.symmetric(horizontal: 6),
                      decoration: pw.BoxDecoration(
                        color: fadedColor,
                        shape: pw.BoxShape.circle,
                      ),
                    ),
                    pw.Text(
                      "ID: $admissionNo",
                      style: pw.TextStyle(
                        fontSize: 7.5,
                        color: darkColor,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ─── 5. FOOTER Dynamic Pattern Accent ───
          pw.Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: pw.Container(
              height: 14,
              decoration: pw.BoxDecoration(
                color: fadedColor,
                borderRadius: const pw.BorderRadius.only(
                  bottomLeft: pw.Radius.circular(10),
                  bottomRight: pw.Radius.circular(10),
                ),
              ),
            ),
          ),
          pw.Positioned(
            bottom: 3,
            left: 20,
            right: 20,
            child: pw.Container(
              height: 8,
              decoration: const pw.BoxDecoration(
                color: PdfColors.white,
                borderRadius: pw.BorderRadius.all(pw.Radius.circular(10)),
              ),
            ),
          ),
          pw.Positioned(
            bottom: 3,
            right: 20,
            child: pw.Container(
              width: height * 0.15,
              height: 8,
              decoration: pw.BoxDecoration(
                color: darkColor,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // 🚨 PREMIUM BACK CARD BUILDER (Dynamic Brand Color)
  // ============================================================================
  pw.Widget _buildIdCardBack(
    Map<String, dynamic> student,
    String schoolName,
    String schoolAddress,
    String schoolEmail,
    String schoolPhone,
    double width,
    double height,
    PdfColor brandColor, // 🔥 Dynamic Brand Color
  ) {
    String admissionNo = student['admission_no']?.toString() ?? 'N/A';

    // We replace the hardcoded Navy/Gold with the School's Brand Color.
    // For the secondary accent (previously gold), we use a dark grey to keep it premium.
    final accentColor = PdfColors.grey700;

    return pw.Container(
      width: width,
      height: height,
      decoration: pw.BoxDecoration(
        borderRadius: pw.BorderRadius.circular(8),
        color: PdfColors.white,
        border: pw.Border.all(color: brandColor, width: 0.5),
      ),
      child: pw.Column(
        children: [
          // Header Bar
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(vertical: 6),
            decoration: pw.BoxDecoration(
              color: brandColor,
              borderRadius: const pw.BorderRadius.vertical(
                top: pw.Radius.circular(8),
              ),
            ),
            child: pw.Text(
              "TERMS & CONDITIONS",
              style: pw.TextStyle(
                color: PdfColors.white,
                fontSize: 7,
                fontWeight: pw.FontWeight.bold,
                letterSpacing: 1,
              ),
              textAlign: pw.TextAlign.center,
            ),
          ),
          pw.Container(height: 1.5, color: accentColor),

          // Body Text
          pw.Expanded(
            child: pw.Padding(
              padding: const pw.EdgeInsets.all(10),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _buildPremiumBackInfo(
                    "1",
                    "This card is the property of $schoolName. Unauthorized use is prohibited.",
                    brandColor,
                    accentColor,
                  ),
                  pw.SizedBox(height: 6),
                  _buildPremiumBackInfo(
                    "2",
                    "If found, please return to:\n$schoolAddress${schoolPhone.isNotEmpty ? "\nTel: $schoolPhone" : ""}${schoolEmail.isNotEmpty ? "\nEmail: $schoolEmail" : ""}",
                    brandColor,
                    accentColor,
                  ),
                  pw.SizedBox(height: 6),
                  _buildPremiumBackInfo(
                    "3",
                    "Must be presented on demand to authorized officials.",
                    brandColor,
                    accentColor,
                  ),

                  pw.Spacer(),

                  // Bottom Section: QR and Signature
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      // QR Code (Encoding Admission No)
                      pw.Container(
                        width: 45,
                        height: 45,
                        padding: const pw.EdgeInsets.all(2),
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(color: brandColor, width: 1),
                          borderRadius: pw.BorderRadius.circular(4),
                        ),
                        child: pw.BarcodeWidget(
                          barcode: pw.Barcode.qrCode(),
                          data: admissionNo,
                          color: brandColor,
                        ),
                      ),
                      // Signature Line
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.center,
                        children: [
                          pw.Container(width: 50, height: 1, color: brandColor),
                          pw.SizedBox(height: 2),
                          pw.Text(
                            "Authorized Sign",
                            style: pw.TextStyle(
                              fontSize: 5,
                              color: brandColor,
                              fontStyle: pw.FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Footer Bar
          pw.Container(height: 1.5, color: accentColor),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(vertical: 4),
            decoration: pw.BoxDecoration(
              color: brandColor,
              borderRadius: const pw.BorderRadius.vertical(
                bottom: pw.Radius.circular(8),
              ),
            ),
            child: pw.Text(
              schoolName.toUpperCase(),
              style: const pw.TextStyle(
                color: PdfColors.white,
                fontSize: 5,
                letterSpacing: 0.5,
              ),
              textAlign: pw.TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildPremiumBackInfo(
    String number,
    String text,
    PdfColor numberColor,
    PdfColor textColor,
  ) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          "$number. ",
          style: pw.TextStyle(
            color: numberColor,
            fontSize: 6,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.Expanded(
          child: pw.Text(
            text,
            style: pw.TextStyle(
              color: textColor,
              fontSize: 6,
              lineSpacing: 1.2,
            ),
          ),
        ),
      ],
    );
  }

  // ============================================================================
  // 🚨 UI LAYOUT (UNTOUCHED)
  // ============================================================================
  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color primaryColor = Theme.of(context).primaryColor;
    Color bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF1F4F8);

    if (_isLoadingConfig) {
      return Scaffold(
        backgroundColor: bgColor,
        body: Center(child: TridetaLoader(color: primaryColor)),
      );
    }

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text(
          "Student ID Generator",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            children: [
              // ─── TOP CONTROL PANEL ───
              Container(
                padding: const EdgeInsets.all(20),
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.badge_rounded,
                          color: primaryColor,
                          size: 30,
                        ),
                        const SizedBox(width: 15),
                        const Expanded(
                          child: Text(
                            "Select a class to generate and download individual standard CR80 PVC ID Cards, or use the bulk download to print the whole class.",
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 15,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white10
                                  : Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isDark
                                    ? Colors.white10
                                    : Colors.grey.shade300,
                              ),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                isExpanded: true,
                                value: _selectedClass,
                                icon: Icon(Icons.class_, color: primaryColor),
                                items: _activeClasses.map((String c) {
                                  return DropdownMenuItem<String>(
                                    value: c,
                                    child: Text(
                                      c,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  );
                                }).toList(),
                                onChanged: (_isGenerating || _isLoadingStudents)
                                    ? null
                                    : (String? v) {
                                        if (v != null && v != _selectedClass) {
                                          setState(() {
                                            _selectedClass = v;
                                          });
                                          _fetchStudentsForClass(v);
                                        }
                                      },
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 15),
                        // 🚨 SECONDARY BULK DOWNLOAD BUTTON
                        Expanded(
                          flex: 1,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: primaryColor,
                              side: BorderSide(color: primaryColor),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: _isGenerating
                                ? null
                                : _generateBulkIdCards,
                            icon: const Icon(Icons.file_download, size: 18),
                            label: const Text(
                              "BULK A4",
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // ─── STUDENT LIST ───
              Expanded(
                child: _isLoadingStudents
                    ? Center(child: TridetaLoader(color: primaryColor))
                    : _students.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.search_off,
                              size: 60,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              "No students found in this class.",
                              style: TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        itemCount: _students.length,
                        itemBuilder: (context, index) {
                          final student = _students[index];
                          final String fullName =
                              "${student['first_name']} ${student['last_name']}";
                          final String? photoUrl = student['passport_url'];

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF1E1E1E)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(15),
                              border: Border.all(
                                color: isDark
                                    ? Colors.white10
                                    : Colors.grey.shade200,
                              ),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              leading: CircleAvatar(
                                backgroundColor: primaryColor.withValues(
                                  alpha: 0.1,
                                ),
                                backgroundImage:
                                    photoUrl != null && photoUrl.isNotEmpty
                                    ? NetworkImage(photoUrl)
                                    : null,
                                child: photoUrl == null || photoUrl.isEmpty
                                    ? Icon(Icons.person, color: primaryColor)
                                    : null,
                              ),
                              title: Text(
                                fullName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                "ID: ${student['admission_no'] ?? 'N/A'}",
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              // 🚨 PRIMARY ACTION BUTTON
                              trailing: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: primaryColor,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                onPressed: _isGenerating
                                    ? null
                                    : () => _generateIndividualId(student),
                                icon: const Icon(
                                  Icons.download_rounded,
                                  size: 16,
                                ),
                                label: const Text("DOWNLOAD"),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
