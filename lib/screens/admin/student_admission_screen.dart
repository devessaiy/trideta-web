import 'package:trideta_v2/utils/auth_error_handler.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// 🚨 UPDATED ABSOLUTE IMPORTS
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

  // 🚨 DUAL PHONE CONTROLLERS
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
  // 🚨 INJECTED: Dictionary map to translate string names to UUIDs
  final Map<String, String> _classNameToIdMap = {};
  bool _isLoading = true;
  bool _hasClasses = false;

  String _currentSchoolName = "";
  String _selectedSession = "2025/2026";
  String? _selectedClass;
  String? _selectedDepartment;
  String _selectedGender = "Male";
  String _studentCategory = "Regular";
  String _generatedID = "---/--/--/---";

  bool _usePhoneAsLogin = false;
  bool _isObscure1 = true;
  bool _isObscure2 = true;

  @override
  void initState() {
    super.initState();
    _fetchSchoolConfig();
  }

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

      final school = await _supabase
          .from('schools')
          .select('name')
          .eq('id', schoolId)
          .single();

      final classesData = await _supabase
          .from('classes')
          .select('id, name')
          .eq('school_id', schoolId)
          .order('list_order', ascending: true);

      if (mounted) {
        setState(() {
          _currentSchoolName = school['name'] ?? "";

          _classNameToIdMap.clear();
          if (classesData.isNotEmpty) {
            for (var c in classesData) {
              _classNameToIdMap[c['name'].toString()] = c['id'].toString();
            }
            _activeClasses = classesData
                .map((c) => c['name'].toString())
                .toList();
            _hasClasses = true;
            _selectedClass = _activeClasses[0];
          }

          _isLoading = false;
        });
        _updateSmartID();
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _updateSmartID() {
    if (_selectedClass == null || _currentSchoolName.isEmpty) return;
    String schoolPrefix = _generateSchoolAcronym(_currentSchoolName);
    String year = _selectedSession.split("/")[0].substring(2);
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

  Future<void> _pickImage() async {
    setState(() => isInteractingWithSystem = true);

    // 🚨 AUTO-COMPRESSION ENGINE
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality:
          70, // 70% quality is visually identical for passports but saves massive space
      maxWidth:
          600, // Crushes 4000px phone camera photos down to a sensible size
      maxHeight: 600, // Keeps the aspect ratio bounded
    );

    setState(() => isInteractingWithSystem = false);

    if (image != null) {
      final bytes = await image.readAsBytes();

      // OPTIONAL: Extreme Safety Net (Hard Limit of 2MB)
      // Just in case the compressed image is somehow still too large
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
          "Passport photo is missing.\\n\\nPlease scroll up and tap the camera icon to upload a photo of the student.",
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
      exactLoginId = "+234${rawLoginPhone.replaceAll(' ', '')}@trideta.com";
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

      // 🚨 ADVANCED SIBLING CHECK
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

        // 🚨 THE SERVER-SIDE MIGRATION MAGIC
        if (_usePhoneAsLogin &&
            oldParentEmail.isNotEmpty &&
            !oldParentEmail.contains('@trideta.com')) {
          try {
            final response = await _supabase.functions.invoke(
              'migrate-parent-email',
              body: {'oldEmail': oldParentEmail, 'newEmail': exactLoginId},
            );

            // Check if the Edge Function sent back a custom error
            if (response.data != null && response.data['error'] != null) {
              setState(() => _isLoading = false);
              showAuthErrorDialog(
                "Migration Failed: ${response.data['error']}",
              );
              return;
            }

            // We NO LONGER update the database from Flutter. The Edge Function did it!
          } catch (e) {
            setState(() => _isLoading = false);
            showAuthErrorDialog(
              "Migration Error.\\n\\nCould not migrate existing email account to phone number. Contact support if this persists.",
            );
            return;
          }
        }

        bool proceed =
            await showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text("Sibling Detected"),
                content: Text(
                  "We found an existing parent profile matching this ${_usePhoneAsLogin ? 'phone number' : 'email address'} (Child: $siblingName).\\n\\nDo you want to link this new student to the same parent account?",
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text("Cancel"),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text("Yes, Link Sibling"),
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
        // NOT A SIBLING, CREATE NEW
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
              "Account Collision.\\n\\nThis exact login already exists in the Trideta network but is NOT linked to your school yet. Please use a slightly different email or phone number.",
            );
            return;
          }
          setState(() => _isLoading = false);
          showAuthErrorDialog("Auth Creation Error: $e");
          return;
        }
      }

      // --- SAVE PASSPORT & STUDENT DATA ---
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

      // 🚨 INSERT NEW STUDENT
      await _supabase.from('students').insert({
        'school_id': schoolId,
        'first_name': _firstNameController.text.trim(),
        'middle_name': _middleNameController.text.trim(),
        'last_name': _lastNameController.text.trim(),
        'admission_no': finalID,
        'class_id': _classNameToIdMap[_selectedClass], // 🚨 PUSHING THE UUID!
        'class_level': _selectedClass,
        'department': _selectedDepartment,
        'gender': _selectedGender,
        'dob': _dobController.text.trim(),
        'passport_url': passportUrl,
        'parent_name': _parentNameController.text.trim(),
        'parent_email': finalLoginIdToSave, // Inherited or New
        'parent_phone': searchPhone,
        'address': _addressController.text.trim(),
        'category': _studentCategory,
        'session_admitted': _selectedSession,
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
          "Failed to admit student.\\n\\nPlease check your internet connection.",
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
      _isLoading = false;
      _updateSmartID();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _activeClasses.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
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

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text(
          "Admit New Student",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth > 800) {
            // 💻 DESKTOP LAYOUT
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 20),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isDark ? Colors.white10 : Colors.grey.shade200,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 15,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: _buildFormContent(isDark, primaryColor),
                  ),
                ),
              ),
            );
          } else {
            // 📱 MOBILE LAYOUT
            return _buildFormContent(isDark, primaryColor);
          }
        },
      ),
    );
  }

  Widget _buildFormContent(bool isDark, Color primaryColor) {
    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 🚨 PHOTO & PREVIEW HEADER
            Center(
              child: Column(
                children: [
                  GestureDetector(
                    onTap: _pickImage,
                    child: CircleAvatar(
                      radius: 60,
                      backgroundColor: primaryColor.withOpacity(0.1),
                      backgroundImage: _webImage != null
                          ? MemoryImage(_webImage!)
                          : null,
                      child: _webImage == null
                          ? Icon(
                              Icons.add_a_photo,
                              size: 40,
                              color: primaryColor,
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    "Student Passport",
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 15),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Text(
                      _generatedID,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: primaryColor,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),

            _buildSectionTitle("Student Details", Icons.person_outline),
            const SizedBox(height: 15),
            Row(
              children: [
                Expanded(
                  child: _buildTextField(
                    _firstNameController,
                    "First Name",
                    Icons.badge,
                    isDark,
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: _buildTextField(
                    _middleNameController,
                    "Middle Name",
                    null,
                    isDark,
                    isRequired: false,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),
            _buildTextField(
              _lastNameController,
              "Surname (Last Name)",
              Icons.badge_outlined,
              isDark,
            ),
            const SizedBox(height: 15),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: _buildTextField(
                    _dobController,
                    "Date of Birth (DD/MM/YYYY)",
                    Icons.cake,
                    isDark,
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  flex: 2,
                  child: _buildDropdown(
                    "Gender",
                    ['Male', 'Female'],
                    _selectedGender,
                    (v) => setState(() => _selectedGender = v!),
                    isDark,
                    primaryColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 30),

            _buildSectionTitle("Academic Setup", Icons.school_outlined),
            const SizedBox(height: 15),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: _buildDropdown(
                    "Session",
                    ['2024/2025', '2025/2026', '2026/2027'],
                    _selectedSession,
                    (v) => setState(() {
                      _selectedSession = v!;
                      _updateSmartID();
                    }),
                    isDark,
                    primaryColor,
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  flex: 4,
                  child: _buildDropdown(
                    "Class",
                    _activeClasses,
                    _selectedClass,
                    (v) => setState(() {
                      _selectedClass = v!;
                      _updateSmartID();
                    }),
                    isDark,
                    primaryColor,
                  ),
                ),
              ],
            ),
            if ((_selectedClass ?? "").contains("SS")) ...[
              const SizedBox(height: 15),
              _buildDropdown(
                "Department (Optional)",
                ['Science', 'Art', 'Commercial'],
                _selectedDepartment,
                (v) => setState(() => _selectedDepartment = v),
                isDark,
                primaryColor,
              ),
            ],
            const SizedBox(height: 15),
            _buildDropdown(
              "Admission Type",
              ['Regular', 'Transfer', 'Scholarship', 'Special'],
              _studentCategory,
              (v) => setState(() => _studentCategory = v!),
              isDark,
              primaryColor,
            ),
            const SizedBox(height: 40),

            // 🚨 GUARDIAN / LOGIN SECTION
            _buildSectionTitle(
              "Parent/Guardian Profile",
              Icons.family_restroom_rounded,
            ),
            const SizedBox(height: 10),

            // 🚨 LOGIN METHOD TOGGLE
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withOpacity(0.05)
                    : Colors.grey[200],
                borderRadius: BorderRadius.circular(15),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() {
                        _usePhoneAsLogin = false;
                        _loginPhoneController.clear();
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: !_usePhoneAsLogin
                              ? primaryColor
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Text(
                            "Use Email to Login",
                            style: TextStyle(
                              color: !_usePhoneAsLogin
                                  ? Colors.white
                                  : Colors.grey,
                              fontWeight: FontWeight.bold,
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
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: _usePhoneAsLogin
                              ? primaryColor
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Text(
                            "Use Phone to Login",
                            style: TextStyle(
                              color: _usePhoneAsLogin
                                  ? Colors.white
                                  : Colors.grey,
                              fontWeight: FontWeight.bold,
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

            _buildTextField(
              _parentNameController,
              "Parent/Guardian Full Name",
              Icons.person,
              isDark,
            ),
            const SizedBox(height: 15),

            // 🚨 DYNAMIC LOGIN FIELDS
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _usePhoneAsLogin
                  ? _buildPhoneLoginFields(isDark, primaryColor)
                  : _buildEmailLoginFields(isDark, primaryColor),
            ),

            const SizedBox(height: 15),
            _buildTextField(
              _addressController,
              "Home Address",
              Icons.location_on,
              isDark,
              maxLines: 2,
            ),

            const SizedBox(height: 30),
            _buildSectionTitle("Parent Login Setup", Icons.security_outlined),
            const SizedBox(height: 15),
            _buildPasswordField(
              _parentPasswordController,
              "Create Parent Password",
              _isObscure1,
              (v) => setState(() => _isObscure1 = v),
              isDark,
            ),
            const SizedBox(height: 15),
            _buildPasswordField(
              _parentConfirmPasswordController,
              "Confirm Password",
              _isObscure2,
              (v) => setState(() => _isObscure2 = v),
              isDark,
            ),

            const SizedBox(height: 50),

            // 🚨 SUBMIT BUTTON
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                onPressed: _isLoading ? null : _registerStudent,
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        "SUBMIT ENROLLMENT",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 1,
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

  // --- COMPONENT HELPERS ---

  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Colors.grey, size: 20),
        const SizedBox(width: 8),
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.grey,
            letterSpacing: 1.2,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildTextField(
    TextEditingController ctrl,
    String label,
    IconData? icon,
    bool isDark, {
    bool isRequired = true,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: ctrl,
      maxLines: maxLines,
      validator: isRequired
          ? (v) => v!.trim().isEmpty ? "Required field" : null
          : null,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: icon != null ? Icon(icon, color: Colors.grey) : null,
        filled: true,
        fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.grey[50],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide(
            color: isDark ? Colors.white10 : Colors.grey.shade300,
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
  ) {
    return TextFormField(
      controller: ctrl,
      obscureText: isObscure,
      validator: (v) {
        if (v!.isEmpty) return "Password required";
        if (v.length < 6) return "Must be at least 6 chars";
        if (ctrl == _parentConfirmPasswordController &&
            v != _parentPasswordController.text) {
          return "Passwords do not match";
        }
        return null;
      },
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.lock_outline, color: Colors.grey),
        suffixIcon: IconButton(
          icon: Icon(
            isObscure ? Icons.visibility_off : Icons.visibility,
            color: Colors.grey,
          ),
          onPressed: () => onToggle(!isObscure),
        ),
        filled: true,
        fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.grey[50],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide(
            color: isDark ? Colors.white10 : Colors.grey.shade300,
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
  ) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey[50],
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade300,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: value,
          hint: Padding(
            padding: const EdgeInsets.only(left: 15),
            child: Text(hint, style: const TextStyle(color: Colors.grey)),
          ),
          icon: Padding(
            padding: const EdgeInsets.only(right: 15),
            child: Icon(Icons.arrow_drop_down, color: primaryColor),
          ),
          items: items
              .map(
                (e) => DropdownMenuItem(
                  value: e,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 15),
                    child: Text(e),
                  ),
                ),
              )
              .toList(),
          onChanged: onChanged,
          dropdownColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
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
          Icons.email_outlined,
          isDark,
        ),
        const SizedBox(height: 15),
        _buildTextField(
          _parentPhoneController,
          "Contact Phone Number (Optional)",
          Icons.phone,
          isDark,
          isRequired: false,
        ),
      ],
    );
  }

  Widget _buildPhoneLoginFields(bool isDark, Color primaryColor) {
    return Column(
      key: const ValueKey('phone_login'),
      children: [
        TextFormField(
          controller: _loginPhoneController,
          keyboardType: TextInputType.phone,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          validator: (v) =>
              v!.trim().isEmpty ? "Phone required for login" : null,
          decoration: InputDecoration(
            labelText: "Login Phone Number",
            hintText: "08012345678",
            prefixIcon: const Padding(
              padding: EdgeInsets.all(15),
              child: Text(
                "🇳🇬 +234",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            filled: true,
            fillColor: isDark
                ? Colors.white.withOpacity(0.05)
                : Colors.grey[50],
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide(
                color: isDark ? Colors.white10 : Colors.grey.shade300,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "Parents will log in using this number exactly as entered.",
          style: TextStyle(color: Colors.orange[700], fontSize: 12),
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
    return Scaffold(
      appBar: AppBar(
        title: const Text("System Check"),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.warning_amber_rounded, size: 80, color: Colors.orange),
              const SizedBox(height: 20),
              const Text(
                "Configuration Required",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              const Text(
                "Please define active classes in the Setup Wizard.",
                textAlign: TextAlign.center,
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
                    ),
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
