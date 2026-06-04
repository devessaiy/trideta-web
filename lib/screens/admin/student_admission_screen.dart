import 'dart:async';
import 'package:trideta_v2/utils/auth_error_handler.dart';
import 'package:trideta_v2/widgets/trideta_loader.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:trideta_v2/main.dart';
import 'package:trideta_v2/screens/admin/school_configuration_screen.dart';

class StudentAdmissionScreen extends StatefulWidget {
  const StudentAdmissionScreen({super.key});

  @override
  State<StudentAdmissionScreen> createState() => _StudentAdmissionScreenState();
}

class _StudentAdmissionScreenState extends State<StudentAdmissionScreen>
    with AuthErrorHandler {
  final _formKey = GlobalKey<FormState>();
  final _supabase = Supabase.instance.client;

  // --- CONTROLLERS ---
  final _firstNameController = TextEditingController();
  final _middleNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _dobController = TextEditingController();
  final _parentNameController = TextEditingController();
  final _parentEmailController = TextEditingController();

  final _loginPhoneController = TextEditingController();
  final _parentPhoneController = TextEditingController();

  final _addressController = TextEditingController();

  final _parentPasswordController = TextEditingController();
  final _parentConfirmPasswordController = TextEditingController();

  // --- STATE ---
  XFile? _pickedFile;
  Uint8List? _webImage;
  final ImagePicker _picker = ImagePicker();

  List<String> _activeClasses = [];
  List<Map<String, dynamic>> _allClassesData = [];
  final Map<String, String> _classNameToIdMap = {};

  bool _isLoading = true;
  bool _hasClasses = false;

  String _currentSchoolName = "";
  String? _schoolId; // 🚨 FIX: define _schoolId used across methods

  // 🚨 AUTO-SYNC ENGINE STATES
  String _globalSession = "2025/2026";
  String _globalTerm = "1st Term";
  String _resolvedSession = "2025/2026";
  String _resolvedTerm = "1st Term";

  String? _selectedClass;
  String? _selectedDepartment;
  String _selectedGender = "Male";
  String _studentCategory = "Regular";
  String _generatedID = "---/--/--/---";

  bool _usePhoneAsLogin = false;
  bool _isObscure1 = true;
  bool _isObscure2 = true;

  // 🚨 NEW: LIVE TRACKER STATES
  Timer? _debounce;
  bool _isExistingParentFound = false;
  bool _pwdHasMinLength = false;
  bool _pwdHasNumber = false;
  bool _pwdMatch = false;

  @override
  void initState() {
    super.initState();
    _fetchSchoolConfig();

    // Attach live listeners for the password tracker
    _parentPasswordController.addListener(_validatePassword);
    _parentConfirmPasswordController.addListener(_validatePassword);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _parentPasswordController.removeListener(_validatePassword);
    _parentConfirmPasswordController.removeListener(_validatePassword);
    super.dispose();
  }

  // ===========================================================================
  // 🚨 LOGIC ENGINE: STRICTLY UNTOUCHED (With Tracker Methods Added)
  // ===========================================================================
  Future<void> _fetchSchoolConfig() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final profile = await _supabase
          .from('profiles')
          .select('school_id')
          .eq('id', user.id)
          .single();
      final schoolId = profile['school_id'];
      if (mounted) setState(() => _schoolId = schoolId);

      final school = await _supabase
          .from('schools')
          .select('name, current_session, current_term')
          .eq('id', schoolId)
          .single();

      final classesData = await _supabase
          .from('classes')
          .select('id, name, override_session, override_term')
          .eq('school_id', schoolId)
          .order('list_order', ascending: true);

      if (mounted) {
        setState(() {
          _currentSchoolName = school['name'] ?? "";
          _globalSession = school['current_session'] ?? "2025/2026";
          _globalTerm = school['current_term'] ?? "1st Term";

          _classNameToIdMap.clear();
          if (classesData.isNotEmpty) {
            _allClassesData = List<Map<String, dynamic>>.from(classesData);
            for (var c in classesData) {
              _classNameToIdMap[c['name'].toString()] = c['id'].toString();
            }
            _activeClasses = classesData
                .map((c) => c['name'].toString())
                .toList();
            _hasClasses = true;
            _selectedClass = _activeClasses[0];

            _resolveSessionForClass(_selectedClass!);
          }

          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _resolveSessionForClass(String className) {
    final classData = _allClassesData.firstWhere(
      (c) => c['name'] == className,
      orElse: () => <String, dynamic>{},
    );
    setState(() {
      _selectedClass =
          className; // 🚨 BUG FIXED: Class now correctly stays selected in UI
      _resolvedSession = classData['override_session'] ?? _globalSession;
      _resolvedTerm = classData['override_term'] ?? _globalTerm;
    });
    _updateSmartID();
  }

  void _updateSmartID() {
    if (_selectedClass == null || _currentSchoolName.isEmpty) return;
    String schoolPrefix = _generateSchoolAcronym(_currentSchoolName);
    String year = _resolvedSession.split("/")[0].substring(2);
    String classCode = _getClassCode(_selectedClass!);
    setState(() => _generatedID = "$schoolPrefix/$year/$classCode/XXX");
  }

  String _getClassCode(String cls) {
    if (cls.contains("JSS 1")) return "J1";
    if (cls.contains("JSS 2")) return "J2";
    if (cls.contains("JSS 3")) return "J3";
    if (cls.contains("SS 1")) return "S1";
    if (cls.contains("SS 2")) return "S2";
    if (cls.contains("SS 3")) return "S3";
    return "GN";
  }

  String _generateSchoolAcronym(String name) {
    return name
        .split(" ")
        .where((w) => !["of", "the", "school"].contains(w.toLowerCase()))
        .map((w) => w[0])
        .join()
        .toUpperCase();
  }

  // 🚨 NEW: Password Tracker Validator
  void _validatePassword() {
    String p = _parentPasswordController.text;
    String c = _parentConfirmPasswordController.text;
    setState(() {
      _pwdHasMinLength = p.length >= 6;
      _pwdHasNumber = p.contains(RegExp(r'[0-9]'));
      _pwdMatch = p.isNotEmpty && p == c;
    });
  }

  // 🚨 NEW: Parent ID Live DB Polling
  void _onParentLoginChanged(String val) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () {
      _checkExistingParent();
    });
  }

  Future<void> _checkExistingParent() async {
    if (!mounted || _schoolId == null) return;

    String exactLoginId = _parentEmailController.text.trim().toLowerCase();
    String rawLoginPhone = _loginPhoneController.text.trim();
    String searchPhone = _usePhoneAsLogin
        ? rawLoginPhone
        : _parentPhoneController.text.trim();

    if (_usePhoneAsLogin && rawLoginPhone.length < 10) {
      setState(() => _isExistingParentFound = false);
      return;
    }
    if (!_usePhoneAsLogin &&
        (exactLoginId.isEmpty || !exactLoginId.contains('@'))) {
      setState(() => _isExistingParentFound = false);
      return;
    }

    try {
      List existing = [];
      if (searchPhone.isNotEmpty && _usePhoneAsLogin) {
        existing = await _supabase
            .from('students')
            .select('parent_name')
            .eq('parent_phone', searchPhone)
            .eq('school_id', _schoolId!)
            .limit(1);
      } else {
        existing = await _supabase
            .from('students')
            .select('parent_name')
            .eq('parent_email', exactLoginId)
            .eq('school_id', _schoolId!)
            .limit(1);
      }

      if (mounted) {
        if (existing.isNotEmpty) {
          setState(() {
            _isExistingParentFound = true;
            _parentNameController.text = existing[0]['parent_name'] ?? '';
          });
        } else {
          setState(() => _isExistingParentFound = false);
        }
      }
    } catch (e) {
      debugPrint("Live check error: $e");
    }
  }

  Future<void> _pickImage() async {
    setState(() => isInteractingWithSystem = true);

    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
      maxWidth: 600,
      maxHeight: 600,
    );

    setState(() => isInteractingWithSystem = false);

    if (image != null) {
      final bytes = await image.readAsBytes();

      if (bytes.lengthInBytes > 500 * 1024) {
        showAuthErrorDialog(
          "Image is too large. Please choose a simpler photo.",
        );
        return;
      }

      setState(() {
        _pickedFile = image;
        _webImage = bytes;
      });
    }
  }

  Future<void> _registerStudent() async {
    if (!_formKey.currentState!.validate() || _pickedFile == null) {
      if (_pickedFile == null) {
        showAuthErrorDialog(
          "Passport photo is missing.\n\nPlease scroll up and tap the camera icon to upload a photo of the student.",
        );
      }
      return;
    }

    String exactLoginId = _parentEmailController.text.trim().toLowerCase();
    String rawLoginPhone = _loginPhoneController.text.trim();
    String pwd = _parentPasswordController.text;

    if (_usePhoneAsLogin) {
      if (rawLoginPhone.isEmpty) {
        showAuthErrorDialog("Please enter a phone number for login.");
        return;
      }

      String cleanPhone = rawLoginPhone.replaceAll(' ', '');
      if (cleanPhone.startsWith('0')) {
        cleanPhone = '+234${cleanPhone.substring(1)}';
      } else if (!cleanPhone.startsWith('+')) {
        cleanPhone = '+234$cleanPhone';
      }
      exactLoginId = "$cleanPhone@trideta.com";
    }

    setState(() => _isLoading = true);
    try {
      final user = _supabase.auth.currentUser;
      final profile = await _supabase
          .from('profiles')
          .select('school_id')
          .eq('id', user!.id)
          .single();
      final schoolId = profile['school_id'];

      List existing = [];
      String searchPhone = _usePhoneAsLogin
          ? rawLoginPhone
          : _parentPhoneController.text.trim();

      if (searchPhone.isNotEmpty) {
        existing = await _supabase
            .from('students')
            .select('parent_account_created, first_name, parent_email')
            .eq('parent_phone', searchPhone)
            .eq('school_id', schoolId)
            .limit(1);
      } else {
        existing = await _supabase
            .from('students')
            .select('parent_account_created, first_name, parent_email')
            .eq('parent_email', exactLoginId)
            .eq('school_id', schoolId)
            .limit(1);
      }

      bool isExistingParent = existing.isNotEmpty;
      bool accountAlreadyCreated = false;
      String finalLoginIdToSave = exactLoginId;

      if (isExistingParent) {
        setState(() => _isLoading = false);
        String siblingName = existing[0]['first_name'];
        accountAlreadyCreated = existing[0]['parent_account_created'] ?? false;
        String oldParentEmail = existing[0]['parent_email']?.toString() ?? "";

        if (_usePhoneAsLogin &&
            oldParentEmail.isNotEmpty &&
            !oldParentEmail.contains('@trideta.com')) {
          try {
            final response = await _supabase.functions.invoke(
              'migrate-parent-email',
              body: {'oldEmail': oldParentEmail, 'newEmail': exactLoginId},
            );

            if (response.data != null && response.data['error'] != null) {
              setState(() => _isLoading = false);
              showAuthErrorDialog(
                "Migration Failed: ${response.data['error']}",
              );
              return;
            }
          } catch (e) {
            setState(() => _isLoading = false);
            showAuthErrorDialog(
              "Migration Error.\n\nCould not migrate existing email account to phone number. Contact support if this persists.",
            );
            return;
          }
        }

        bool proceed =
            await showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF1E1E1E)
                    : Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                title: const Row(
                  children: [
                    Icon(Icons.family_restroom_rounded, color: Colors.blue),
                    SizedBox(width: 10),
                    Text(
                      "Sibling Detected",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                content: Text(
                  "We found an existing parent profile matching this ${_usePhoneAsLogin ? 'phone number' : 'email address'} (Child: $siblingName).\n\nDo you want to link this new student to the same parent account?",
                  style: const TextStyle(height: 1.4),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text(
                      "Cancel",
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text(
                      "Yes, Link Sibling",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ) ??
            false;

        if (!proceed) {
          setState(() => _isLoading = false);
          return;
        }

        setState(() => _isLoading = true);
        if (!accountAlreadyCreated) {
          try {
            await _supabase.functions.invoke(
              'create-parent-account',
              body: {
                'email': _usePhoneAsLogin ? '' : exactLoginId,
                'password': pwd,
                'phone': _usePhoneAsLogin
                    ? rawLoginPhone
                    : _parentPhoneController.text.trim(),
                'studentName': _firstNameController.text.trim(),
                'usePhoneForLogin': _usePhoneAsLogin,
              },
            );
            accountAlreadyCreated = true;
          } catch (e) {
            if (e.toString().contains("already exists")) {
              accountAlreadyCreated = true;
            } else {
              setState(() => _isLoading = false);
              showAuthErrorDialog("Auth Link Error: $e");
              return;
            }
          }
        } else {
          finalLoginIdToSave = oldParentEmail.isNotEmpty
              ? oldParentEmail
              : exactLoginId;
        }
      } else {
        try {
          await _supabase.functions.invoke(
            'create-parent-account',
            body: {
              'email': _usePhoneAsLogin ? '' : exactLoginId,
              'password': pwd,
              'phone': _usePhoneAsLogin
                  ? rawLoginPhone
                  : _parentPhoneController.text.trim(),
              'studentName': _firstNameController.text.trim(),
              'usePhoneForLogin': _usePhoneAsLogin,
            },
          );
          accountAlreadyCreated = true;
          finalLoginIdToSave = exactLoginId;
        } catch (e) {
          if (e.toString().contains("already exists")) {
            setState(() => _isLoading = false);
            showAuthErrorDialog(
              "Account Collision.\n\nThis exact login already exists in the Trideta network but is NOT linked to your school yet. Please use a slightly different email or phone number.",
            );
            return;
          }
          setState(() => _isLoading = false);
          showAuthErrorDialog("Auth Creation Error: $e");
          return;
        }
      }

      String finalID = _generatedID.replaceAll(
        'XXX',
        DateTime.now().millisecondsSinceEpoch.toString().substring(9),
      );
      final fileExt = _pickedFile!.name.split('.').last;
      final fileName = '$schoolId/${finalID.replaceAll('/', '_')}.$fileExt';

      await _supabase.storage
          .from('student_passports')
          .uploadBinary(fileName, _webImage!);
      String passportUrl = _supabase.storage
          .from('student_passports')
          .getPublicUrl(fileName);

      await _supabase.from('students').insert({
        'school_id': schoolId,
        'first_name': _firstNameController.text.trim(),
        'middle_name': _middleNameController.text.trim(),
        'last_name': _lastNameController.text.trim(),
        'admission_no': finalID,
        'class_id': _classNameToIdMap[_selectedClass],
        'class_level': _selectedClass,
        'department': _selectedDepartment,
        'gender': _selectedGender,
        'dob': _dobController.text.trim(),
        'passport_url': passportUrl,
        'parent_name': _parentNameController.text.trim(),
        'parent_email': finalLoginIdToSave,
        'parent_phone': searchPhone,
        'address': _addressController.text.trim(),
        'category': _studentCategory,
        'session_admitted': _resolvedSession,
        'parent_account_created': accountAlreadyCreated,
      });

      if (mounted) {
        showSuccessDialog(
          "Admission Successful",
          "Student $finalID has been registered${isExistingParent ? ' and linked as a sibling' : ''}.",
        );
        _clearForm();
      }
    } catch (e) {
      debugPrint("💥 ADMISSION ERROR: $e");
      if (mounted) {
        setState(() => _isLoading = false);
        showAuthErrorDialog(
          "Failed to admit student.\n\nPlease check your internet connection.",
        );
      }
    }
  }

  void _clearForm() {
    setState(() {
      _firstNameController.clear();
      _middleNameController.clear();
      _lastNameController.clear();
      _dobController.clear();
      _parentNameController.clear();
      _parentEmailController.clear();
      _loginPhoneController.clear();
      _parentPhoneController.clear();
      _addressController.clear();
      _parentPasswordController.clear();
      _parentConfirmPasswordController.clear();
      _pickedFile = null;
      _webImage = null;

      // Reset tracker states
      _isExistingParentFound = false;
      _pwdHasMinLength = false;
      _pwdHasNumber = false;
      _pwdMatch = false;

      _isLoading = false;
      _updateSmartID();
    });
  }

  // ===========================================================================
  // 🚨 PREMIUM UI (REFINED FORM AND INTELLIGENT INDICATORS)
  // ===========================================================================
  @override
  Widget build(BuildContext context) {
    if (_isLoading && _activeClasses.isEmpty) {
      return const Scaffold(body: Center(child: TridetaLoader()));
    }
    if (!_hasClasses) {
      return _NoClassesView(
        onRefresh: () {
          setState(() => _isLoading = true);
          _fetchSchoolConfig();
        },
      );
    }

    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color primaryColor = Theme.of(context).primaryColor;
    Color bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC);
    Color cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    Color textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text(
          "Admit New Student",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: bgColor,
        foregroundColor: textColor,
        elevation: 0,
        centerTitle: true,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth > 800) {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: Container(
                  margin: const EdgeInsets.symmetric(
                    vertical: 24,
                    horizontal: 24,
                  ),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: isDark ? Colors.white10 : Colors.grey.shade200,
                      width: 1.5,
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
                    child: _buildFormContent(
                      isDark,
                      primaryColor,
                      cardColor,
                      textColor,
                    ),
                  ),
                ),
              ),
            );
          } else {
            return _buildFormContent(isDark, primaryColor, bgColor, textColor);
          }
        },
      ),
    );
  }

  Widget _buildFormContent(
    bool isDark,
    Color primaryColor,
    Color cardColor,
    Color textColor,
  ) {
    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Column(
                children: [
                  GestureDetector(
                    onTap: _pickImage,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: primaryColor.withValues(alpha: 0.05),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: primaryColor.withValues(alpha: 0.2),
                          width: 2,
                          style: BorderStyle.solid,
                        ),
                      ),
                      child: CircleAvatar(
                        radius: 65,
                        backgroundColor: isDark
                            ? Colors.white.withValues(alpha: 0.05)
                            : Colors.white,
                        backgroundImage: _webImage != null
                            ? MemoryImage(_webImage!)
                            : null,
                        child: _webImage == null
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
                                      color: primaryColor.withValues(
                                        alpha: 0.7,
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(height: 25),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF2C2C2C)
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isDark ? Colors.white10 : Colors.grey.shade300,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.tag_rounded,
                          size: 16,
                          color: Colors.grey.shade500,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _generatedID,
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
            ),
            const SizedBox(height: 40),

            _buildSectionTitle(
              "Academic Setup",
              Icons.school_rounded,
              primaryColor,
            ),
            const SizedBox(height: 20),

            _buildDropdown(
              "Class Designation",
              _activeClasses,
              _selectedClass,
              (v) => _resolveSessionForClass(v!),
              isDark,
              primaryColor,
              cardColor,
            ),
            const SizedBox(height: 12),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: primaryColor.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.auto_awesome_rounded,
                    color: primaryColor,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Auto-Synced to $_resolvedSession  •  $_resolvedTerm",
                      style: TextStyle(
                        color: primaryColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            if ((_selectedClass ?? "").contains("SS")) ...[
              const SizedBox(height: 16),
              _buildDropdown(
                "Department (Optional)",
                ['Science', 'Art', 'Commercial'],
                _selectedDepartment,
                (v) => setState(() => _selectedDepartment = v),
                isDark,
                primaryColor,
                cardColor,
              ),
            ],
            const SizedBox(height: 16),
            _buildDropdown(
              "Admission Type",
              ['Regular', 'Transfer', 'Scholarship', 'Special'],
              _studentCategory,
              (v) => setState(() => _studentCategory = v!),
              isDark,
              primaryColor,
              cardColor,
            ),
            const SizedBox(height: 40),

            _buildSectionTitle(
              "Student Biodata",
              Icons.badge_rounded,
              Colors.orange,
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _buildTextField(
                    _firstNameController,
                    "First Name",
                    Icons.person_outline_rounded,
                    isDark,
                    primaryColor,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildTextField(
                    _middleNameController,
                    "Middle Name",
                    null,
                    isDark,
                    primaryColor,
                    isRequired: false,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildTextField(
              _lastNameController,
              "Surname (Last Name)",
              Icons.badge_outlined,
              isDark,
              primaryColor,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: _buildTextField(
                    _dobController,
                    "Date of Birth",
                    Icons.cake_rounded,
                    isDark,
                    primaryColor,
                    readOnly: true,
                    onTap: () async {
                      final DateTime? picked = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now().subtract(
                          const Duration(days: 365 * 3),
                        ),
                        firstDate: DateTime(1990),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        setState(() {
                          _dobController.text =
                              "${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}";
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: _buildDropdown(
                    "Gender",
                    ['Male', 'Female'],
                    _selectedGender,
                    (v) => setState(() => _selectedGender = v!),
                    isDark,
                    primaryColor,
                    cardColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 40),

            _buildSectionTitle(
              "Parent / Guardian Routing",
              Icons.family_restroom_rounded,
              Colors.green,
            ),
            const SizedBox(height: 20),

            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() {
                        _usePhoneAsLogin = false;
                        _loginPhoneController.clear();
                      }),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: !_usePhoneAsLogin
                              ? cardColor
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: !_usePhoneAsLogin
                              ? [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.05),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                              : [],
                        ),
                        child: Center(
                          child: Text(
                            "Email Login",
                            style: TextStyle(
                              color: !_usePhoneAsLogin
                                  ? textColor
                                  : Colors.grey.shade500,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() {
                        _usePhoneAsLogin = true;
                        _parentEmailController.clear();
                      }),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: _usePhoneAsLogin
                              ? cardColor
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: _usePhoneAsLogin
                              ? [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.05),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                              : [],
                        ),
                        child: Center(
                          child: Text(
                            "Phone Login",
                            style: TextStyle(
                              color: _usePhoneAsLogin
                                  ? textColor
                                  : Colors.grey.shade500,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SizeTransition(sizeFactor: animation, child: child),
              ),
              child: _usePhoneAsLogin
                  ? _buildPhoneLoginFields(isDark, primaryColor)
                  : _buildEmailLoginFields(isDark, primaryColor),
            ),
            const SizedBox(height: 20),

            // 🚨 INTELLIGENT EXISTING PARENT BADGE
            if (_isExistingParentFound)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.green.withValues(alpha: 0.3),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.verified_user_rounded,
                      color: Colors.green,
                      size: 24,
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        "Linked Parent Profile Found! Name auto-filled and password setup bypassed.",
                        style: TextStyle(
                          color: Colors.green,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            _buildTextField(
              _parentNameController,
              "Parent Full Name",
              Icons.account_circle_rounded,
              isDark,
              primaryColor,
              readOnly: _isExistingParentFound,
            ),
            const SizedBox(height: 16),

            _buildTextField(
              _addressController,
              "Home Address",
              Icons.location_on_rounded,
              isDark,
              primaryColor,
              maxLines: 2,
            ),

            // 🚨 HIDES PASSWORD FIELDS IF PARENT ALREADY EXISTS
            if (!_isExistingParentFound) ...[
              const SizedBox(height: 35),
              _buildSectionTitle(
                "Security & Authorization",
                Icons.security_rounded,
                Colors.redAccent,
              ),
              const SizedBox(height: 20),
              _buildPasswordField(
                _parentPasswordController,
                "Create Parent Password",
                _isObscure1,
                (v) => setState(() => _isObscure1 = v),
                isDark,
                primaryColor,
              ),

              // 🚨 LIVE PASSWORD TRACKER
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 4,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _trackerChip("6+ Chars", _pwdHasMinLength),
                    _trackerChip("Number", _pwdHasNumber),
                    _trackerChip("Match", _pwdMatch),
                  ],
                ),
              ),

              _buildPasswordField(
                _parentConfirmPasswordController,
                "Confirm Password",
                _isObscure2,
                (v) => setState(() => _isObscure2 = v),
                isDark,
                primaryColor,
              ),
            ],

            const SizedBox(height: 50),

            SizedBox(
              width: double.infinity,
              height: 60,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: primaryColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                onPressed: _isLoading ? null : _registerStudent,
                icon: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: TridetaLoader(color: Colors.white),
                      )
                    : const Icon(
                        Icons.check_circle_rounded,
                        color: Colors.white,
                      ),
                label: Text(
                  _isLoading ? "AUTHORIZING..." : "SUBMIT ENROLLMENT",
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 50),
          ],
        ),
      ),
    );
  }

  // --- COMPACT WIDGETS ---

  Widget _trackerChip(String label, bool isValid) {
    return Row(
      children: [
        Icon(
          isValid
              ? Icons.check_circle_rounded
              : Icons.radio_button_unchecked_rounded,
          size: 16,
          color: isValid ? Colors.green : Colors.grey.shade400,
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isValid ? Colors.green : Colors.grey.shade500,
            fontWeight: isValid ? FontWeight.bold : FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title, IconData icon, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 12),
            Text(
              title.toUpperCase(),
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: color,
                letterSpacing: 1.5,
                fontSize: 11,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Divider(height: 1, color: Colors.grey.withValues(alpha: 0.2)),
      ],
    );
  }

  Widget _buildTextField(
    TextEditingController ctrl,
    String label,
    IconData? icon,
    bool isDark,
    Color primaryColor, {
    bool isRequired = true,
    int maxLines = 1,
    bool readOnly = false,
    VoidCallback? onTap,
    Function(String)? onChanged,
  }) {
    return TextFormField(
      controller: ctrl,
      maxLines: maxLines,
      readOnly: readOnly,
      onTap: onTap,
      onChanged: onChanged,
      validator: isRequired
          ? (v) => v!.trim().isEmpty ? "Required field" : null
          : null,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey.shade500, fontSize: 13),
        prefixIcon: icon != null
            ? Icon(icon, color: readOnly ? Colors.grey : primaryColor, size: 20)
            : null,
        filled: true,
        fillColor: readOnly
            ? (isDark
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.grey.shade200)
            : (isDark
                  ? Colors.white.withValues(alpha: 0.03)
                  : Colors.grey.shade50),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: isDark ? Colors.white10 : Colors.grey.shade200,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: primaryColor.withValues(alpha: 0.5),
            width: 2,
          ),
        ),
      ),
    );
  }

  Widget _buildPasswordField(
    TextEditingController ctrl,
    String label,
    bool isObscure,
    Function(bool) onToggle,
    bool isDark,
    Color primaryColor,
  ) {
    return TextFormField(
      controller: ctrl,
      obscureText: isObscure,
      validator: (v) {
        if (v!.isEmpty) return "Password required";
        if (v.length < 6) return "Must be at least 6 chars";
        if (ctrl == _parentConfirmPasswordController &&
            v != _parentPasswordController.text)
          return "Passwords do not match";
        return null;
      },
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey.shade500, fontSize: 13),
        prefixIcon: Icon(Icons.lock_rounded, color: primaryColor, size: 20),
        suffixIcon: IconButton(
          icon: Icon(
            isObscure ? Icons.visibility_off_rounded : Icons.visibility_rounded,
            color: Colors.grey.shade400,
            size: 20,
          ),
          onPressed: () => onToggle(!isObscure),
        ),
        filled: true,
        fillColor: isDark
            ? Colors.white.withValues(alpha: 0.03)
            : Colors.grey.shade50,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: isDark ? Colors.white10 : Colors.grey.shade200,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: primaryColor.withValues(alpha: 0.5),
            width: 2,
          ),
        ),
      ),
    );
  }

  Widget _buildDropdown(
    String hint,
    List<String> items,
    String? value,
    Function(String?) onChanged,
    bool isDark,
    Color primaryColor,
    Color dropdownColor,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.03)
            : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: value,
          hint: Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Text(
              hint,
              style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
            ),
          ),
          icon: Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Icon(Icons.keyboard_arrow_down_rounded, color: primaryColor),
          ),
          items: items
              .map(
                (e) => DropdownMenuItem(
                  value: e,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: Text(
                      e,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
          onChanged: onChanged,
          dropdownColor: isDark ? const Color(0xFF2C2C2C) : Colors.white,
        ),
      ),
    );
  }

  Widget _buildEmailLoginFields(bool isDark, Color primaryColor) {
    return Column(
      key: const ValueKey('email_login'),
      children: [
        _buildTextField(
          _parentEmailController,
          "Parent Login Email",
          Icons.email_rounded,
          isDark,
          primaryColor,
          onChanged: _onParentLoginChanged,
        ),
        const SizedBox(height: 16),
        _buildTextField(
          _parentPhoneController,
          "Contact Phone Number (Optional)",
          Icons.phone_rounded,
          isDark,
          primaryColor,
          isRequired: false,
        ),
      ],
    );
  }

  Widget _buildPhoneLoginFields(bool isDark, Color primaryColor) {
    return Column(
      key: const ValueKey('phone_login'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _loginPhoneController,
          keyboardType: TextInputType.phone,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: _onParentLoginChanged,
          validator: (v) =>
              v!.trim().isEmpty ? "Phone required for login" : null,
          decoration: InputDecoration(
            labelText: "Login Phone Number",
            labelStyle: TextStyle(color: Colors.grey.shade500, fontSize: 13),
            hintText: "08012345678",
            hintStyle: TextStyle(color: Colors.grey.shade400),
            prefixIcon: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
              child: Text(
                "🇳🇬 +234",
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ),
            filled: true,
            fillColor: isDark
                ? Colors.white.withValues(alpha: 0.03)
                : Colors.grey.shade50,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color: isDark ? Colors.white10 : Colors.grey.shade200,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color: primaryColor.withValues(alpha: 0.5),
                width: 2,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.info_outline_rounded,
                color: Colors.orange,
                size: 14,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Parents will log in using this number exactly as entered.",
                  style: TextStyle(
                    color: Colors.orange.shade700,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NoClassesView extends StatelessWidget {
  final VoidCallback onRefresh;
  const _NoClassesView({required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    Color primaryColor = Theme.of(context).primaryColor;
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF121212)
          : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          "System Check",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: isDark ? Colors.white : Colors.black87,
        elevation: 0,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  size: 60,
                  color: Colors.orange,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                "Configuration Required",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              Text(
                "Please define active classes in the Setup Wizard before admitting students.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade500, height: 1.4),
              ),
              const SizedBox(height: 40),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: primaryColor,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const SchoolConfigurationScreen(),
                  ),
                ).then((_) => onRefresh()),
                icon: const Icon(
                  Icons.settings_suggest_rounded,
                  color: Colors.white,
                ),
                label: const Text(
                  "OPEN SETUP WIZARD",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
