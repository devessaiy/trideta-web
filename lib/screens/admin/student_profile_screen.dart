import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:trideta_v2/utils/auth_error_handler.dart';
import 'package:trideta_v2/widgets/trideta_loader.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'package:pdf/pdf.dart' show PdfColor, PdfColors, PdfPageFormat;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'package:http/http.dart' as http;
import 'dart:ui' as ui;
import 'package:pro_image_editor/pro_image_editor.dart';

import 'package:trideta_v2/screens/admin/components/student_profile/profile_hero_header.dart';
import 'package:trideta_v2/screens/admin/components/student_profile/parent_security_dialogs.dart';
import 'package:trideta_v2/screens/admin/components/student_profile/profile_academic_tab.dart';
import 'package:trideta_v2/screens/admin/components/student_profile/profile_records_tab.dart';
import 'package:trideta_v2/screens/admin/components/student_profile/profile_edit_form.dart';

class ParentSecurityCard extends StatelessWidget {
  final bool isCheckingStatus;
  final String? dbParentPhone;
  final VoidCallback onSecurityTap;
  final VoidCallback onCallTap;
  final Color primaryColor;
  final bool isDesktop;
  final bool isDark;

  const ParentSecurityCard({
    super.key,
    required this.isCheckingStatus,
    this.dbParentPhone,
    required this.onSecurityTap,
    required this.onCallTap,
    required this.primaryColor,
    required this.isDesktop,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    if (isCheckingStatus) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (dbParentPhone != null && dbParentPhone!.isNotEmpty) ...[
          ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 8,
            ),
            leading: const Icon(
              Icons.phone_in_talk_rounded,
              color: Colors.green,
              size: 28,
            ),
            title: const Text(
              "Call Parent",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            subtitle: Text(
              dbParentPhone!,
              style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
            ),
            onTap: onCallTap,
          ),
          Padding(
            padding: const EdgeInsets.only(left: 72, right: 24),
            child: Divider(
              height: 1,
              color: isDark ? Colors.white10 : Colors.grey.shade200,
            ),
          ),
        ],
        ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 8,
          ),
          leading: Icon(Icons.shield_rounded, color: primaryColor, size: 28),
          title: const Text(
            "Parent App Security",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          subtitle: Text(
            "Manage portal access & passwords",
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
          ),
          trailing: Icon(
            Icons.chevron_right_rounded,
            color: Colors.grey.shade400,
          ),
          onTap: onSecurityTap,
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
  String? _classId;

  String? _dbParentEmail;
  String? _dbParentPhone;

  String _currentSession = "";
  String _currentTerm = "1st Term";
  double _walletBalance = 0.0;
  double _outstandingDebt = 0.0;

  bool _isFetchingAcademics = true;
  String _attendancePercentage = "N/A";
  String _gradeAverage = "N/A";
  List<Map<String, dynamic>> _subjectGrades = [];

  bool _isGeneratingRecord = false;

  bool _isEditing = false;
  bool _isSaving = false;
  bool _isInteractingWithSystem = false;

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
  }

  String _standardizeClass(String val) {
    String v = val.replaceAll(' ', '').toLowerCase();
    v = v
        .replaceAll('one', '1')
        .replaceAll('two', '2')
        .replaceAll('three', '3');
    v = v
        .replaceAll('four', '4')
        .replaceAll('five', '5')
        .replaceAll('six', '6');
    v = v
        .replaceAll('seven', '7')
        .replaceAll('eight', '8')
        .replaceAll('nine', '9');
    return v;
  }

  bool _doesItApply(
    dynamic columnData,
    String studentData, {
    bool isCategory = false,
  }) {
    String cleanStudentData = isCategory
        ? studentData.replaceAll(' ', '').toLowerCase()
        : _standardizeClass(studentData);
    if (isCategory &&
        (cleanStudentData.isEmpty || cleanStudentData == 'notfound')) {
      cleanStudentData = 'regular';
    }
    if (cleanStudentData.isEmpty || cleanStudentData == 'notfound') {
      return false;
    }
    if (columnData == null) return true;

    if (columnData is String && columnData.startsWith('[')) {
      try {
        List<dynamic> parsedList = jsonDecode(columnData);
        if (parsedList.isEmpty) return true;
        for (var item in parsedList) {
          String cleanItem = isCategory
              ? item.toString().replaceAll(' ', '').toLowerCase()
              : _standardizeClass(item.toString());
          if (cleanItem == 'all' || cleanItem == cleanStudentData) return true;
        }
        return false;
      } catch (e) {
        // Fallback
      }
    }

    String colStr = isCategory
        ? columnData.toString().replaceAll(' ', '').toLowerCase()
        : _standardizeClass(columnData.toString());
    if (colStr.isEmpty ||
        colStr == 'all' ||
        colStr == '[]' ||
        colStr == '["all"]') {
      return true;
    }
    return colStr.contains(cleanStudentData);
  }

  Future<void> _checkAccountStatus() async {
    try {
      final data = await _supabase
          .from('students')
          .select(
            'school_id, class_id, parent_account_created, admission_no, parent_email, parent_phone, first_name, middle_name, last_name, passport_url, dob, gender, department, category, address, wallet_balance, schools(current_session, current_term)',
          )
          .eq('id', widget.id)
          .single();

      if (mounted) {
        setState(() {
          _schoolId = data['school_id'];
          _classId = data['class_id'];
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
          _walletBalance = (data['wallet_balance'] ?? 0).toDouble();
          _currentNameDisplay = widget.name;
          _currentImagePath = widget.imagePath ?? data['passport_url'];

          if (data['schools'] != null) {
            _currentSession = data['schools']['current_session'] ?? "";
            _currentTerm = data['schools']['current_term'] ?? "1st Term";
          }

          _isCheckingStatus = false;
        });
      }

      await Future.wait([_fetchAcademicData(), _fetchFinancialData()]);
    } catch (e) {
      if (mounted) setState(() => _isCheckingStatus = false);
    }
  }

  Future<void> _fetchFinancialData() async {
    if (_schoolId == null || _currentSession.isEmpty) return;
    try {
      final feesData = await _supabase
          .from('fee_structures')
          .select()
          .eq('school_id', _schoolId!)
          .eq('academic_session', _currentSession);

      final txData = await _supabase
          .from('transactions')
          .select()
          .eq('student_id', widget.id)
          .eq('academic_session', _currentSession);

      double expected = 0;
      for (var fee in feesData) {
        if (_doesItApply(fee['applicable_class_ids'], _classId ?? '') ||
            _doesItApply(fee['applicable_classes'], widget.studentClass)) {
          if (_doesItApply(
            fee['applicable_categories'],
            _studentCategory,
            isCategory: true,
          )) {
            String fTerm = fee['academic_term'] ?? 'All Terms';
            if (fTerm == _currentTerm || fTerm == 'All Terms') {
              expected += (fee['amount'] ?? 0).toDouble();
            }
          }
        }
      }

      double paid = 0;
      for (var tx in txData) {
        String tTerm = tx['academic_term'] ?? 'All Terms';
        if (tTerm == _currentTerm ||
            tTerm == 'All Terms' ||
            _currentTerm == 'All Terms') {
          paid += (tx['amount'] ?? 0).toDouble();
        }
      }

      double termDebt = expected - paid;
      double finalDebt = termDebt - _walletBalance;

      if (mounted) {
        setState(() {
          _outstandingDebt = finalDebt > 0 ? finalDebt : 0.0;
        });
      }
    } catch (e) {
      debugPrint("Finance Error: $e");
    }
  }

  Future<void> _fetchAcademicData() async {
    if (_schoolId == null || _currentSession.isEmpty) return;
    try {
      final schoolAttRes = await _supabase
          .from('attendance')
          .select('date')
          .eq('school_id', _schoolId!)
          .eq('academic_session', _currentSession)
          .eq('term', _currentTerm);

      int totalSchoolDays = schoolAttRes
          .map((r) => r['date'].toString())
          .toSet()
          .length;

      final stuAttRes = await _supabase
          .from('attendance')
          .select('status')
          .eq('student_id', widget.id)
          .eq('academic_session', _currentSession)
          .eq('term', _currentTerm);

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
          .eq('student_id', widget.id)
          .eq('academic_session', _currentSession)
          .eq('term', _currentTerm);

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

  void _showImagePreview(String imageUrl) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          alignment: Alignment.center,
          children: [
            InteractiveViewer(
              child: Image.network(
                imageUrl,
                fit: BoxFit.contain,
                width: double.infinity,
                height: double.infinity,
              ),
            ),
            Positioned(
              top: 40,
              left: 20,
              child: IconButton(
                icon: const Icon(
                  Icons.arrow_back_rounded,
                  color: Colors.white,
                  size: 30,
                ),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
            Positioned(
              bottom: 40,
              child: Column(
                children: [
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white24,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () async {
                      final Uri url = Uri.parse(imageUrl);
                      if (await canLaunchUrl(url)) {
                        await launchUrl(
                          url,
                          mode: LaunchMode.externalApplication,
                        );
                      }
                    },
                    icon: const Icon(Icons.download_rounded),
                    label: const Text("SAVE TO DEVICE"),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await _pickImage();
                      if (_pickedFile != null) {
                        await _saveQuickPhotoChange();
                      }
                    },
                    icon: const Icon(Icons.edit_rounded),
                    label: const Text("CHANGE PHOTO"),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage() async {
    setState(() => _isInteractingWithSystem = true);

    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
        maxWidth: 1000,
        maxHeight: 1000,
      );

      if (image != null) {
        final bytes = await image.readAsBytes();
        if (!mounted) return;

        Uint8List imageToEdit = bytes;

        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) =>
              const Center(child: TridetaLoader(color: Colors.white)),
        );

        try {
          final request = http.MultipartRequest(
            'POST',
            Uri.parse('https://api.remove.bg/v1.0/removebg'),
          );

          request.headers['X-Api-Key'] = 'xDZscf4d861ip44UcfKRuaYN';
          request.files.add(
            http.MultipartFile.fromBytes(
              'image_file',
              bytes,
              filename: 'upload.jpg',
            ),
          );

          final response = await request.send();

          if (response.statusCode == 200) {
            final transparentBytes = await response.stream.toBytes();

            final codec = await ui.instantiateImageCodec(transparentBytes);
            final frame = await codec.getNextFrame();
            final ui.Image aiImage = frame.image;

            final ui.PictureRecorder recorder = ui.PictureRecorder();
            final ui.Canvas canvas = ui.Canvas(recorder);

            final ui.Paint paint = ui.Paint()
              ..color = Theme.of(context).primaryColor;
            final Rect rect = Rect.fromLTWH(
              0,
              0,
              aiImage.width.toDouble(),
              aiImage.height.toDouble(),
            );
            canvas.drawRect(rect, paint);
            canvas.drawImage(aiImage, Offset.zero, ui.Paint());

            final ui.Picture picture = recorder.endRecording();
            final ui.Image mergedImage = await picture.toImage(
              aiImage.width,
              aiImage.height,
            );
            final ByteData? byteData = await mergedImage.toByteData(
              format: ui.ImageByteFormat.png,
            );

            imageToEdit = byteData!.buffer.asUint8List();
          } else {
            debugPrint("Cloud API Failed. Status: ${response.statusCode}");
          }
        } catch (error) {
          debugPrint("Background Removal Skipped (Network Error): $error");
        }

        if (mounted) Navigator.pop(context);

        bool hasPopped = false;

        final Uint8List? editedBytes = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (editorContext) => ProImageEditor.memory(
              imageToEdit,
              callbacks: ProImageEditorCallbacks(
                onImageEditingComplete: (Uint8List result) async {
                  if (!hasPopped) {
                    hasPopped = true;
                    Navigator.pop(editorContext, result);
                  }
                },
                onCloseEditor: (mode) {
                  if (!hasPopped) {
                    hasPopped = true;
                    Navigator.pop(editorContext, null);
                  }
                },
              ),
            ),
          ),
        );

        if (editedBytes != null) {
          if (editedBytes.lengthInBytes > 500 * 1024) {
            showAuthErrorDialog(
              "Image is too large. Please choose a simpler photo.",
            );
            return;
          }
          setState(() {
            _pickedFile = image;
            _webImage = editedBytes;
          });
        }
      }
    } catch (e) {
      debugPrint("Image Picker Error: $e");
    } finally {
      if (mounted) setState(() => _isInteractingWithSystem = false);
    }
  }

  Future<void> _saveQuickPhotoChange() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: TridetaLoader(color: Colors.white)),
    );
    try {
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
        String newPassportUrl = _supabase.storage
            .from('student_passports')
            .getPublicUrl(fileName);

        await _supabase
            .from('students')
            .update({'passport_url': newPassportUrl})
            .eq('id', widget.id);

        if (mounted) {
          setState(() {
            _currentImagePath = newPassportUrl;
          });
          Navigator.pop(context);
          showSuccessDialog(
            "Photo Updated",
            "Student profile picture has been successfully updated.",
          );
        }
      } else {
        if (mounted) Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        showAuthErrorDialog("Failed to update photo: $e");
      }
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

  // 🚨 UI FIX: Security check added to require typing "CONFIRM"
  void _confirmDeletion(bool isDark) {
    bool shouldDeleteAuth = false;
    String confirmText = "";

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Row(
            children: [
              Icon(Icons.person_off_rounded, color: Colors.red),
              SizedBox(width: 10),
              Text(
                "Delete Record?",
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Are you sure you want to remove ${widget.name}? This action is permanent.",
              ),
              const SizedBox(height: 15),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  "Also remove parent login credentials?",
                  style: TextStyle(fontSize: 13),
                ),
                value: shouldDeleteAuth,
                onChanged: (v) => setS(() => shouldDeleteAuth = v!),
                activeColor: Colors.red,
              ),
              const SizedBox(height: 15),
              TextField(
                onChanged: (val) => setS(() => confirmText = val),
                decoration: InputDecoration(
                  labelText: "Type CONFIRM to continue",
                  labelStyle: TextStyle(color: Colors.red.shade300),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.red, width: 2),
                  ),
                ),
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
              onPressed: confirmText == "CONFIRM"
                  ? () {
                      Navigator.pop(ctx);
                      _deleteStudent(shouldDeleteAuth);
                    }
                  : null,
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

  // 🚨 UI FIX: Flattened into pure WhatsApp ListTiles
  Widget _buildFinancialCard(bool isDark, Color primaryColor) {
    if (_isCheckingStatus) return const SizedBox.shrink();

    final currencyFmt = NumberFormat.currency(symbol: '₦', decimalDigits: 0);

    return Column(
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 4,
          ),
          leading: const Icon(
            Icons.account_balance_wallet_rounded,
            color: Colors.blue,
            size: 28,
          ),
          title: const Text(
            "Wallet Balance",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          subtitle: Text(
            "Available credit",
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
          ),
          trailing: Text(
            currencyFmt.format(_walletBalance),
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              color: Colors.blue,
              fontSize: 16,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 72, right: 24),
          child: Divider(
            height: 1,
            color: isDark ? Colors.white10 : Colors.grey.shade200,
          ),
        ),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 4,
          ),
          leading: Icon(
            _outstandingDebt > 0
                ? Icons.warning_rounded
                : Icons.check_circle_rounded,
            color: _outstandingDebt > 0 ? Colors.redAccent : Colors.green,
            size: 28,
          ),
          title: const Text(
            "Outstanding Debt",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          subtitle: Text(
            "For $_currentTerm",
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
          ),
          trailing: Text(
            currencyFmt.format(_outstandingDebt),
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: _outstandingDebt > 0 ? Colors.redAccent : Colors.green,
              fontSize: 16,
            ),
          ),
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

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color primaryColor = Theme.of(context).primaryColor;

    // 🚨 UI FIX: Pure Material Matte Backgrounds globally forced
    Color bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC);
    Color textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(
          _isEditing ? "Edit Profile" : "Student Info",
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
          // 🚨 UI FIX: Delete icon removed from Top App Bar (moved to bottom)
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          bool isDesktop = constraints.maxWidth > 800;

          if (_isEditing) {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 850),
                child: ProfileEditForm(
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
                  cardColor: bgColor,
                  textColor: textColor,
                  isDark: isDark,
                ),
              ),
            );
          }

          if (isDesktop) {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 850),
                child: Column(
                  children: [
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
                                    _currentImagePath ?? widget.imagePath ?? "",
                                primaryColor: primaryColor,
                                cardColor: bgColor,
                                isDark: isDark,
                                isDesktop: true,
                                onImageTap: () {
                                  if (_currentImagePath != null &&
                                      _currentImagePath!.startsWith('http')) {
                                    _showImagePreview(_currentImagePath!);
                                  } else if (widget.imagePath != null &&
                                      widget.imagePath!.startsWith('http')) {
                                    _showImagePreview(widget.imagePath!);
                                  } else {
                                    _pickImage().then((_) {
                                      if (_pickedFile != null) {
                                        _saveQuickPhotoChange();
                                      }
                                    });
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              flex: 4,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _buildFinancialCard(isDark, primaryColor),
                                  ParentSecurityCard(
                                    isCheckingStatus: _isCheckingStatus,
                                    dbParentPhone: _dbParentPhone,
                                    onSecurityTap: () =>
                                        _handleSecurityTap(primaryColor),
                                    onCallTap: _callParent,
                                    primaryColor: primaryColor,
                                    isDesktop: true,
                                    isDark: isDark,
                                  ),
                                  // 🚨 UI FIX: WhatsApp Delete Tile (Desktop Column)
                                  InkWell(
                                    onTap: () => _confirmDeletion(isDark),
                                    child: const ListTile(
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: 24,
                                        vertical: 12,
                                      ),
                                      leading: Icon(
                                        Icons.delete_outline_rounded,
                                        color: Colors.red,
                                        size: 28,
                                      ),
                                      title: Text(
                                        "Remove Student",
                                        style: TextStyle(
                                          color: Colors.red,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 8,
                      ),
                      child: TabBar(
                        controller: _tabController,
                        indicatorColor: primaryColor,
                        indicatorWeight: 3,
                        labelColor: primaryColor,
                        unselectedLabelColor: Colors.grey,
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
                            cardColor: bgColor,
                            textColor: textColor,
                            isDark: isDark,
                          ),
                          ProfileRecordsTab(
                            isGeneratingRecord: _isGeneratingRecord,
                            onGenerateTap: _generateComprehensiveRecord,
                            primaryColor: primaryColor,
                            cardColor: bgColor,
                            isDark: isDark,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) {
              return [
                SliverToBoxAdapter(
                  child: Column(
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
                        cardColor: bgColor,
                        isDark: isDark,
                        isDesktop: false,
                        onImageTap: () {
                          if (_currentImagePath != null &&
                              _currentImagePath!.startsWith('http')) {
                            _showImagePreview(_currentImagePath!);
                          } else if (widget.imagePath != null &&
                              widget.imagePath!.startsWith('http')) {
                            _showImagePreview(widget.imagePath!);
                          } else {
                            _pickImage().then((_) {
                              if (_pickedFile != null) _saveQuickPhotoChange();
                            });
                          }
                        },
                      ),
                      // 🚨 UI FIX: Removed thick 12px divider blocks
                      _buildFinancialCard(isDark, primaryColor),
                      ParentSecurityCard(
                        isCheckingStatus: _isCheckingStatus,
                        dbParentPhone: _dbParentPhone,
                        onSecurityTap: () => _handleSecurityTap(primaryColor),
                        onCallTap: _callParent,
                        primaryColor: primaryColor,
                        isDesktop: false,
                        isDark: isDark,
                      ),
                      // 🚨 UI FIX: WhatsApp Delete Tile securely appended to the bottom
                      InkWell(
                        onTap: () => _confirmDeletion(isDark),
                        child: const ListTile(
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                          leading: Icon(
                            Icons.delete_outline_rounded,
                            color: Colors.red,
                            size: 28,
                          ),
                          title: Text(
                            "Remove Student",
                            style: TextStyle(
                              color: Colors.red,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _SliverAppBarDelegate(
                    TabBar(
                      controller: _tabController,
                      indicatorColor: primaryColor,
                      indicatorWeight: 3,
                      labelColor: primaryColor,
                      unselectedLabelColor: Colors.grey,
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
                ),
              ];
            },
            body: TabBarView(
              controller: _tabController,
              children: [
                ProfileAcademicTab(
                  isFetchingAcademics: _isFetchingAcademics,
                  attendancePercentage: _attendancePercentage,
                  gradeAverage: _gradeAverage,
                  subjectGrades: _subjectGrades,
                  primaryColor: primaryColor,
                  cardColor: bgColor,
                  textColor: textColor,
                  isDark: isDark,
                ),
                ProfileRecordsTab(
                  isGeneratingRecord: _isGeneratingRecord,
                  onGenerateTap: _generateComprehensiveRecord,
                  primaryColor: primaryColor,
                  cardColor: bgColor,
                  isDark: isDark,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  _SliverAppBarDelegate(this._tabBar);

  final TabBar _tabBar;

  @override
  double get minExtent => _tabBar.preferredSize.height;
  @override
  double get maxExtent => _tabBar.preferredSize.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC);

    return Container(color: bgColor, child: _tabBar);
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) {
    return false;
  }
}
