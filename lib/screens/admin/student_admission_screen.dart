import 'dart:async';
import 'package:trideta_v2/utils/auth_error_handler.dart';
import 'package:trideta_v2/widgets/trideta_loader.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';

import 'package:trideta_v2/main.dart';
import 'package:trideta_v2/screens/admin/school_configuration_screen.dart';

// 🚨 MODULARIZED COMPONENTS
import 'package:trideta_v2/screens/admin/components/admission/admission_header_widget.dart';
import 'package:trideta_v2/screens/admin/components/admission/academic_setup_widget.dart';
import 'package:trideta_v2/screens/admin/components/admission/student_biodata_widget.dart';
import 'package:trideta_v2/screens/admin/components/admission/parent_routing_widget.dart';

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
  String _schoolId = "";

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

  Timer? _debounce;
  bool _isExistingParentFound = false;
  bool _pwdHasMinLength = false;
  bool _pwdHasNumber = false;
  bool _pwdMatch = false;

  @override
  void initState() {
    super.initState();
    _fetchSchoolConfig();
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
  // 🚨 THE LOGIC ENGINE
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
      final sId = profile['school_id'];
      if (mounted) setState(() => _schoolId = sId);

      final school = await _supabase
          .from('schools')
          .select('name, current_session, current_term')
          .eq('id', sId)
          .single();
      final classesData = await _supabase
          .from('classes')
          .select('id, name, override_session, override_term')
          .eq('school_id', sId)
          .order('list_order', ascending: true);

      if (mounted) {
        setState(() {
          _currentSchoolName = school['name'] ?? "";
          _globalSession = school['current_session'] ?? "2025/2026";
          _globalTerm = school['current_term'] ?? "1st Term";

          _classNameToIdMap.clear();
          if (classesData.isNotEmpty) {
            _allClassesData = List<Map<String, dynamic>>.from(classesData);
            for (var c in classesData)
              _classNameToIdMap[c['name'].toString()] = c['id'].toString();
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
      _selectedClass = className;
      _resolvedSession = classData['override_session'] ?? _globalSession;
      _resolvedTerm = classData['override_term'] ?? _globalTerm;
    });
    _updateSmartID();
  }

  void _updateSmartID() {
    if (_selectedClass == null || _currentSchoolName.isEmpty) return;
    String schoolPrefix = _currentSchoolName
        .split(" ")
        .where((w) => !["of", "the", "school"].contains(w.toLowerCase()))
        .map((w) => w[0])
        .join()
        .toUpperCase();
    String year = _resolvedSession.split("/")[0].substring(2);

    String cls = _selectedClass!;
    String classCode = "GN";
    if (cls.contains("JSS 1")) classCode = "J1";
    if (cls.contains("JSS 2")) classCode = "J2";
    if (cls.contains("JSS 3")) classCode = "J3";
    if (cls.contains("SS 1")) classCode = "S1";
    if (cls.contains("SS 2")) classCode = "S2";
    if (cls.contains("SS 3")) classCode = "S3";

    setState(() => _generatedID = "$schoolPrefix/$year/$classCode/XXX");
  }

  void _validatePassword() {
    String p = _parentPasswordController.text;
    String c = _parentConfirmPasswordController.text;
    setState(() {
      _pwdHasMinLength = p.length >= 6;
      _pwdHasNumber = p.contains(RegExp(r'[0-9]'));
      _pwdMatch = p.isNotEmpty && p == c;
    });
  }

  void _onParentLoginChanged(String val) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _checkExistingParent);
  }

  Future<void> _checkExistingParent() async {
    if (!mounted || _schoolId.isEmpty) return;
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
      // 🚨 UPDATED LOGIC: Removed .eq('school_id', _schoolId) to allow cross-school parent detection
      if (searchPhone.isNotEmpty && _usePhoneAsLogin) {
        existing = await _supabase
            .from('students')
            .select('parent_name')
            .eq('parent_phone', searchPhone)
            .limit(1);
      } else {
        existing = await _supabase
            .from('students')
            .select('parent_name')
            .eq('parent_email', exactLoginId)
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
      if (_pickedFile == null)
        showAuthErrorDialog(
          "Passport photo is missing.\n\nPlease scroll up and tap the camera icon to upload a photo of the student.",
        );
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
      if (cleanPhone.startsWith('0'))
        cleanPhone = '+234${cleanPhone.substring(1)}';
      else if (!cleanPhone.startsWith('+'))
        cleanPhone = '+234$cleanPhone';
      exactLoginId = "$cleanPhone@trideta.com";
    }

    setState(() => _isLoading = true);
    try {
      List existing = [];
      String searchPhone = _usePhoneAsLogin
          ? rawLoginPhone
          : _parentPhoneController.text.trim();

      // 🚨 UPDATED LOGIC: Removed .eq('school_id', _schoolId) to verify parent status globally
      if (searchPhone.isNotEmpty) {
        existing = await _supabase
            .from('students')
            .select('parent_account_created, first_name, parent_email')
            .eq('parent_phone', searchPhone)
            .limit(1);
      } else {
        existing = await _supabase
            .from('students')
            .select('parent_account_created, first_name, parent_email')
            .eq('parent_email', exactLoginId)
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
              "Migration Error.\n\nCould not migrate existing email account to phone number.",
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
              "Account Collision.\n\nThis exact login already exists.",
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
      final fileName = '$_schoolId/${finalID.replaceAll('/', '_')}.$fileExt';

      await _supabase.storage
          .from('student_passports')
          .uploadBinary(fileName, _webImage!);
      String passportUrl = _supabase.storage
          .from('student_passports')
          .getPublicUrl(fileName);

      await _supabase.from('students').insert({
        'school_id': _schoolId,
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
      _isExistingParentFound = false;
      _pwdHasMinLength = false;
      _pwdHasNumber = false;
      _pwdMatch = false;
      _isLoading = false;
      _updateSmartID();
    });
  }

  // ===========================================================================
  // 🚨 MODULAR UI COMPOSITION
  // ===========================================================================
  @override
  Widget build(BuildContext context) {
    if (_isLoading && _activeClasses.isEmpty)
      return const Scaffold(body: Center(child: TridetaLoader()));
    if (!_hasClasses) {
      return Scaffold(
        appBar: AppBar(title: const Text("System Check")),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                size: 60,
                color: Colors.orange,
              ),
              const SizedBox(height: 20),
              const Text(
                "Configuration Required",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const SchoolConfigurationScreen(),
                      ),
                    ).then((_) {
                      setState(() => _isLoading = true);
                      _fetchSchoolConfig();
                    }),
                child: const Text("OPEN SETUP WIZARD"),
              ),
            ],
          ),
        ),
      );
    }

    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color primaryColor = Theme.of(context).primaryColor;
    Color bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC);
    Color cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    Color textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);

    Widget formContent = Form(
      key: _formKey,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(30),
        child: Column(
          children: [
            AdmissionHeaderWidget(
              webImage: _webImage,
              onPickImage: _pickImage,
              generatedID: _generatedID,
              primaryColor: primaryColor,
              isDark: isDark,
              textColor: textColor,
            ),
            const SizedBox(height: 40),
            AcademicSetupWidget(
              activeClasses: _activeClasses,
              selectedClass: _selectedClass,
              resolvedSession: _resolvedSession,
              resolvedTerm: _resolvedTerm,
              selectedDepartment: _selectedDepartment,
              studentCategory: _studentCategory,
              primaryColor: primaryColor,
              isDark: isDark,
              cardColor: cardColor,
              onClassChanged: _resolveSessionForClass,
              onDepartmentChanged: (v) =>
                  setState(() => _selectedDepartment = v),
              onCategoryChanged: (v) => setState(() => _studentCategory = v),
            ),
            const SizedBox(height: 40),
            StudentBiodataWidget(
              firstNameController: _firstNameController,
              middleNameController: _middleNameController,
              lastNameController: _lastNameController,
              dobController: _dobController,
              selectedGender: _selectedGender,
              onGenderChanged: (v) => setState(() => _selectedGender = v),
              onDateTap: () async {
                final DateTime? picked = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now().subtract(
                    const Duration(days: 365 * 3),
                  ),
                  firstDate: DateTime(1990),
                  lastDate: DateTime.now(),
                );
                if (picked != null)
                  setState(
                    () => _dobController.text =
                        "${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}",
                  );
              },
              primaryColor: primaryColor,
              isDark: isDark,
              cardColor: cardColor,
            ),
            const SizedBox(height: 40),
            ParentRoutingWidget(
              usePhoneAsLogin: _usePhoneAsLogin,
              onLoginMethodChanged: (v) => setState(() {
                _usePhoneAsLogin = v;
                if (v)
                  _parentEmailController.clear();
                else
                  _loginPhoneController.clear();
              }),
              isExistingParentFound: _isExistingParentFound,
              parentNameController: _parentNameController,
              parentEmailController: _parentEmailController,
              loginPhoneController: _loginPhoneController,
              parentPhoneController: _parentPhoneController,
              addressController: _addressController,
              parentPasswordController: _parentPasswordController,
              parentConfirmPasswordController: _parentConfirmPasswordController,
              isObscure1: _isObscure1,
              isObscure2: _isObscure2,
              onObscure1Changed: (v) => setState(() => _isObscure1 = v),
              onObscure2Changed: (v) => setState(() => _isObscure2 = v),
              pwdHasMinLength: _pwdHasMinLength,
              pwdHasNumber: _pwdHasNumber,
              pwdMatch: _pwdMatch,
              onParentLoginChanged: _onParentLoginChanged,
              primaryColor: primaryColor,
              isDark: isDark,
              cardColor: cardColor,
              textColor: textColor,
            ),
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
          ],
        ),
      ),
    );

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
                    child: formContent,
                  ),
                ),
              ),
            );
          }
          return formContent;
        },
      ),
    );
  }
}
