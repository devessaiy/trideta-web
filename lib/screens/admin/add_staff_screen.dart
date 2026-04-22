import 'package:trideta_v2/utils/auth_error_handler.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// 🚨 UPDATED ABSOLUTE IMPORTS
import 'package:trideta_v2/main.dart'; // For isInteractingWithSystem if needed

class AddStaffScreen extends StatefulWidget {
  const AddStaffScreen({super.key});

  @override
  State<AddStaffScreen> createState() => _AddStaffScreenState();
}

class _AddStaffScreenState extends State<AddStaffScreen> with AuthErrorHandler {
  final _formKey = GlobalKey<FormState>();
  final _supabase = Supabase.instance.client;

  // --- CONTROLLERS ---
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _designationController = TextEditingController();

  // 🚨 PASSWORD CONTROLLERS
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  // --- STATE ---
  XFile? _pickedFile;
  Uint8List? _webImage;
  bool _isLoading = false;

  String _selectedRole = 'Teacher';
  String? _selectedClass; // Only needed if role is Teacher
  List<String> _schoolClasses = [];

  // --- PASSWORD STATE ---
  bool _isObscure1 = true;
  bool _isObscure2 = true;
  String _passwordStrength = "";
  Color _strengthColor = Colors.transparent;
  String _matchStatus = "";
  Color _matchColor = Colors.transparent;

  @override
  void initState() {
    super.initState();
    _fetchSchoolClasses();
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _designationController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // --- 1. FETCH CLASSES (If assigning a teacher) ---
  Future<void> _fetchSchoolClasses() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final profile = await _supabase
          .from('profiles')
          .select('school_id')
          .eq('id', user.id)
          .single();

      final classesRes = await _supabase
          .from('classes')
          .select('name')
          .eq('school_id', profile['school_id'])
          .order('list_order', ascending: true);

      if (mounted) {
        setState(() {
          _schoolClasses = (classesRes as List)
              .map((c) => c['name'].toString())
              .toList();
        });
      }
    } catch (e) {
      debugPrint("Error fetching classes: $e");
    }
  }

  // --- 2. PICK PASSPORT IMAGE ---
  Future<void> _pickImage() async {
    setState(() => isInteractingWithSystem = true);
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
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

  // --- 3. PASSWORD LOGIC ---
  void _checkPasswordStrength(String val, Color primaryColor) {
    if (val.isEmpty) {
      setState(() => _passwordStrength = "");
      _checkMatch(_confirmPasswordController.text);
      return;
    }

    bool hasLetters = RegExp(r'[a-zA-Z]').hasMatch(val);
    bool hasNumbers = RegExp(r'[0-9]').hasMatch(val);
    bool hasSpecial = RegExp(r'[!@#\$&*~%]').hasMatch(val);

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
    _checkMatch(_confirmPasswordController.text);
  }

  void _checkMatch(String val) {
    if (val.isEmpty) {
      setState(() => _matchStatus = "");
      return;
    }

    if (val == _passwordController.text) {
      _matchStatus = "Passwords match";
      _matchColor = Colors.green;
    } else {
      _matchStatus = "Passwords do not match";
      _matchColor = Colors.red;
    }
    setState(() {});
  }

  // --- 4. SUBMIT TO BACKEND ---
  Future<void> _submitRegistration() async {
    if (!_formKey.currentState!.validate()) {
      showAuthErrorDialog("Please fill all required fields.");
      return;
    }

    String pwd = _passwordController.text;
    if (pwd.length < 6 ||
        !RegExp(r'[a-zA-Z]').hasMatch(pwd) ||
        !RegExp(r'[0-9]').hasMatch(pwd)) {
      showAuthErrorDialog(
        "Password is too weak. It must be at least 6 characters and contain letters and numbers.",
      );
      return;
    }
    if (pwd != _confirmPasswordController.text) {
      showAuthErrorDialog("Passwords do not match.");
      return;
    }

    if (_selectedRole == 'Teacher' && _selectedClass == null) {
      showAuthErrorDialog("Please assign a class to this teacher.");
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

      String? avatarUrl;

      // Upload image if selected
      if (_pickedFile != null && _webImage != null) {
        final fileExt = _pickedFile!.name.split('.').last;
        final fileName =
            'staff_${DateTime.now().millisecondsSinceEpoch}.$fileExt';
        final path = 'avatars/$fileName';

        await _supabase.storage
            .from('profiles')
            .uploadBinary(
              path,
              _webImage!,
              fileOptions: FileOptions(contentType: 'image/$fileExt'),
            );
        avatarUrl = _supabase.storage.from('profiles').getPublicUrl(path);
      }

      // 🚨 CALL EDGE FUNCTION OR RPC TO CREATE USER
      // NOTE: Creating a new auth user from an already logged-in user usually
      // requires a Supabase Edge Function or a secure RPC call so the Admin
      // doesn't get logged out.
      // For this implementation, we will assume you have an RPC called 'create_staff_user'
      // that handles the auth.admin.createUser() bypass securely.

      final response = await _supabase.rpc(
        'create_staff_user',
        params: {
          'target_email': _emailController.text.trim(),
          'target_password': _passwordController.text.trim(),
          'target_role': _selectedRole.toLowerCase(),
          'school_id': schoolId,
          'first_name': _firstNameController.text.trim(),
          'last_name': _lastNameController.text.trim(),
          'phone': _phoneController.text.trim(),
          'assigned_class': _selectedRole == 'Teacher' ? _selectedClass : null,
          'designation': _designationController.text.trim(),
          'avatar_url': avatarUrl,
        },
      );

      if (response != null && response['error'] != null) {
        throw response['error'];
      }

      if (mounted) {
        setState(() => _isLoading = false);
        showSuccessDialog(
          "Staff Added",
          "Successfully registered ${_firstNameController.text} as a $_selectedRole.",
          onOkay: () =>
              Navigator.pop(context, true), // Returns true to refresh list
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      String errorMsg = e.toString();
      if (errorMsg.contains("already registered")) {
        errorMsg = "An account with this email already exists.";
      }
      showAuthErrorDialog("Failed to add staff: $errorMsg");
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC);
    Color textColor = isDark ? Colors.white : Colors.black87;
    Color subTextColor = isDark ? Colors.grey.shade400 : Colors.grey.shade600;
    Color fieldBgColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    Color primaryColor = Theme.of(context).primaryColor;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text(
          "Register Staff",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 0,
      ),
      // 🚨 SHAPE-SHIFTER: LayoutBuilder added for Web Responsiveness
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth > 800) {
            // 💻 DESKTOP LAYOUT (Constrained Centered Card)
            return Center(
              child: Container(
                width: 700,
                margin: const EdgeInsets.symmetric(vertical: 40),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(40),
                    child: _buildFormContent(
                      isDark,
                      primaryColor,
                      textColor,
                      subTextColor,
                      fieldBgColor,
                      isDesktop: true,
                    ),
                  ),
                ),
              ),
            );
          } else {
            // 📱 MOBILE LAYOUT
            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: _buildFormContent(
                  isDark,
                  primaryColor,
                  textColor,
                  subTextColor,
                  fieldBgColor,
                  isDesktop: false,
                ),
              ),
            );
          }
        },
      ),
    );
  }

  // 🚨 EXTRACTED FORM CONTENT
  Widget _buildFormContent(
    bool isDark,
    Color primaryColor,
    Color textColor,
    Color subTextColor,
    Color fieldBgColor, {
    required bool isDesktop,
  }) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Stack(
              children: [
                CircleAvatar(
                  radius: isDesktop ? 60 : 50,
                  backgroundColor: primaryColor.withOpacity(0.1),
                  backgroundImage: _webImage != null
                      ? MemoryImage(_webImage!)
                      : null,
                  child: _webImage == null
                      ? Icon(
                          Icons.person,
                          size: isDesktop ? 60 : 50,
                          color: primaryColor,
                        )
                      : null,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: _pickImage,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: primaryColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(
                        Icons.camera_alt,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            "Upload Staff Passport",
            textAlign: TextAlign.center,
            style: TextStyle(color: subTextColor, fontSize: 12),
          ),
          const SizedBox(height: 30),

          // --- ROLE SELECTION ---
          const Text(
            "STAFF ROLE & ACCESS",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 10),
          _buildDropdown(
            "Account Type (Role)",
            ['Teacher', 'Bursar', 'Admin'],
            _selectedRole,
            (val) {
              setState(() {
                _selectedRole = val!;
                if (val != 'Teacher') _selectedClass = null;
              });
            },
            isDark,
            primaryColor,
            textColor,
            subTextColor,
            fieldBgColor,
          ),
          const SizedBox(height: 15),

          if (_selectedRole == 'Teacher') ...[
            _buildDropdown(
              "Assigned Class",
              _schoolClasses,
              _selectedClass,
              (val) => setState(() => _selectedClass = val),
              isDark,
              primaryColor,
              textColor,
              subTextColor,
              fieldBgColor,
            ),
            const SizedBox(height: 15),
          ],

          _buildTextField(
            "Official Designation (e.g. Head of Science)",
            Icons.work,
            _designationController,
            isDark,
            primaryColor,
            textColor,
            subTextColor,
            fieldBgColor,
          ),
          const SizedBox(height: 25),

          // --- PERSONAL INFO ---
          const Text(
            "PERSONAL INFORMATION",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 10),

          Row(
            children: [
              Expanded(
                child: _buildTextField(
                  "First Name",
                  Icons.person_outline,
                  _firstNameController,
                  isDark,
                  primaryColor,
                  textColor,
                  subTextColor,
                  fieldBgColor,
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: _buildTextField(
                  "Last Name",
                  Icons.person_outline,
                  _lastNameController,
                  isDark,
                  primaryColor,
                  textColor,
                  subTextColor,
                  fieldBgColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),

          _buildTextField(
            "Email Address (Login ID)",
            Icons.email_outlined,
            _emailController,
            isDark,
            primaryColor,
            textColor,
            subTextColor,
            fieldBgColor,
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 15),

          _buildTextField(
            "Phone Number",
            Icons.phone_outlined,
            _phoneController,
            isDark,
            primaryColor,
            textColor,
            subTextColor,
            fieldBgColor,
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 25),

          // --- PASSWORD SETUP ---
          const Text(
            "SECURITY SETUP",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 10),

          TextFormField(
            controller: _passwordController,
            obscureText: _isObscure1,
            style: TextStyle(color: textColor),
            onChanged: (val) => _checkPasswordStrength(val, primaryColor),
            validator: (v) => v!.isEmpty ? "Required" : null,
            decoration: InputDecoration(
              labelText: "Temporary Login Password",
              labelStyle: TextStyle(color: subTextColor, fontSize: 14),
              prefixIcon: Icon(
                Icons.lock_outline,
                color: primaryColor,
                size: 20,
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  _isObscure1 ? Icons.visibility : Icons.visibility_off,
                  color: subTextColor,
                ),
                onPressed: () => setState(() => _isObscure1 = !_isObscure1),
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
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          const SizedBox(height: 15),

          TextFormField(
            controller: _confirmPasswordController,
            obscureText: _isObscure2,
            style: TextStyle(color: textColor),
            onChanged: _checkMatch,
            validator: (v) => v!.isEmpty ? "Required" : null,
            decoration: InputDecoration(
              labelText: "Confirm Password",
              labelStyle: TextStyle(color: subTextColor, fontSize: 14),
              prefixIcon: Icon(Icons.lock_reset, color: primaryColor, size: 20),
              suffixIcon: IconButton(
                icon: Icon(
                  _isObscure2 ? Icons.visibility : Icons.visibility_off,
                  color: subTextColor,
                ),
                onPressed: () => setState(() => _isObscure2 = !_isObscure2),
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
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          const SizedBox(height: 30),

          SizedBox(
            height: 55,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              onPressed: _isLoading ? null : _submitRegistration,
              child: _isLoading
                  ? const SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 3,
                      ),
                    )
                  : const Text(
                      "REGISTER STAFF",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        letterSpacing: 1.2,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // --- UI HELPERS ---
  Widget _buildTextField(
    String label,
    IconData icon,
    TextEditingController controller,
    bool isDark,
    Color primaryColor,
    Color textColor,
    Color subTextColor,
    Color fieldBgColor, {
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      style: TextStyle(color: textColor),
      validator: (v) => v!.isEmpty ? "Required" : null,
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
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: subTextColor, fontSize: 14),
        prefixIcon: Icon(Icons.badge, color: primaryColor, size: 20),
        filled: true,
        fillColor: fieldBgColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
