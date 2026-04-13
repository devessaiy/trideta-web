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
  final _parentPhoneController = TextEditingController();
  final _addressController = TextEditingController();

  // 🚨 NEW PASSWORD CONTROLLERS
  final _parentPasswordController = TextEditingController();
  final _parentConfirmPasswordController = TextEditingController();

  // --- STATE ---
  XFile? _pickedFile;
  Uint8List? _webImage;
  final ImagePicker _picker = ImagePicker();

  List<String> _activeClasses = [];
  bool _isLoading = true;
  bool _hasClasses = false;

  String _currentSchoolName = "";
  String _selectedSession = "2025/2026";
  String? _selectedClass;
  String? _selectedDepartment;
  String _selectedGender = "Male";
  String _studentCategory = "Regular";
  String _generatedID = "---/--/--/---";

  // 🚨 PASSWORD STATE VARIABLES (Cloned from Registration Screen)
  bool _isObscure1 = true;
  bool _isObscure2 = true;
  String _passwordStrength = "";
  Color _strengthColor = Colors.transparent;
  String _matchStatus = "";
  Color _matchColor = Colors.transparent;

  @override
  void initState() {
    super.initState();
    _fetchSchoolConfig();
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    _dobController.dispose();
    _parentNameController.dispose();
    _parentEmailController.dispose();
    _parentPhoneController.dispose();
    _addressController.dispose();
    _parentPasswordController.dispose();
    _parentConfirmPasswordController.dispose();
    super.dispose();
  }

  // --- 🚨 PASSWORD VALIDATION LOGIC (Cloned from Registration Screen) ---
  void _checkPasswordStrength(String val) {
    if (val.isEmpty) {
      setState(() => _passwordStrength = "");
      _checkMatch(_parentConfirmPasswordController.text);
      return;
    }

    bool hasLetters = RegExp(r'[a-zA-Z]').hasMatch(val);
    bool hasNumbers = RegExp(r'[0-9]').hasMatch(val);
    bool hasSpecial = RegExp(r'[!@#\$&*~%]').hasMatch(val);

    Color primaryColor = Theme.of(context).primaryColor;

    if (val.length < 6) {
      _passwordStrength = "Too short (Min 6 characters)";
      _strengthColor = Colors.red;
    } else if (!hasLetters || !hasNumbers) {
      _passwordStrength = "Weak (Add letters & numbers)";
      _strengthColor = Colors.orange;
    } else if (hasLetters && hasNumbers && !hasSpecial && val.length >= 6) {
      _passwordStrength = "Good Password";
      _strengthColor = primaryColor;
    } else if (hasLetters && hasNumbers && hasSpecial && val.length >= 8) {
      _passwordStrength = "Strong Password";
      _strengthColor = Colors.green;
    } else {
      _passwordStrength = "Good Password";
      _strengthColor = primaryColor;
    }

    setState(() {});
    _checkMatch(_parentConfirmPasswordController.text);
  }

  void _checkMatch(String val) {
    if (val.isEmpty) {
      setState(() => _matchStatus = "");
      return;
    }

    if (val == _parentPasswordController.text) {
      _matchStatus = "Passwords match";
      _matchColor = Colors.green;
    } else {
      _matchStatus = "Passwords do not match";
      _matchColor = Colors.red;
    }
    setState(() {});
  }

  // --- LOGIC: EXIT GUARD ---
  bool _isFormDirty() {
    return _firstNameController.text.isNotEmpty ||
        _parentNameController.text.isNotEmpty ||
        _pickedFile != null;
  }

  Future<bool> _onWillPop() async {
    if (!_isFormDirty()) return true;
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    return await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Text("Discard Changes?"),
            content: const Text(
              "Leaving now will lose all the student data you've entered. Exit anyway?",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text("Stay"),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(
                  "Discard",
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ) ??
        false;
  }

  // --- LOGIC: FETCH DATA & SMART ID ---
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
          .select('name')
          .eq('school_id', schoolId)
          .order('list_order', ascending: true);

      if (mounted) {
        setState(() {
          _currentSchoolName = school['name'] ?? "";

          if (classesData.isNotEmpty) {
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

  // --- LOGIC: IMAGE & SUBMIT ---
  Future<void> _pickImage() async {
    setState(() => isInteractingWithSystem = true);
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 600,
      maxHeight: 600,
      imageQuality: 70,
    );
    setState(() => isInteractingWithSystem = false);
    if (image != null) {
      final bytes = await image.readAsBytes();
      setState(() {
        _pickedFile = image;
        _webImage = bytes;
      });
    }
  }

  Future<void> _registerStudent() async {
    if (!_formKey.currentState!.validate() || _pickedFile == null) {
      showAuthErrorDialog(
        "Incomplete details. Please upload a passport photo and fill all required fields.",
      );
      return;
    }

    // 🚨 NEW: Validating using the simple rules
    String pwd = _parentPasswordController.text;
    if (pwd.length < 6 ||
        !RegExp(r'[a-zA-Z]').hasMatch(pwd) ||
        !RegExp(r'[0-9]').hasMatch(pwd)) {
      showAuthErrorDialog(
        "Your password is too weak. It must be at least 6 characters long and contain both letters and numbers.",
      );
      return;
    }

    if (pwd != _parentConfirmPasswordController.text) {
      showAuthErrorDialog(
        "The passwords you entered do not match. Please check them and try again.",
      );
      return;
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
      final email = _parentEmailController.text.trim();
      final password = _parentPasswordController.text;

      // SIBLING CHECK
      final List existing = await _supabase
          .from('students')
          .select('parent_account_created, first_name')
          .eq('parent_email', email)
          .eq('school_id', schoolId)
          .limit(1);

      bool isExistingParent = existing.isNotEmpty;
      bool accountAlreadyCreated =
          isExistingParent && existing[0]['parent_account_created'] == true;

      if (isExistingParent) {
        setState(() => _isLoading = false);
        bool confirmLink = await _showSiblingDialog(
          existing[0]['first_name'],
          email,
        );
        if (!confirmLink) return;
        setState(() => _isLoading = true);
      } else {
        // IF NOT A SIBLING, CREATE THE AUTH ACCOUNT
        try {
          await _supabase.functions.invoke(
            'create-parent-account',
            body: {
              'email': email,
              'password': password,
              'phone': _parentPhoneController.text.trim(),
              'studentName': _firstNameController.text.trim(),
            },
          );
          accountAlreadyCreated = true;
        } catch (e) {
          setState(() => _isLoading = false);
          showAuthErrorDialog(
            "Failed to create parent login account on the server. Ensure the email is valid and the edge function is running.",
          );
          return;
        }
      }

      String finalID = _generatedID.replaceAll(
        "XXX",
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
        'class_level': _selectedClass,
        'department': _selectedDepartment,
        'gender': _selectedGender,
        'dob': _dobController.text.trim(),
        'passport_url': passportUrl,
        'parent_name': _parentNameController.text.trim(),
        'parent_email': email,
        'parent_phone': _parentPhoneController.text.trim(),
        'address': _addressController.text.trim(),
        'session_admitted': _selectedSession,
        'category': _studentCategory,
        'parent_account_created': accountAlreadyCreated,
      });

      if (mounted) {
        setState(() => _isLoading = false);
        showSuccessDialog(
          "Admission Successful",
          "Student ID: $finalID\n\n${isExistingParent ? 'Linked to existing parent account.' : 'Parent login credentials generated securely.'}",
          onOkay: () => Navigator.pop(context),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      showAuthErrorDialog(
        "Admission failed. We couldn't save the student record.",
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _activeClasses.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_hasClasses) {
      return AdmissionLockOverlay(onRefresh: () => _fetchSchoolConfig());
    }

    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC);
    Color cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    Color primaryColor = Theme.of(context).primaryColor;
    Color textColor = isDark ? Colors.white : Colors.black87;
    Color subTextColor = isDark ? Colors.white54 : Colors.grey[600]!;
    Color fieldBgColor = isDark
        ? Colors.white.withOpacity(0.03)
        : Colors.grey[50]!;

    bool showDepartment =
        _selectedClass != null &&
        _selectedClass!.toUpperCase().startsWith("SS");

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final bool shouldPop = await _onWillPop();
        if (shouldPop && mounted) Navigator.pop(context);
      },
      child: Scaffold(
        backgroundColor: bgColor,
        appBar: AppBar(
          title: const Text(
            "Student Admission",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          centerTitle: true,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPassportHeader(isDark, primaryColor),
                const SizedBox(height: 30),

                _buildSectionHeader(
                  Icons.school_rounded,
                  "Academic Details",
                  primaryColor,
                ),
                _buildFormCard(cardColor, [
                  _buildDropdown(
                    "Session",
                    ["2024/2025", "2025/2026"],
                    _selectedSession,
                    (v) {
                      setState(() {
                        _selectedSession = v!;
                        _updateSmartID();
                      });
                    },
                    isDark,
                    primaryColor,
                    textColor,
                    subTextColor,
                    fieldBgColor,
                  ),
                  const SizedBox(height: 15),
                  _buildDropdown(
                    "Class",
                    _activeClasses,
                    _selectedClass,
                    (v) {
                      setState(() {
                        _selectedClass = v!;
                        _updateSmartID();
                        if (!showDepartment) _selectedDepartment = null;
                      });
                    },
                    isDark,
                    primaryColor,
                    textColor,
                    subTextColor,
                    fieldBgColor,
                  ),
                  if (showDepartment) ...[
                    const SizedBox(height: 15),
                    _buildDropdown(
                      "Class Category / Department",
                      ["Science", "Art", "Commercial"],
                      _selectedDepartment,
                      (v) => setState(() => _selectedDepartment = v),
                      isDark,
                      primaryColor,
                      textColor,
                      subTextColor,
                      fieldBgColor,
                    ),
                  ],
                  const SizedBox(height: 15),
                  _buildDropdown(
                    "Category",
                    ["Regular", "Transfer", "Scholarship"],
                    _studentCategory,
                    (v) => setState(() => _studentCategory = v!),
                    isDark,
                    primaryColor,
                    textColor,
                    subTextColor,
                    fieldBgColor,
                  ),
                ]),

                const SizedBox(height: 30),
                _buildSectionHeader(
                  Icons.person_rounded,
                  "Student Information",
                  primaryColor,
                ),
                _buildFormCard(cardColor, [
                  _buildTextField(
                    "First Name",
                    _firstNameController,
                    Icons.person,
                    isDark,
                    primaryColor,
                    textColor,
                    subTextColor,
                    fieldBgColor,
                  ),
                  const SizedBox(height: 15),
                  _buildTextField(
                    "Middle Name (Optional)",
                    _middleNameController,
                    Icons.person_outline,
                    isDark,
                    primaryColor,
                    textColor,
                    subTextColor,
                    fieldBgColor,
                    optional: true,
                  ),
                  const SizedBox(height: 15),
                  _buildTextField(
                    "Surname / Last Name",
                    _lastNameController,
                    Icons.person,
                    isDark,
                    primaryColor,
                    textColor,
                    subTextColor,
                    fieldBgColor,
                  ),
                  const SizedBox(height: 15),
                  _buildDropdown(
                    "Gender",
                    ["Male", "Female"],
                    _selectedGender,
                    (v) => setState(() => _selectedGender = v!),
                    isDark,
                    primaryColor,
                    textColor,
                    subTextColor,
                    fieldBgColor,
                  ),
                  const SizedBox(height: 15),
                  _buildDateField(
                    context,
                    isDark,
                    primaryColor,
                    textColor,
                    subTextColor,
                    fieldBgColor,
                  ),
                ]),

                const SizedBox(height: 30),
                _buildSectionHeader(
                  Icons.family_restroom_rounded,
                  "Parent Contact & Login",
                  primaryColor,
                ),
                _buildFormCard(cardColor, [
                  _buildTextField(
                    "Parent Full Name",
                    _parentNameController,
                    Icons.supervisor_account,
                    isDark,
                    primaryColor,
                    textColor,
                    subTextColor,
                    fieldBgColor,
                  ),
                  const SizedBox(height: 15),
                  _buildTextField(
                    "Parent Email (Login ID)",
                    _parentEmailController,
                    Icons.email,
                    isDark,
                    primaryColor,
                    textColor,
                    subTextColor,
                    fieldBgColor,
                    type: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 15),
                  _buildTextField(
                    "Phone Number",
                    _parentPhoneController,
                    Icons.phone,
                    isDark,
                    primaryColor,
                    textColor,
                    subTextColor,
                    fieldBgColor,
                    type: TextInputType.phone,
                  ),
                  const SizedBox(height: 15),

                  // 🚨 NEW: PASSWORD FIELDS CLONED FROM REGISTRATION SCREEN
                  TextFormField(
                    controller: _parentPasswordController,
                    obscureText: _isObscure1,
                    onChanged: _checkPasswordStrength,
                    style: TextStyle(color: textColor),
                    validator: (v) =>
                        v!.isEmpty ? "Please create a password" : null,
                    decoration: InputDecoration(
                      labelText: "Create Password",
                      labelStyle: TextStyle(color: subTextColor, fontSize: 14),
                      prefixIcon: Icon(
                        Icons.lock_outline_rounded,
                        color: primaryColor,
                        size: 20,
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _isObscure1 ? Icons.visibility : Icons.visibility_off,
                          color: subTextColor,
                          size: 20,
                        ),
                        onPressed: () =>
                            setState(() => _isObscure1 = !_isObscure1),
                      ),
                      filled: true,
                      fillColor: fieldBgColor,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  if (_passwordStrength.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0, left: 10.0),
                      child: Text(
                        _passwordStrength,
                        style: TextStyle(
                          color: _strengthColor,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  const SizedBox(height: 15),

                  TextFormField(
                    controller: _parentConfirmPasswordController,
                    obscureText: _isObscure2,
                    onChanged: _checkMatch,
                    style: TextStyle(color: textColor),
                    validator: (v) {
                      if (v!.isEmpty) return "Required";
                      if (v != _parentPasswordController.text)
                        return "Passwords do not match";
                      return null;
                    },
                    decoration: InputDecoration(
                      labelText: "Confirm Password",
                      labelStyle: TextStyle(color: subTextColor, fontSize: 14),
                      prefixIcon: Icon(
                        Icons.lock_reset_rounded,
                        color: primaryColor,
                        size: 20,
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _isObscure2 ? Icons.visibility : Icons.visibility_off,
                          color: subTextColor,
                          size: 20,
                        ),
                        onPressed: () =>
                            setState(() => _isObscure2 = !_isObscure2),
                      ),
                      filled: true,
                      fillColor: fieldBgColor,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  if (_matchStatus.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0, left: 10.0),
                      child: Text(
                        _matchStatus,
                        style: TextStyle(
                          color: _matchColor,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),

                  const SizedBox(height: 15),
                  _buildTextField(
                    "Residential Address",
                    _addressController,
                    Icons.home_rounded,
                    isDark,
                    primaryColor,
                    textColor,
                    subTextColor,
                    fieldBgColor,
                    lines: 2,
                  ),
                ]),

                const SizedBox(height: 40),
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
                            "COMPLETE ADMISSION",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 50),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- UI HELPERS ---

  Widget _buildPassportHeader(bool isDark, Color primaryColor) {
    return Center(
      child: Column(
        children: [
          GestureDetector(
            onTap: _pickImage,
            child: Stack(
              children: [
                Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white10 : Colors.grey[200],
                    shape: BoxShape.circle,
                    border: Border.all(color: primaryColor, width: 3),
                    image: _webImage != null
                        ? DecorationImage(
                            image: MemoryImage(_webImage!),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: _webImage == null
                      ? Icon(
                          Icons.add_a_photo_rounded,
                          color: primaryColor,
                          size: 35,
                        )
                      : null,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: CircleAvatar(
                    backgroundColor: primaryColor,
                    radius: 18,
                    child: const Icon(
                      Icons.edit,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 15),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              "PROJECTED ID: $_generatedID",
              style: TextStyle(
                color: primaryColor,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(IconData icon, String title, Color primaryColor) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: primaryColor, size: 20),
          const SizedBox(width: 10),
          Text(
            title.toUpperCase(),
            style: TextStyle(
              color: primaryColor,
              fontWeight: FontWeight.w800,
              fontSize: 13,
              letterSpacing: 1.1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormCard(Color cardColor, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller,
    IconData icon,
    bool isDark,
    Color primaryColor,
    Color textColor,
    Color subTextColor,
    Color fieldBgColor, {
    TextInputType type = TextInputType.text,
    int lines = 1,
    bool optional = false,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: type,
      maxLines: lines,
      style: TextStyle(color: textColor),
      validator: (v) => (!optional && v!.isEmpty) ? "Required" : null,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: subTextColor, fontSize: 14),
        prefixIcon: Icon(icon, color: primaryColor, size: 20),
        filled: true,
        fillColor: fieldBgColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildDropdown(
    String label,
    List<String> items,
    String? value,
    Function(String?) onChanged,
    bool isDark,
    Color primaryColor,
    Color textColor,
    Color subTextColor,
    Color fieldBgColor,
  ) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      items: items
          .map((e) => DropdownMenuItem(value: e, child: Text(e)))
          .toList(),
      onChanged: onChanged,
      dropdownColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      style: TextStyle(color: textColor),
      validator: (v) => v == null ? "Required" : null,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: subTextColor, fontSize: 14),
        prefixIcon: Icon(
          Icons.arrow_drop_down_circle_outlined,
          color: primaryColor,
          size: 20,
        ),
        filled: true,
        fillColor: fieldBgColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildDateField(
    BuildContext context,
    bool isDark,
    Color primaryColor,
    Color textColor,
    Color subTextColor,
    Color fieldBgColor,
  ) {
    return TextFormField(
      controller: _dobController,
      readOnly: true,
      style: TextStyle(color: textColor),
      onTap: () async {
        final DateTime? picked = await showDatePicker(
          context: context,
          initialDate: DateTime(2015),
          firstDate: DateTime(2000),
          lastDate: DateTime.now(),
        );
        if (picked != null) {
          setState(
            () => _dobController.text =
                "${picked.day}/${picked.month}/${picked.year}",
          );
        }
      },
      validator: (v) => v!.isEmpty ? "Required" : null,
      decoration: InputDecoration(
        labelText: "Date of Birth",
        labelStyle: TextStyle(color: subTextColor, fontSize: 14),
        prefixIcon: Icon(
          Icons.calendar_month_rounded,
          color: primaryColor,
          size: 20,
        ),
        filled: true,
        fillColor: fieldBgColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Future<bool> _showSiblingDialog(String name, String email) async {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color primaryColor = Theme.of(context).primaryColor;
    return await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Icon(
              Icons.group_add_rounded,
              color: Colors.orange,
              size: 40,
            ),
            content: Text(
              "Sibling Detected!\n\n'$email' is already linked to $name. Link to the same parent account?",
              textAlign: TextAlign.center,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text(
                  "New Account",
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: primaryColor),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(
                  "Yes, Link",
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ) ??
        false;
  }
}

// 🚨 Admission Lock Overlay
class AdmissionLockOverlay extends StatelessWidget {
  final VoidCallback onRefresh;
  const AdmissionLockOverlay({super.key, required this.onRefresh});
  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color primaryColor = Theme.of(context).primaryColor;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF121212)
          : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text("Admission Restricted"),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(30),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.domain_disabled_rounded,
                  size: 80,
                  color: Colors.orange,
                ),
              ),
              const SizedBox(height: 30),
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
