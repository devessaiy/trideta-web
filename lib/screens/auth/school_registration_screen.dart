import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// 🚨 MODULAR IMPORTS
import 'package:trideta_v2/utils/auth_error_handler.dart';
import 'package:trideta_v2/screens/auth/login_screen.dart';
import 'package:trideta_v2/services/auth_service.dart';

class SchoolRegistrationScreen extends StatefulWidget {
  const SchoolRegistrationScreen({super.key});

  @override
  State<SchoolRegistrationScreen> createState() =>
      _SchoolRegistrationScreenState();
}

class _SchoolRegistrationScreenState extends State<SchoolRegistrationScreen>
    with AuthErrorHandler {
  final _formKey = GlobalKey<FormState>();
  final _schoolNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();

  // Password Controllers
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  // Backend Service
  final _authService = AuthService();
  bool _isLoading = false;

  // Privacy Agreement State
  bool _isAgreed = false;
  bool _isFreeTierAgreed = false;

  // Password State Variables
  bool _isObscure1 = true;
  bool _isObscure2 = true;
  String _passwordStrength = "";
  Color _strengthColor = Colors.transparent;
  String _matchStatus = "";
  Color _matchColor = Colors.transparent;

  @override
  void dispose() {
    _schoolNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // --- PASSWORD VALIDATION LOGIC ---
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

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = isDark ? const Color(0xFF121212) : Colors.grey.shade50;
    Color textColor = isDark ? Colors.white : Colors.black87;
    Color primaryColor = Theme.of(context).primaryColor;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: textColor),
      ),
      // 🚨 THE MAGIC SHAPE-SHIFTER: LayoutBuilder
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth > 800) {
            // 💻 DESKTOP: Split Screen
            return Row(
              children: [
                Expanded(
                  flex: 5,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [primaryColor.withOpacity(0.8), primaryColor],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.domain_add_rounded,
                            size: 100,
                            color: Colors.white,
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            "Partner with Trideta",
                            style: TextStyle(
                              fontSize: 42,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: 2.0,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            "Bring your entire school into the cloud today.",
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.white.withOpacity(0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  flex: 5,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 550),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 40,
                          vertical: 20,
                        ),
                        child: _buildRegistrationForm(
                          isDark,
                          primaryColor,
                          isMobile: false,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          } else {
            // 📱 MOBILE: Centered Single Column
            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: _buildRegistrationForm(
                  isDark,
                  primaryColor,
                  isMobile: true,
                ),
              ),
            );
          }
        },
      ),
    );
  }

  // 🚨 EXTRACTED FORM FOR BOTH PLATFORMS
  Widget _buildRegistrationForm(
    bool isDark,
    Color primaryColor, {
    required bool isMobile,
  }) {
    Color textColor = isDark ? Colors.white : Colors.black87;
    Color subTextColor = isDark ? Colors.grey.shade400 : Colors.grey.shade600;
    Color fieldColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isMobile) ...[
            Icon(Icons.domain_add, size: 80, color: primaryColor),
            const SizedBox(height: 20),
          ],
          Text(
            "Create School Account",
            textAlign: isMobile ? TextAlign.center : TextAlign.left,
            style: TextStyle(
              fontSize: isMobile ? 24 : 32,
              fontWeight: FontWeight.bold,
              color: primaryColor,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            "Enter your administrative details below.",
            textAlign: isMobile ? TextAlign.center : TextAlign.left,
            style: TextStyle(color: subTextColor, fontSize: 16),
          ),
          const SizedBox(height: 30),

          // 1. SCHOOL NAME
          TextFormField(
            controller: _schoolNameController,
            style: TextStyle(color: textColor),
            decoration: _inputDecoration(
              "School Name",
              Icons.school,
              fieldColor,
              subTextColor,
              primaryColor,
            ),
            validator: (value) =>
                value!.isEmpty ? "Please enter school name" : null,
          ),
          const SizedBox(height: 15),

          // 2. EMAIL
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            style: TextStyle(color: textColor),
            decoration: _inputDecoration(
              "Admin Email (Login ID)",
              Icons.email,
              fieldColor,
              subTextColor,
              primaryColor,
            ),
            validator: (value) => value!.isEmpty ? "Please enter email" : null,
          ),
          const SizedBox(height: 15),

          // 3. PHONE NUMBER
          TextFormField(
            controller: _phoneController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            maxLength: 11,
            style: TextStyle(color: textColor),
            decoration: _inputDecoration(
              "Admin Phone Number",
              Icons.phone,
              fieldColor,
              subTextColor,
              primaryColor,
            ).copyWith(counterText: ""),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return "Please enter phone number";
              }
              if (value.length < 11) {
                return "Phone number must be exactly 11 digits";
              }
              return null;
            },
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8.0, left: 10.0),
            child: Text(
              "* This will be used for administrative contact.",
              style: TextStyle(
                fontSize: 12,
                color: subTextColor,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
          const SizedBox(height: 20),

          // 4. PASSWORD
          TextFormField(
            controller: _passwordController,
            obscureText: _isObscure1,
            style: TextStyle(color: textColor),
            onChanged: (val) => _checkPasswordStrength(val, primaryColor),
            decoration:
                _inputDecoration(
                  "Create Password",
                  Icons.lock_outline,
                  fieldColor,
                  subTextColor,
                  primaryColor,
                ).copyWith(
                  suffixIcon: IconButton(
                    icon: Icon(
                      _isObscure1 ? Icons.visibility : Icons.visibility_off,
                      color: subTextColor,
                    ),
                    onPressed: () => setState(() => _isObscure1 = !_isObscure1),
                  ),
                ),
            validator: (value) =>
                value!.isEmpty ? "Please create a password" : null,
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

          // 5. CONFIRM PASSWORD
          TextFormField(
            controller: _confirmPasswordController,
            obscureText: _isObscure2,
            style: TextStyle(color: textColor),
            onChanged: _checkMatch,
            decoration:
                _inputDecoration(
                  "Confirm Password",
                  Icons.lock_reset,
                  fieldColor,
                  subTextColor,
                  primaryColor,
                ).copyWith(
                  suffixIcon: IconButton(
                    icon: Icon(
                      _isObscure2 ? Icons.visibility : Icons.visibility_off,
                      color: subTextColor,
                    ),
                    onPressed: () => setState(() => _isObscure2 = !_isObscure2),
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
          const SizedBox(height: 30),

          // AGREEMENT CHECKBOX 1: Privacy Policy
          Row(
            children: [
              Checkbox(
                value: _isAgreed,
                activeColor: primaryColor,
                checkColor: Colors.white,
                side: BorderSide(color: subTextColor),
                onChanged: (val) => setState(() => _isAgreed = val!),
              ),
              Expanded(
                child: Wrap(
                  children: [
                    Text("I agree to the ", style: TextStyle(color: textColor)),
                    GestureDetector(
                      onTap: () => _showPrivacyPolicy(primaryColor),
                      child: Text(
                        "Terms & Privacy Policy",
                        style: TextStyle(
                          color: primaryColor,
                          fontWeight: FontWeight.bold,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // AGREEMENT CHECKBOX 2: Free Tier Acknowledgment
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: _isFreeTierAgreed,
                activeColor: primaryColor,
                checkColor: Colors.white,
                side: BorderSide(color: subTextColor),
                onChanged: (val) => setState(() => _isFreeTierAgreed = val!),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 10.0),
                  child: Text(
                    "I acknowledge that TriDeta is currently free for a limited time, and continued usage in the future may require a paid subscription.",
                    style: TextStyle(fontSize: 13, color: textColor),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 30),

          // SUBMIT BUTTON
          SizedBox(
            height: 55,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              onPressed: _isLoading
                  ? null
                  : () => _showConfirmationDialog(primaryColor),
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
                      "REGISTER SCHOOL",
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
  InputDecoration _inputDecoration(
    String label,
    IconData icon,
    Color fieldColor,
    Color hintColor,
    Color primaryColor,
  ) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: hintColor),
      prefixIcon: Icon(icon, color: primaryColor),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide(color: primaryColor, width: 2),
      ),
      filled: true,
      fillColor: fieldColor,
    );
  }

  Widget _buildDetailRow(String label, String value, Color textColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: TextStyle(fontWeight: FontWeight.bold, color: textColor),
            ),
          ),
          Expanded(
            child: Text(value, style: TextStyle(color: textColor)),
          ),
        ],
      ),
    );
  }

  // --- LOGIC ---
  void _showConfirmationDialog(Color primaryColor) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color popupBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    Color textColor = isDark ? Colors.white : Colors.black87;

    if (!_formKey.currentState!.validate()) {
      showAuthErrorDialog("Please fill in all the required fields correctly.");
      return;
    }

    String pwd = _passwordController.text;
    if (pwd.length < 6 ||
        !RegExp(r'[a-zA-Z]').hasMatch(pwd) ||
        !RegExp(r'[0-9]').hasMatch(pwd)) {
      showAuthErrorDialog(
        "Your password is too weak. It must be at least 6 characters long and contain both letters and numbers.",
      );
      return;
    }
    if (pwd != _confirmPasswordController.text) {
      showAuthErrorDialog(
        "The passwords you entered do not match. Please check them and try again.",
      );
      return;
    }

    if (!_isAgreed || !_isFreeTierAgreed) {
      showAuthErrorDialog(
        "You must check both agreement boxes to acknowledge the Terms of Service and Free Access policy before continuing.",
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: popupBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text(
          "Confirm Details",
          style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Please verify your details before submitting:",
              style: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
            ),
            const SizedBox(height: 20),
            _buildDetailRow("School:", _schoolNameController.text, textColor),
            _buildDetailRow("Email:", _emailController.text, textColor),
            _buildDetailRow("Phone:", _phoneController.text, textColor),
            _buildDetailRow("Password:", "********", textColor),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              "Edit",
              style: TextStyle(color: isDark ? Colors.white54 : Colors.grey),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () {
              Navigator.pop(context);
              _submitRegistration(primaryColor);
            },
            child: const Text(
              "Submit",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submitRegistration(Color primaryColor) async {
    setState(() => _isLoading = true);

    String? error = await _authService.registerSchool(
      schoolName: _schoolNameController.text.trim(),
      email: _emailController.text.trim(),
      password: _passwordController.text.trim(),
      phone: _phoneController.text.trim(),
    );

    setState(() => _isLoading = false);

    if (error == null) {
      if (mounted) _showSuccessDialog(primaryColor);
    } else {
      String laymanError = error;
      if (error.toLowerCase().contains("already registered") ||
          error.toLowerCase().contains("already exists")) {
        laymanError =
            "An account with this email already exists. Please try logging in.";
      } else if (error.toLowerCase().contains("database error")) {
        laymanError =
            "We hit a snag setting up your school profile. Please check your internet and try again.";
      } else if (error.toLowerCase().contains("timeout") ||
          error.toLowerCase().contains("socket")) {
        laymanError =
            "Poor internet connection. Please check your network and try again.";
      }

      if (mounted) showAuthErrorDialog(laymanError);
    }
  }

  void _showSuccessDialog(Color primaryColor) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color popupBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    Color textColor = isDark ? Colors.white : Colors.black87;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: popupBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Column(
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 50),
            const SizedBox(height: 10),
            Text(
              "Success!",
              style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          "Your school account has been created.\n\nPlease log in to complete the Setup Wizard.",
          textAlign: TextAlign.center,
          style: TextStyle(color: isDark ? Colors.white70 : Colors.black87),
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              },
              child: const Text(
                "GO TO LOGIN",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showPrivacyPolicy(Color primaryColor) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    Color textColor = isDark ? Colors.white : Colors.black87;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, controller) => Container(
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SingleChildScrollView(
            controller: controller,
            padding: const EdgeInsets.all(25),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 50,
                    height: 5,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey[700] : Colors.grey[300],
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  "Terms & Privacy Policy",
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: primaryColor,
                  ),
                ),
                const SizedBox(height: 15),
                Text(
                  "1. Data Privacy",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: textColor,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  "TriDeta Systems respects your data privacy. We store student and school records securely using industry-standard encryption.",
                  style: TextStyle(color: textColor),
                ),
                const SizedBox(height: 15),
                Text(
                  "2. Usage Rights",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: textColor,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  "This software is licensed for educational management purposes only.",
                  style: TextStyle(color: textColor),
                ),
                const SizedBox(height: 15),
                Text(
                  "3. Subscription Model",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: textColor,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  "TriDeta is provided completely free of charge for a promotional period. We reserve the right to introduce subscription tiers in the future. Administrators will receive a 30-day notice prior to any billing changes.",
                  style: TextStyle(color: textColor),
                ),
                const SizedBox(height: 15),
                Text(
                  "4. Security",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: textColor,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  "TriDeta is not responsible for any data loss or security breaches that may occur based on user negligence or misuse of the system.",
                  style: TextStyle(color: textColor),
                ),
                const SizedBox(height: 30),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      "I UNDERSTAND",
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
      ),
    );
  }
}
