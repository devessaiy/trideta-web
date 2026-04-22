import 'package:trideta_v2/utils/auth_error_handler.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';

// 🚨 PDF PACKAGES FOR DOSSIER GENERATION
import 'package:pdf/pdf.dart' show PdfColor, PdfColors, PdfPageFormat;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

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

  // --- STATE VARIABLES ---
  bool _accountExists = false;
  bool _isCheckingStatus = true;
  bool _isCreatingAccount = false;
  String? _admissionNo;
  String? _schoolId;

  String? _dbParentEmail;
  String? _dbParentPhone;

  // --- ACADEMIC STATE VARIABLES ---
  bool _isFetchingAcademics = true;
  String _attendancePercentage = "N/A";
  String _gradeAverage = "N/A";
  List<Map<String, dynamic>> _subjectGrades = [];

  // --- PDF GENERATOR STATE ---
  bool _isGeneratingRecord = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _checkAccountStatus();
    _fetchAcademicData();
  }

  Future<void> _checkAccountStatus() async {
    try {
      final data = await _supabase
          .from('students')
          .select(
            'school_id, parent_account_created, admission_no, parent_email, parent_phone',
          )
          .eq('id', widget.id)
          .single();

      if (mounted) {
        setState(() {
          _schoolId = data['school_id'];
          _accountExists = data['parent_account_created'] == true;
          _admissionNo = data['admission_no']?.toString();
          _dbParentEmail = data['parent_email']?.toString();
          _dbParentPhone = data['parent_phone']?.toString();
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

      final uniqueDates = classAttRes.map((r) => r['date'].toString()).toSet();
      int totalSchoolDays = uniqueDates.length;

      final stuAttRes = await _supabase
          .from('attendance')
          .select('status')
          .eq('student_id', widget.id);

      int presentCount = stuAttRes
          .where((r) => r['status'] == 'Punctual' || r['status'] == 'Late')
          .length;

      if (totalSchoolDays > 0) {
        double attPct = (presentCount / totalSchoolDays) * 100;
        _attendancePercentage =
            "${attPct.toStringAsFixed(1)}% ($presentCount/$totalSchoolDays Days)";
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

        double avg = totalSum / scoresRes.length;
        _gradeAverage = "${avg.toStringAsFixed(1)}%";

        parsedGrades.sort((a, b) => a['subject'].compareTo(b['subject']));
        _subjectGrades = parsedGrades;
      }

      if (mounted) {
        setState(() => _isFetchingAcademics = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isFetchingAcademics = false);
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
      final attendanceData = await _supabase
          .from('attendance')
          .select('status')
          .eq('student_id', widget.id);

      List<dynamic> financeData = [];
      try {
        financeData = await _supabase
            .from('fee_payments')
            .select()
            .eq('student_id', widget.id)
            .order('payment_date', ascending: false);
      } catch (_) {}

      int punctual = attendanceData
          .where((r) => r['status'] == 'Punctual')
          .length;
      int late = attendanceData.where((r) => r['status'] == 'Late').length;
      int absent = attendanceData.where((r) => r['status'] == 'Absent').length;
      int sick = attendanceData.where((r) => r['status'] == 'Sick').length;

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

  // ============================================================================
  // 🚨 STREAMLINED ACCOUNT VIEW & RESET LOGIC
  // ============================================================================

  void _handleActiveAccountTap(Color primaryColor) {
    // Because the actual Login ID is ALWAYS saved in _dbParentEmail
    // (whether it's a real email or a phantom phone email), we no longer
    // need to ask the Admin to choose. We just pop the credentials straight up!

    if (_dbParentEmail == null || _dbParentEmail!.isEmpty) {
      showAuthErrorDialog("Error: Missing login credentials in database.");
      return;
    }

    _showCredentialPopup(primaryColor, "******** (Hidden for security)");
  }

  // Dialog for ACTIVATING OLD legacy accounts (Orange Card)
  void _showLoginMethodDialog() {
    Color primaryColor = Theme.of(context).primaryColor;
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          "Select Login Method",
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: const Text(
          "How should this parent log into the app?",
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.phone),
                label: Text("Use Phone: ${_dbParentPhone ?? 'N/A'}"),
                onPressed: () {
                  Navigator.pop(ctx);
                  _showActivationPasswordDialog(true);
                },
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: primaryColor,
                  side: BorderSide(color: primaryColor),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.email),
                label: Text("Use Email: ${_dbParentEmail ?? 'N/A'}"),
                onPressed: () {
                  Navigator.pop(ctx);
                  _showActivationPasswordDialog(false);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showActivationPasswordDialog(bool usePhoneChoice) {
    final pwdController = TextEditingController();
    final confirmController = TextEditingController();
    bool isObscure1 = true;
    bool isObscure2 = true;
    String pwdStrength = "";
    Color strengthColor = Colors.transparent;
    String matchStatus = "";
    Color matchColor = Colors.transparent;

    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color primaryColor = Theme.of(context).primaryColor;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          void checkStrength(String val) {
            if (val.isEmpty) {
              setDialogState(() {
                pwdStrength = "";
                matchStatus = "";
              });
              return;
            }
            bool hasLetters = RegExp(r'[a-zA-Z]').hasMatch(val);
            bool hasNumbers = RegExp(r'[0-9]').hasMatch(val);
            if (val.length < 6) {
              pwdStrength = "Too short";
              strengthColor = Colors.red;
            } else if (!hasLetters || !hasNumbers) {
              pwdStrength = "Weak";
              strengthColor = Colors.orange;
            } else {
              pwdStrength = "Good Password";
              strengthColor = primaryColor;
            }
            if (confirmController.text.isNotEmpty) {
              if (confirmController.text == val) {
                matchStatus = "Passwords match";
                matchColor = Colors.green;
              } else {
                matchStatus = "Passwords do not match";
                matchColor = Colors.red;
              }
            }
            setDialogState(() {});
          }

          void checkMatch(String val) {
            if (val.isEmpty) {
              setDialogState(() => matchStatus = "");
              return;
            }
            if (val == pwdController.text) {
              matchStatus = "Passwords match";
              matchColor = Colors.green;
            } else {
              matchStatus = "Passwords do not match";
              matchColor = Colors.red;
            }
            setDialogState(() {});
          }

          return AlertDialog(
            backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Text(
              "Create Parent Password",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Set a secure login password to activate this parent account.",
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: pwdController,
                    obscureText: isObscure1,
                    onChanged: checkStrength,
                    decoration: InputDecoration(
                      labelText: "New Password",
                      prefixIcon: Icon(
                        Icons.lock_outline,
                        color: primaryColor,
                        size: 20,
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          isObscure1 ? Icons.visibility : Icons.visibility_off,
                          size: 20,
                        ),
                        onPressed: () =>
                            setDialogState(() => isObscure1 = !isObscure1),
                      ),
                      filled: true,
                      fillColor: isDark ? Colors.white10 : Colors.grey[50],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  if (pwdStrength.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0, left: 10.0),
                      child: Text(
                        pwdStrength,
                        style: TextStyle(
                          color: strengthColor,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: confirmController,
                    obscureText: isObscure2,
                    onChanged: checkMatch,
                    decoration: InputDecoration(
                      labelText: "Confirm Password",
                      prefixIcon: Icon(
                        Icons.lock_reset,
                        color: primaryColor,
                        size: 20,
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          isObscure2 ? Icons.visibility : Icons.visibility_off,
                          size: 20,
                        ),
                        onPressed: () =>
                            setDialogState(() => isObscure2 = !isObscure2),
                      ),
                      filled: true,
                      fillColor: isDark ? Colors.white10 : Colors.grey[50],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  if (matchStatus.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0, left: 10.0),
                      child: Text(
                        matchStatus,
                        style: TextStyle(
                          color: matchColor,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text(
                  "Cancel",
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () async {
                  if (pwdController.text.length < 6 ||
                      !RegExp(r'[a-zA-Z]').hasMatch(pwdController.text) ||
                      !RegExp(r'[0-9]').hasMatch(pwdController.text)) {
                    showAuthErrorDialog(
                      "Password is too weak. Needs at least 6 characters, letters and numbers.",
                    );
                    return;
                  }
                  if (pwdController.text != confirmController.text) {
                    showAuthErrorDialog("Passwords do not match.");
                    return;
                  }
                  Navigator.pop(ctx);
                  _processActivation(pwdController.text, usePhoneChoice);
                },
                child: const Text(
                  "ACTIVATE",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _activateParentAccount() async {
    if ((_dbParentEmail == null || _dbParentEmail!.isEmpty) &&
        (_dbParentPhone == null || _dbParentPhone!.isEmpty)) {
      showAuthErrorDialog(
        "We can't activate this account because both the email and phone number are missing in the database.",
      );
      return;
    }
    bool hasEmail = _dbParentEmail != null && _dbParentEmail!.isNotEmpty;
    bool hasPhone = _dbParentPhone != null && _dbParentPhone!.isNotEmpty;

    // For older students who might have both fields but aren't activated yet
    if (hasEmail && hasPhone) {
      _showLoginMethodDialog();
    } else if (hasPhone) {
      _showActivationPasswordDialog(true);
    } else {
      _showActivationPasswordDialog(false);
    }
  }

  Future<void> _processActivation(
    String generatedPassword,
    bool usePhoneChoice,
  ) async {
    setState(() => _isCreatingAccount = true);

    try {
      // 1. Calculate the exact Login ID string that will be sent to Auth
      String exactLoginId = _dbParentEmail ?? '';

      if (usePhoneChoice && _dbParentPhone != null) {
        String phonePart = _dbParentPhone!.replaceAll(' ', '');
        if (phonePart.startsWith('0')) {
          phonePart = '+234${phonePart.substring(1)}';
        } else if (!phonePart.startsWith('+')) {
          phonePart = '+234$phonePart';
        }
        exactLoginId = '$phonePart@trideta.com';
      }

      // 2. Tell Edge Function to create the account
      await _supabase.functions.invoke(
        'create-parent-account',
        body: {
          'email': _dbParentEmail ?? '',
          'password': generatedPassword,
          'phone': _dbParentPhone ?? '',
          'studentName': widget.name,
          'usePhoneForLogin': usePhoneChoice,
        },
      );

      // 3. Update the database to permanently store the EXACT Login ID in the email column
      await _supabase
          .from('students')
          .update({
            'parent_account_created': true,
            'parent_email': exactLoginId, // Overwrites the old wrong email!
          })
          .eq('id', widget.id);

      if (mounted) {
        setState(() {
          _accountExists = true;
          _dbParentEmail = exactLoginId; // Instantly updates the UI's memory
        });
        _showCredentialPopup(Theme.of(context).primaryColor, generatedPassword);
      }
    } catch (e) {
      if (mounted) {
        showAuthErrorDialog("Activation Error: ${e.toString()}");
      }
    } finally {
      if (mounted) setState(() => _isCreatingAccount = false);
    }
  }

  // --- LOGIN CREDENTIALS POPUP ---
  void _showCredentialPopup(Color primaryColor, String createdPassword) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    // Because we updated the DB rules, the Email column IS ALWAYS the exact target ID!
    String targetLoginId = _dbParentEmail ?? "N/A";

    // Clean up the display for the Admin so they don't see @trideta.com if it's a phone
    String displayedId = targetLoginId;
    if (displayedId.contains('@trideta.com')) {
      displayedId = displayedId.replaceAll('@trideta.com', '');
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Column(
          children: [
            const Icon(
              Icons.verified_user_rounded,
              color: Colors.green,
              size: 50,
            ),
            const SizedBox(height: 10),
            Text(
              "Parent Account Active",
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Provide these credentials to the parent for app login:",
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            _credentialCard(
              "User ID / Login",
              displayedId,
              isDark,
              primaryColor,
            ),
            _credentialCard("Password", createdPassword, isDark, primaryColor),
          ],
        ),
        actions: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: () => Navigator.pop(ctx),
                child: const Text(
                  "GOT IT",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // 🚨 The Reset Password Button
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                icon: const Icon(Icons.lock_reset, size: 18),
                label: const Text(
                  "Force Password Reset",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  _showAdminResetPasswordDialog(
                    targetLoginId,
                  ); // Sends the exact phantom email directly!
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 🚨 The dialog where the Admin types the new temporary password
  void _showAdminResetPasswordDialog(String targetLoginId) {
    final pwdController = TextEditingController();
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    bool isLoading = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Text(
              "Reset Parent Password",
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "Enter a new temporary password for this parent. They can change it later in their app settings.",
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: pwdController,
                  decoration: InputDecoration(
                    labelText: "New Temporary Password",
                    prefixIcon: const Icon(Icons.lock_reset, color: Colors.red),
                    filled: true,
                    fillColor: isDark ? Colors.white10 : Colors.grey[50],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text(
                  "CANCEL",
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: isLoading
                    ? null
                    : () async {
                        if (pwdController.text.length < 6) {
                          showAuthErrorDialog(
                            "Password must be at least 6 characters.",
                          );
                          return;
                        }

                        setDialogState(() => isLoading = true);
                        try {
                          // Call the Edge Function with the EXACT target ID
                          final response = await _supabase.functions.invoke(
                            'reset-parent-password',
                            body: {
                              'email': targetLoginId,
                              'newPassword': pwdController.text,
                            },
                          );

                          // 🚨 NEW: Check if the Edge Function sent back an error inside the 200 OK response
                          if (response.data != null &&
                              response.data['error'] != null) {
                            setDialogState(() => isLoading = false);
                            showAuthErrorDialog(
                              "Reset Failed: ${response.data['error']}",
                            );
                            return;
                          }

                          if (mounted) {
                            Navigator.pop(ctx);
                            showSuccessDialog(
                              "Password Reset",
                              "The parent's password has been successfully changed to: \n\n${pwdController.text}",
                            );
                          }
                        } catch (e) {
                          setDialogState(() => isLoading = false);
                          showAuthErrorDialog("App Error: ${e.toString()}");
                        }
                      },
                child: isLoading
                    ? const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        "RESET",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _credentialCard(
    String label,
    String value,
    bool isDark,
    Color primaryColor,
  ) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: primaryColor.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 10,
              color: Colors.grey,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
        ],
      ),
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

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC);
    Color cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    Color primaryColor = Theme.of(context).primaryColor;

    Widget mainContent = Column(
      children: [
        _buildHeroHeader(cardColor, isDark, primaryColor),
        _buildActivationBar(isDark),
        Container(
          color: cardColor,
          child: TabBar(
            controller: _tabController,
            labelColor: primaryColor,
            unselectedLabelColor: Colors.grey,
            indicatorColor: primaryColor,
            indicatorWeight: 3,
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
              _buildAcademicTab(isDark, primaryColor),
              _buildRecordsTab(isDark, primaryColor),
            ],
          ),
        ),
      ],
    );

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text(
          "Student Profile",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_forever_rounded),
            onPressed: () => _confirmDeletion(isDark),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth > 800) {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
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
          } else {
            return mainContent;
          }
        },
      ),
    );
  }

  Widget _buildHeroHeader(Color cardColor, bool isDark, Color primaryColor) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10),
        ],
      ),
      child: Row(
        children: [
          Hero(
            tag: widget.id,
            child: CircleAvatar(
              radius: 45,
              backgroundColor: primaryColor.withOpacity(0.1),
              backgroundImage:
                  (widget.imagePath != null && widget.imagePath!.isNotEmpty)
                  ? (widget.imagePath!.startsWith('http')
                        ? NetworkImage(widget.imagePath!)
                        : FileImage(File(widget.imagePath!)) as ImageProvider)
                  : null,
              child: (widget.imagePath == null || widget.imagePath!.isEmpty)
                  ? Icon(Icons.person_rounded, size: 40, color: primaryColor)
                  : null,
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.name,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 5),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    widget.studentClass,
                    style: TextStyle(
                      color: primaryColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _admissionNo != null
                      ? "Admission No: $_admissionNo"
                      : "Fetching Details...",
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivationBar(bool isDark) {
    if (_isCheckingStatus) return const LinearProgressIndicator(minHeight: 2);
    Color primaryColor = Theme.of(context).primaryColor;
    return GestureDetector(
      onTap: _accountExists
          ? () => _handleActiveAccountTap(primaryColor)
          : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: _accountExists
              ? Colors.green.withOpacity(0.1)
              : Colors.orange.withOpacity(0.1),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: _accountExists
                ? Colors.green.withOpacity(0.3)
                : Colors.orange.withOpacity(0.3),
          ),
        ),
        child: Row(
          children: [
            Icon(
              _accountExists
                  ? Icons.verified_user_rounded
                  : Icons.warning_amber_rounded,
              color: _accountExists ? Colors.green : Colors.orange,
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _accountExists
                        ? "Parent Account Active"
                        : "Parent Account Inactive",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    _accountExists
                        ? "Tap to view login details."
                        : "Activate parent login for app access.",
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            if (!_accountExists)
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange[800],
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: _isCreatingAccount ? null : _activateParentAccount,
                child: _isCreatingAccount
                    ? const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        "ACTIVATE",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
              ),
            if (_accountExists)
              IconButton(
                icon: const Icon(Icons.call_rounded, color: Colors.green),
                onPressed: _callParent,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAcademicTab(bool isDark, Color primaryColor) {
    if (_isFetchingAcademics)
      return Center(child: CircularProgressIndicator(color: primaryColor));
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
      children: [
        _buildStatCard(
          "Attendance",
          _attendancePercentage,
          Icons.calendar_month,
          Colors.blue,
        ),
        const SizedBox(height: 15),
        _buildStatCard(
          "Grade Average",
          _gradeAverage,
          Icons.auto_graph_rounded,
          Colors.purple,
        ),
        const SizedBox(height: 25),
        const Text(
          "SUBJECT GRADES",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12,
            color: Colors.grey,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        if (_subjectGrades.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 20),
            child: Center(
              child: Text(
                "No scores recorded yet.",
                style: TextStyle(color: Colors.grey),
              ),
            ),
          )
        else
          ..._subjectGrades.map((gradeData) {
            Color gColor = Colors.grey;
            if (gradeData['grade'] == 'A') gColor = Colors.green;
            if (gradeData['grade'] == 'B') gColor = Colors.blue;
            if (gradeData['grade'] == 'C') gColor = Colors.orange;
            if (gradeData['grade'] == 'P') gColor = Colors.purple;
            if (gradeData['grade'] == 'F') gColor = Colors.red;
            return _buildGradeTile(
              gradeData['subject'],
              "${gradeData['score']} (${gradeData['grade']})",
              gColor,
            );
          }).toList(),
      ],
    );
  }

  Widget _buildRecordsTab(bool isDark, Color primaryColor) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 100),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.assignment_ind_rounded,
            size: 70,
            color: primaryColor.withOpacity(0.3),
          ),
          const SizedBox(height: 20),
          const Text(
            "Comprehensive Student Dossier",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          const Text(
            "Generate a complete, printable PDF record including this student's historic term results, attendance records, and financial statements.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, height: 1.5),
          ),
          const SizedBox(height: 40),
          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                elevation: 0,
              ),
              onPressed: _isGeneratingRecord
                  ? null
                  : _generateComprehensiveRecord,
              icon: _isGeneratingRecord
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(
                      Icons.picture_as_pdf_rounded,
                      color: Colors.white,
                    ),
              label: Text(
                _isGeneratingRecord
                    ? "PACKAGING FILES..."
                    : "GENERATE FULL RECORD",
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String val, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey.withOpacity(0.1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 15),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
          Text(
            val,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGradeTile(String name, String score, Color color) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w500)),
      trailing: Text(
        score,
        style: TextStyle(fontWeight: FontWeight.bold, color: color),
      ),
    );
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
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("CANCEL"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => _deleteStudent(shouldDeleteAuth),
              child: const Text(
                "CONFIRM DELETE",
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _callParent() async {
    if (_dbParentPhone == null) return;
    final Uri url = Uri(scheme: 'tel', path: _dbParentPhone);
    if (await canLaunchUrl(url)) await launchUrl(url);
  }
}
