import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trideta_v2/utils/auth_error_handler.dart';
import 'package:trideta_v2/main.dart'; // To access isInteractingWithSystem

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
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  // --- STATE ---
  bool _isLoading = false;
  bool _isObscure1 = true;
  bool _isObscure2 = true;

  String _passwordStrength = "";
  Color _strengthColor = Colors.grey;
  bool _passwordsMatch = true;

  String _selectedRole = 'Teacher';

  XFile? _pickedFile;
  Uint8List? _webImage;

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

  // --- 1. PICK PASSPORT IMAGE WITH COMPRESSION ---
  Future<void> _pickImage() async {
    setState(() => isInteractingWithSystem = true);
    final ImagePicker picker = ImagePicker();

    // Auto-compression to prevent massive 5MB+ photos
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
      maxWidth: 600,
      maxHeight: 600,
    );

    setState(() => isInteractingWithSystem = false);

    if (image != null) {
      final bytes = await image.readAsBytes();

      // Safety net: Reject if it somehow remains over 500KB
      if (bytes.lengthInBytes > 500 * 1024) {
        showAuthErrorDialog(
          "Image is too large. Please select a smaller photo.",
        );
        return;
      }

      setState(() {
        _pickedFile = image;
        _webImage = bytes;
      });
    }
  }

  // --- 2. PASSWORD LOGIC ---
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
      setState(() => _passwordsMatch = true);
      return;
    }
    setState(() {
      _passwordsMatch = val == _passwordController.text;
    });
  }

  // --- 3. SUBMIT FORM (EDGE FUNCTION TRIGGER) ---
  Future<void> _saveStaff() async {
    if (!_formKey.currentState!.validate()) return;

    String pwd = _passwordController.text;
    if (pwd.length < 6) {
      showAuthErrorDialog("Password must be at least 6 characters.");
      return;
    }
    if (pwd != _confirmPasswordController.text) {
      showAuthErrorDialog("Passwords do not match.");
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

        final path = '$schoolId/$fileName';

        // Storing inside staff_passports bucket
        await _supabase.storage
            .from('staff_passports')
            .uploadBinary(
              path,
              _webImage!,
              fileOptions: FileOptions(contentType: 'image/$fileExt'),
            );

        avatarUrl = _supabase.storage
            .from('staff_passports')
            .getPublicUrl(path);
      }

      // 🚨 PERFECTLY ALIGNED EDGE FUNCTION TRIGGER 🚨
      // Replace 'create-staff-account' below with your actual Edge Function name if it is different!
      await _supabase.functions.invoke(
        'create-staff-account',
        body: {
          'email': _emailController.text.trim(),
          'password': _passwordController.text.trim(),
          'first_name': _firstNameController.text.trim(),
          'last_name': _lastNameController.text.trim(),
          'school_id': schoolId,
          'role': _selectedRole.toLowerCase(),
          'phone': _phoneController.text.trim(),
          'designation': _designationController.text.trim(),
          'passport_url': avatarUrl,
        },
      );

      if (mounted) {
        setState(() => _isLoading = false);
        showSuccessDialog(
          "Staff Added",
          "Successfully registered ${_firstNameController.text} as a $_selectedRole.",
          onOkay: () =>
              Navigator.pop(context, true), // Returns true to refresh list
        );
      }
    } on FunctionException catch (e) {
      // Handles specific Edge Function errors sent back from your catch block
      setState(() => _isLoading = false);
      showAuthErrorDialog("Server Error: ${e.details ?? e.reasonPhrase}");
    } catch (e) {
      setState(() => _isLoading = false);
      String errorMsg = e.toString();
      if (errorMsg.contains("already registered") ||
          errorMsg.contains("User already exists")) {
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
                    color: fieldBgColor,
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
                    child: _buildFormContent(
                      isDark,
                      primaryColor,
                      textColor,
                      subTextColor,
                    ),
                  ),
                ),
              ),
            );
          } else {
            // 📱 MOBILE LAYOUT
            return _buildFormContent(
              isDark,
              primaryColor,
              textColor,
              subTextColor,
            );
          }
        },
      ),
    );
  }

  Widget _buildFormContent(
    bool isDark,
    Color primaryColor,
    Color textColor,
    Color subTextColor,
  ) {
    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- HEADER PHOTO ---
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
                    "Staff Photo",
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),

            // --- STAFF ROLE (Cleaned up: No Class Assignment here) ---
            _buildSectionTitle("Employment Information", Icons.work_outline),
            const SizedBox(height: 15),
            Row(
              children: [
                Expanded(
                  child: _buildDropdown(
                    "Role",
                    ['Teacher', 'Admin', 'Bursar', 'Principal'],
                    _selectedRole,
                    (v) => setState(() {
                      _selectedRole = v!;
                    }),
                    isDark,
                    primaryColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),
            _buildTextField(
              _designationController,
              "Official Designation (e.g., Head of Science)",
              Icons.badge_outlined,
              isDark,
              isRequired: false,
            ),
            const SizedBox(height: 30),

            // --- PERSONAL DETAILS ---
            _buildSectionTitle("Personal Details", Icons.person_outline),
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
                    _lastNameController,
                    "Last Name",
                    null,
                    isDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),
            _buildTextField(
              _phoneController,
              "Phone Number",
              Icons.phone_outlined,
              isDark,
              isNumber: true,
            ),
            const SizedBox(height: 30),

            // --- AUTH DETAILS ---
            _buildSectionTitle("System Access", Icons.security_outlined),
            const SizedBox(height: 15),
            _buildTextField(
              _emailController,
              "Email Address",
              Icons.email_outlined,
              isDark,
              isEmail: true,
            ),
            const SizedBox(height: 15),

            // PASSWORD
            TextFormField(
              controller: _passwordController,
              obscureText: _isObscure1,
              onChanged: (val) => _checkPasswordStrength(val, primaryColor),
              validator: (v) {
                if (v!.isEmpty) return "Required";
                if (v.length < 6) return "Min 6 characters";
                return null;
              },
              decoration: InputDecoration(
                labelText: "Create Password",
                prefixIcon: const Icon(Icons.lock_outline, color: Colors.grey),
                suffixIcon: IconButton(
                  icon: Icon(
                    _isObscure1 ? Icons.visibility_off : Icons.visibility,
                    color: Colors.grey,
                  ),
                  onPressed: () => setState(() => _isObscure1 = !_isObscure1),
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
            if (_passwordStrength.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8, left: 10),
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

            // CONFIRM PASSWORD
            TextFormField(
              controller: _confirmPasswordController,
              obscureText: _isObscure2,
              onChanged: _checkMatch,
              validator: (v) => v!.isEmpty ? "Required" : null,
              decoration: InputDecoration(
                labelText: "Confirm Password",
                prefixIcon: const Icon(Icons.lock_outline, color: Colors.grey),
                suffixIcon: IconButton(
                  icon: Icon(
                    _isObscure2 ? Icons.visibility_off : Icons.visibility,
                    color: Colors.grey,
                  ),
                  onPressed: () => setState(() => _isObscure2 = !_isObscure2),
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
            if (!_passwordsMatch && _confirmPasswordController.text.isNotEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 8, left: 10),
                child: Text(
                  "Passwords do not match",
                  style: TextStyle(
                    color: Colors.red,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

            const SizedBox(height: 50),

            // --- SUBMIT ---
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
                onPressed: _isLoading ? null : _saveStaff,
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        "REGISTER STAFF",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 1.5,
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

  // --- HELPERS ---

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
    bool isEmail = false,
    bool isNumber = false,
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType: isEmail
          ? TextInputType.emailAddress
          : (isNumber ? TextInputType.phone : TextInputType.text),
      inputFormatters: isNumber
          ? [FilteringTextInputFormatter.digitsOnly]
          : null,
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
}
