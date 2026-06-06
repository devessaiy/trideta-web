import 'package:trideta_v2/utils/auth_error_handler.dart';
import 'package:trideta_v2/widgets/trideta_loader.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'package:pdf/pdf.dart' show PdfColor, PdfColors, PdfPageFormat;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

// MODULAR IMPORTS
import 'package:trideta_v2/screens/admin/components/student_profile/profile_hero_header.dart';
import 'package:trideta_v2/screens/admin/components/student_profile/parent_security_dialogs.dart'; // 🚨 NEW COMPONENT
import 'package:trideta_v2/screens/admin/components/student_profile/profile_academic_tab.dart';
import 'package:trideta_v2/screens/admin/components/student_profile/profile_records_tab.dart';
import 'package:trideta_v2/screens/admin/components/student_profile/profile_edit_form.dart';
import 'package:trideta_v2/screens/admin/components/student_profile/parent_security_dialogs.dart';

// Fallback/local stub for ParentSecurityCard in case the imported component
// isn't available. Keeps the file compilable and provides basic functionality.
// Premium local replacement for ParentSecurityCard.

class ParentSecurityCard extends StatefulWidget {
  final bool isCheckingStatus;
  final String? dbParentPhone;
  final VoidCallback onSecurityTap;
  final VoidCallback onCallTap;
  final Color primaryColor;
  final bool isDesktop;

  const ParentSecurityCard({
    super.key,
    required this.isCheckingStatus,
    this.dbParentPhone,
    required this.onSecurityTap,
    required this.onCallTap,
    required this.primaryColor,
    required this.isDesktop,
  });

  @override
  State<ParentSecurityCard> createState() => _ParentSecurityCardState();
}

class _ParentSecurityCardState extends State<ParentSecurityCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color pColor = widget.primaryColor;

    if (widget.isCheckingStatus) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Container(
      margin: widget.isDesktop ? EdgeInsets.zero : const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Theme(
          // This removes the ugly default borders Flutter adds to ExpansionTiles
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: _isExpanded,
            onExpansionChanged: (expanded) {
              setState(() {
                _isExpanded = expanded;
              });
            },
            tilePadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 8,
            ),
            childrenPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            // The chevron arrow icon automatically handles its own animation
            iconColor: Colors.grey.shade500,
            collapsedIconColor: Colors.grey.shade400,

            // --- Premium Header Row (Always Visible) ---
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.verified_user_rounded,
                    color: Colors.green,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Parent Account Active",
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                          color: Colors.green,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      // Smart text that updates based on the expanded state
                      Text(
                        _isExpanded
                            ? "Portal access is granted and secured."
                            : "Tap to manage access & contact",
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // --- The Collapsible Content ---
            children: [
              // --- Descriptive Info Box ---
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.03)
                      : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark ? Colors.white10 : Colors.grey.shade200,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded, color: pColor, size: 18),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        "Manage application access, monitor login credentials, reset passwords, and initiate direct communications with the student's guardian.",
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white70 : Colors.grey.shade700,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // --- Premium Action Buttons ---
              Row(
                children: [
                  if (widget.dbParentPhone != null &&
                      widget.dbParentPhone!.isNotEmpty) ...[
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.green,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        onPressed: widget.onCallTap,
                        icon: const Icon(
                          Icons.phone_in_talk_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                        label: const Text(
                          "CALL",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    flex:
                        widget.dbParentPhone != null &&
                            widget.dbParentPhone!.isNotEmpty
                        ? 1
                        : 2,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: pColor,
                        side: BorderSide(
                          color: pColor.withValues(alpha: 0.3),
                          width: 1.5,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: widget.onSecurityTap,
                      icon: Icon(Icons.shield_rounded, color: pColor, size: 18),
                      label: const Text(
                        "SECURITY",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class StudentProfileScreen extends StatefulWidget {
  final String name;
  final String id;
  final String studentClass;
  final String? imagePath;
  final String? parentPhone;
  final String? parentEmail;

  const StudentProfileScreen({
    super.key,
    required this.name,
    required this.id,
    required this.studentClass,
    this.imagePath,
    this.parentPhone,
    this.parentEmail,
  });

  @override
  State<StudentProfileScreen> createState() => _StudentProfileScreenState();
}

class _StudentProfileScreenState extends State<StudentProfileScreen>
    with SingleTickerProviderStateMixin, AuthErrorHandler {
  final _supabase = Supabase.instance.client;
  late TabController _tabController;

  bool _isCheckingStatus = true;
  String? _admissionNo;
  String? _schoolId;

  String? _dbParentEmail;
  String? _dbParentPhone;

  bool _isFetchingAcademics = true;
  String _attendancePercentage = "N/A";
  String _gradeAverage = "N/A";
  List<Map<String, dynamic>> _subjectGrades = [];

  bool _isGeneratingRecord = false;

  bool _isEditing = false;
  bool _isSaving = false;
  final _firstNameController = TextEditingController();
  final _middleNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _dobController = TextEditingController();
  final _addressController = TextEditingController();

  String _selectedGender = "Male";
  String _selectedDepartment = "General";
  String _studentCategory = "Regular";

  String _currentNameDisplay = "";
  String? _currentImagePath;

  XFile? _pickedFile;
  Uint8List? _webImage;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _checkAccountStatus();
    _fetchAcademicData();
  }

  // ============================================================================
  // 🚨 LOGIC ENGINE
  // ============================================================================
  Future<void> _checkAccountStatus() async {
    try {
      final data = await _supabase
          .from('students')
          .select(
            'school_id, parent_account_created, admission_no, parent_email, parent_phone, first_name, middle_name, last_name, passport_url, dob, gender, department, category, address',
          )
          .eq('id', widget.id)
          .single();
      if (mounted) {
        setState(() {
          _schoolId = data['school_id'];
          _admissionNo = data['admission_no']?.toString();
          _dbParentEmail = data['parent_email']?.toString();
          _dbParentPhone = data['parent_phone']?.toString();
          _firstNameController.text = data['first_name'] ?? '';
          _middleNameController.text = data['middle_name'] ?? '';
          _lastNameController.text = data['last_name'] ?? '';
          _dobController.text = data['dob'] ?? '';
          _addressController.text = data['address'] ?? '';
          _selectedGender = data['gender'] ?? 'Male';
          _selectedDepartment = data['department'] ?? 'General';
          _studentCategory = data['category'] ?? 'Regular';
          _currentNameDisplay = widget.name;
          _currentImagePath = widget.imagePath ?? data['passport_url'];
          _isCheckingStatus = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isCheckingStatus = false);
    }
  }

  Future<void> _fetchAcademicData() async {
    try {
      final classAttRes = await _supabase
          .from('attendance')
          .select('date')
          .eq('class_level', widget.studentClass);
      int totalSchoolDays = classAttRes
          .map((r) => r['date'].toString())
          .toSet()
          .length;
      final stuAttRes = await _supabase
          .from('attendance')
          .select('status')
          .eq('student_id', widget.id);
      int presentCount = stuAttRes
          .where((r) => r['status'] == 'Punctual' || r['status'] == 'Late')
          .length;

      if (totalSchoolDays > 0) {
        _attendancePercentage =
            "${((presentCount / totalSchoolDays) * 100).toStringAsFixed(1)}% ($presentCount/$totalSchoolDays Days)";
      } else {
        _attendancePercentage = "No Class Records";
      }

      final scoresRes = await _supabase
          .from('exam_scores')
          .select('subject_name, total_score, grade')
          .eq('student_id', widget.id);
      if (scoresRes.isNotEmpty) {
        double totalSum = 0;
        List<Map<String, dynamic>> parsedGrades = [];
        for (var score in scoresRes) {
          double tot = (score['total_score'] as num?)?.toDouble() ?? 0.0;
          totalSum += tot;
          parsedGrades.add({
            'subject': score['subject_name'].toString(),
            'score': tot.toStringAsFixed(0),
            'grade': score['grade'].toString(),
          });
        }
        _gradeAverage = "${(totalSum / scoresRes.length).toStringAsFixed(1)}%";
        parsedGrades.sort((a, b) => a['subject'].compareTo(b['subject']));
        _subjectGrades = parsedGrades;
      }
      if (mounted) setState(() => _isFetchingAcademics = false);
    } catch (e) {
      if (mounted) setState(() => _isFetchingAcademics = false);
    }
  }

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
      maxWidth: 600,
      maxHeight: 600,
    );
    if (image != null) {
      final bytes = await image.readAsBytes();
      setState(() {
        _pickedFile = image;
        _webImage = bytes;
      });
    }
  }

  Future<void> _saveProfileChanges() async {
    if (_firstNameController.text.trim().isEmpty ||
        _lastNameController.text.trim().isEmpty) {
      showAuthErrorDialog("First Name and Surname cannot be empty.");
      return;
    }
    setState(() => _isSaving = true);
    try {
      String? newPassportUrl = _currentImagePath;
      if (_pickedFile != null && _webImage != null && _schoolId != null) {
        final fileExt = _pickedFile!.name.split('.').last;
        final fileName =
            '$_schoolId/${widget.id}_update_${DateTime.now().millisecondsSinceEpoch}.$fileExt';
        await _supabase.storage
            .from('student_passports')
            .uploadBinary(
              fileName,
              _webImage!,
              fileOptions: const FileOptions(upsert: true),
            );
        newPassportUrl = _supabase.storage
            .from('student_passports')
            .getPublicUrl(fileName);
      }
      await _supabase
          .from('students')
          .update({
            'first_name': _firstNameController.text.trim(),
            'middle_name': _middleNameController.text.trim(),
            'last_name': _lastNameController.text.trim(),
            'dob': _dobController.text.trim(),
            'gender': _selectedGender,
            'department': _selectedDepartment,
            'category': _studentCategory,
            'address': _addressController.text.trim(),
            'passport_url': newPassportUrl,
          })
          .eq('id', widget.id);
      String updatedName =
          "${_firstNameController.text.trim()} ${_middleNameController.text.trim()} ${_lastNameController.text.trim()}"
              .replaceAll('  ', ' ')
              .trim();
      if (mounted) {
        setState(() {
          _currentNameDisplay = updatedName;
          _currentImagePath = newPassportUrl;
          _isEditing = false;
        });
        showSuccessDialog(
          "Profile Updated",
          "Student biodata has been successfully updated.",
        );
      }
    } catch (e) {
      if (mounted) showAuthErrorDialog("Failed to update profile: $e");
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _generateComprehensiveRecord() async {
    setState(() => _isGeneratingRecord = true);
    try {
      final schoolData = await _supabase
          .from('schools')
          .select('name, address, logo_url')
          .eq('id', _schoolId!)
          .single();
      final termResults = await _supabase
          .from('term_results')
          .select()
          .eq('student_id', widget.id)
          .order('academic_session', ascending: false);

      pw.ImageProvider? logoProvider;
      if (schoolData['logo_url'] != null) {
        try {
          logoProvider = await networkImage(schoolData['logo_url']);
        } catch (_) {}
      }

      pw.ImageProvider? studentPhotoProvider;
      if (widget.imagePath != null && widget.imagePath!.startsWith('http')) {
        try {
          studentPhotoProvider = await networkImage(widget.imagePath!);
        } catch (_) {}
      }

      final pdf = pw.Document();
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (pw.Context context) => [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                if (logoProvider != null)
                  pw.Container(
                    width: 60,
                    height: 60,
                    child: pw.Image(logoProvider, fit: pw.BoxFit.contain),
                  )
                else
                  pw.SizedBox(width: 60, height: 60),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Text(
                        (schoolData['name'] ?? 'School').toUpperCase(),
                        style: pw.TextStyle(
                          fontSize: 20,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.blue900,
                        ),
                        textAlign: pw.TextAlign.center,
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        schoolData['address'] ?? '',
                        style: pw.TextStyle(
                          fontSize: 10,
                          color: PdfColors.grey700,
                        ),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(width: 60),
              ],
            ),
            pw.SizedBox(height: 15),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.symmetric(vertical: 8),
              decoration: pw.BoxDecoration(
                color: PdfColors.blue800,
                borderRadius: pw.BorderRadius.circular(5),
              ),
              child: pw.Text(
                "COMPREHENSIVE STUDENT DOSSIER",
                style: pw.TextStyle(
                  color: PdfColors.white,
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 14,
                ),
                textAlign: pw.TextAlign.center,
              ),
            ),
            pw.SizedBox(height: 20),
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400),
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Row(
                children: [
                  if (studentPhotoProvider != null)
                    pw.Container(
                      width: 50,
                      height: 50,
                      margin: const pw.EdgeInsets.only(right: 15),
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: PdfColors.grey400),
                        image: pw.DecorationImage(
                          image: studentPhotoProvider,
                          fit: pw.BoxFit.cover,
                        ),
                      ),
                    )
                  else
                    pw.Container(
                      width: 50,
                      height: 50,
                      margin: const pw.EdgeInsets.only(right: 15),
                      color: PdfColors.grey200,
                    ),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          "Name: ${widget.name.toUpperCase()}",
                          style: pw.TextStyle(
                            fontSize: 12,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          "Admission No: ${_admissionNo ?? 'N/A'}",
                          style: pw.TextStyle(fontSize: 11),
                        ),
                        pw.Text(
                          "Class: ${widget.studentClass}",
                          style: pw.TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 25),
            pw.Text(
              "ACADEMIC HISTORY",
              style: pw.TextStyle(
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.blue800,
              ),
            ),
            pw.SizedBox(height: 8),
            if (termResults.isEmpty)
              pw.Text(
                "No term results recorded yet.",
                style: pw.TextStyle(fontSize: 10, color: PdfColors.grey),
              )
            else
              pw.TableHelper.fromTextArray(
                headers: [
                  'Session',
                  'Term',
                  'Class',
                  'Average Score',
                  'Position',
                ],
                data: termResults
                    .map(
                      (r) => [
                        r['academic_session'] ?? '',
                        r['term'] ?? '',
                        r['class_level'] ?? '',
                        "${r['average_score'] ?? 0}%",
                        "${r['position'] ?? '-'}${r['position_suffix'] ?? ''}",
                      ],
                    )
                    .toList(),
                headerStyle: pw.TextStyle(
                  color: PdfColors.white,
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 10,
                ),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColors.blueGrey600,
                ),
                cellStyle: const pw.TextStyle(fontSize: 10),
              ),
          ],
        ),
      );

      final bytes = await pdf.save();
      if (mounted) {
        setState(() => _isGeneratingRecord = false);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => Scaffold(
              appBar: AppBar(title: const Text("Student Dossier")),
              body: PdfPreview(
                build: (format) => bytes,
                pdfFileName: "${widget.name.replaceAll(' ', '_')}_Dossier.pdf",
              ),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isGeneratingRecord = false);
        showAuthErrorDialog("Error generating dossier: $e");
      }
    }
  }

  // 🚨 ROUTES TO THE NEW EXTERNAL DIALOG FILE
  void _handleSecurityTap(Color primaryColor) {
    if (_dbParentEmail == null || _dbParentEmail!.isEmpty) {
      showAuthErrorDialog("Error: Missing login credentials in database.");
      return;
    }
    ParentSecurityDialogs.showCredentialPopup(
      context: context,
      targetLoginId: _dbParentEmail!,
      dbParentPhone: _dbParentPhone,
      createdPassword: "******** (Hidden for security)",
      primaryColor: primaryColor,
      supabase: _supabase,
      onError: showAuthErrorDialog,
      onSuccess: showSuccessDialog,
    );
  }

  Future<void> _deleteStudent(bool deleteAuth) async {
    try {
      await _supabase.from('students').delete().eq('id', widget.id);
      if (deleteAuth && _dbParentEmail != null) {
        try {
          await _supabase.functions.invoke(
            'manage-user-auth',
            body: {'action': 'delete', 'email': _dbParentEmail},
          );
        } catch (_) {}
      }
      if (mounted) {
        Navigator.pop(context);
        showSuccessDialog(
          "Student Removed",
          "${widget.name} has been successfully deleted from the system.",
          onOkay: () => Navigator.pop(context),
        );
      }
    } catch (e) {
      showAuthErrorDialog(
        "Record removal failed. This student may have active fee records attached.",
      );
    }
  }

  void _confirmDeletion(bool isDark) {
    bool shouldDeleteAuth = false;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            "Delete Record?",
            style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Are you sure you want to remove ${widget.name}? This action is permanent.",
              ),
              const SizedBox(height: 15),
              CheckboxListTile(
                title: const Text(
                  "Also remove parent login credentials?",
                  style: TextStyle(fontSize: 13),
                ),
                value: shouldDeleteAuth,
                onChanged: (v) => setS(() => shouldDeleteAuth = v!),
                activeColor: Colors.red,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("CANCEL", style: TextStyle(color: Colors.grey)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () => _deleteStudent(shouldDeleteAuth),
              child: const Text(
                "CONFIRM DELETE",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _callParent() async {
    if (_dbParentPhone == null) return;
    final Uri url = Uri(scheme: 'tel', path: _dbParentPhone!);
    if (await canLaunchUrl(url)) await launchUrl(url);
  }

  // ============================================================================
  // 🚨 MODULAR UI COMPOSITION WITH SIDE-BY-SIDE DESKTOP LOGIC
  // ============================================================================
  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC);
    Color cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    Color primaryColor = Theme.of(context).primaryColor;
    Color textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(
          _isEditing ? "Edit Profile" : "Student Profile",
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: bgColor,
        foregroundColor: textColor,
        elevation: 0,
        centerTitle: true,
        actions: [
          if (_isEditing)
            IconButton(
              icon: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: TridetaLoader(color: Colors.blue),
                    )
                  : const Icon(Icons.check_circle_outline, color: Colors.green),
              onPressed: _isSaving ? null : _saveProfileChanges,
            )
          else
            IconButton(
              icon: const Icon(Icons.edit_rounded, color: Colors.blue),
              onPressed: () => setState(() => _isEditing = true),
            ),
          if (!_isEditing)
            IconButton(
              icon: const Icon(
                Icons.delete_forever_rounded,
                color: Colors.redAccent,
              ),
              onPressed: () => _confirmDeletion(isDark),
            ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          bool isDesktop = constraints.maxWidth > 800;

          Widget mainContent = _isEditing
              ? ProfileEditForm(
                  webImage: _webImage,
                  displayImagePath: _currentImagePath ?? widget.imagePath ?? "",
                  onPickImage: _pickImage,
                  firstNameController: _firstNameController,
                  middleNameController: _middleNameController,
                  lastNameController: _lastNameController,
                  dobController: _dobController,
                  addressController: _addressController,
                  studentClass: widget.studentClass,
                  selectedGender: _selectedGender,
                  onGenderChanged: (v) => setState(() => _selectedGender = v),
                  selectedDepartment: _selectedDepartment,
                  onDepartmentChanged: (v) =>
                      setState(() => _selectedDepartment = v),
                  studentCategory: _studentCategory,
                  onCategoryChanged: (v) =>
                      setState(() => _studentCategory = v),
                  onDateTap: () async {
                    final DateTime? picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now().subtract(
                        const Duration(days: 365 * 3),
                      ),
                      firstDate: DateTime(1990),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) {
                      setState(
                        () => _dobController.text =
                            "${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}",
                      );
                    }
                  },
                  primaryColor: primaryColor,
                  cardColor: cardColor,
                  textColor: textColor,
                  isDark: isDark,
                )
              : Column(
                  children: [
                    if (isDesktop)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                        child: IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                flex: 5,
                                child: ProfileHeroHeader(
                                  id: widget.id,
                                  displayName: _currentNameDisplay.isEmpty
                                      ? widget.name
                                      : _currentNameDisplay,
                                  studentClass: widget.studentClass,
                                  admissionNo: _admissionNo,
                                  displayImagePath:
                                      _currentImagePath ??
                                      widget.imagePath ??
                                      "",
                                  primaryColor: primaryColor,
                                  cardColor: cardColor,
                                  isDark: isDark,
                                  isDesktop: true,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                flex: 4,
                                child: ParentSecurityCard(
                                  isCheckingStatus: _isCheckingStatus,
                                  dbParentPhone: _dbParentPhone,
                                  onSecurityTap: () =>
                                      _handleSecurityTap(primaryColor),
                                  onCallTap: _callParent,
                                  primaryColor: primaryColor,
                                  isDesktop: true,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      Column(
                        children: [
                          ProfileHeroHeader(
                            id: widget.id,
                            displayName: _currentNameDisplay.isEmpty
                                ? widget.name
                                : _currentNameDisplay,
                            studentClass: widget.studentClass,
                            admissionNo: _admissionNo,
                            displayImagePath:
                                _currentImagePath ?? widget.imagePath ?? "",
                            primaryColor: primaryColor,
                            cardColor: cardColor,
                            isDark: isDark,
                            isDesktop: false,
                          ),
                          ParentSecurityCard(
                            isCheckingStatus: _isCheckingStatus,
                            dbParentPhone: _dbParentPhone,
                            onSecurityTap: () =>
                                _handleSecurityTap(primaryColor),
                            onCallTap: _callParent,
                            primaryColor: primaryColor,
                            isDesktop: false,
                          ),
                        ],
                      ),

                    Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.05)
                            : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: TabBar(
                        controller: _tabController,
                        dividerColor: Colors.transparent,
                        indicatorSize: TabBarIndicatorSize.tab,
                        indicator: BoxDecoration(
                          color: primaryColor,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        labelColor: Colors.white,
                        unselectedLabelColor: isDark
                            ? Colors.white54
                            : Colors.grey.shade600,
                        labelStyle: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                        tabs: const [
                          Tab(text: "ACADEMICS"),
                          Tab(text: "RECORDS"),
                        ],
                      ),
                    ),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          ProfileAcademicTab(
                            isFetchingAcademics: _isFetchingAcademics,
                            attendancePercentage: _attendancePercentage,
                            gradeAverage: _gradeAverage,
                            subjectGrades: _subjectGrades,
                            primaryColor: primaryColor,
                            cardColor: cardColor,
                            textColor: textColor,
                            isDark: isDark,
                          ),
                          ProfileRecordsTab(
                            isGeneratingRecord: _isGeneratingRecord,
                            onGenerateTap: _generateComprehensiveRecord,
                            primaryColor: primaryColor,
                            cardColor: cardColor,
                            isDark: isDark,
                          ),
                        ],
                      ),
                    ),
                  ],
                );

          if (isDesktop) {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 850),
                child: Container(
                  decoration: BoxDecoration(
                    color: bgColor,
                    border: Border(
                      left: BorderSide(
                        color: isDark ? Colors.white10 : Colors.grey.shade200,
                        width: 1,
                      ),
                      right: BorderSide(
                        color: isDark ? Colors.white10 : Colors.grey.shade200,
                        width: 1,
                      ),
                    ),
                  ),
                  child: mainContent,
                ),
              ),
            );
          }
          return mainContent;
        },
      ),
    );
  }
}
