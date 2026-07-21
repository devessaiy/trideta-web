import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart'; // 🚨 NEW IMPORT FOR PRIVACY LINK

// 🚨 MODULAR IMPORTS
import 'package:trideta_v2/utils/auth_error_handler.dart';
import 'package:trideta_v2/widgets/trideta_loader.dart';
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

  void _checkPasswordStrength(String password) {
    setState(() {
      if (password.isEmpty) {
        _passwordStrength = "";
        _strengthColor = Colors.transparent;
      } else if (password.length < 6) {
        _passwordStrength = "Weak (Too Short)";
        _strengthColor = Colors.red;
      } else if (!RegExp(r'[A-Z]').hasMatch(password) ||
          !RegExp(r'[0-9]').hasMatch(password)) {
        _passwordStrength = "Medium (Add Uppercase & Number)";
        _strengthColor = Colors.orange;
      } else {
        _passwordStrength = "Strong";
        _strengthColor = Colors.green;
      }
    });
    _checkPasswordMatch(_confirmPasswordController.text);
  }

  void _checkPasswordMatch(String confirmPassword) {
    setState(() {
      if (confirmPassword.isEmpty) {
        _matchStatus = "";
        _matchColor = Colors.transparent;
      } else if (confirmPassword == _passwordController.text) {
        _matchStatus = "Passwords Match ✓";
        _matchColor = Colors.green;
      } else {
        _matchStatus = "Passwords do not match";
        _matchColor = Colors.red;
      }
    });
  }

  void _showPrivacyDialog() {
    showDialog(
      context: context,
      builder: (context) => _buildPrivacyAgreement(context),
    );
  }

  void _showFreeTierDialog() {
    showDialog(
      context: context,
      builder: (context) => _buildFreeTierAgreement(context),
    );
  }

  Future<void> _handleRegistration() async {
    if (!_formKey.currentState!.validate()) return;
    if (_passwordController.text != _confirmPasswordController.text) {
      showAuthErrorDialog("Passwords do not match. Please verify.");
      return;
    }
    if (!_isAgreed) {
      showAuthErrorDialog(
        "You must agree to the Terms & Privacy Policy to register.",
      );
      return;
    }
    if (!_isFreeTierAgreed) {
      showAuthErrorDialog(
        "You must acknowledge the Free Trial Limitations to register.",
      );
      return;
    }

    setState(() => _isLoading = true);

    String formattedPhone = _phoneController.text.trim().replaceAll(' ', '');
    if (formattedPhone.startsWith('0')) {
      formattedPhone = '+234${formattedPhone.substring(1)}';
    } else if (!formattedPhone.startsWith('+')) {
      formattedPhone = '+234$formattedPhone';
    }

    try {
      String? error = await _authService.registerSchool(
        schoolName: _schoolNameController.text.trim(),
        email: _emailController.text.trim(),
        phone: formattedPhone,
        password: _passwordController.text,
      );

      if (error == null) {
        if (mounted) {
          showSuccessDialog(
            "Registration Successful!",
            "Your school has been registered and is active on the Free Tier. Please log in to complete setup.",
          );
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            }
          });
        }
      } else {
        setState(() => _isLoading = false);
        showAuthErrorDialog(error);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      showAuthErrorDialog(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = isDark ? const Color(0xFF121212) : Colors.white;
    Color primaryColor = Theme.of(context).primaryColor;
    Color textColor = isDark ? Colors.white : Colors.black87;
    Color fieldColor = isDark ? const Color(0xFF1E1E1E) : Colors.grey.shade100;
    Color hintColor = isDark ? Colors.grey.shade500 : Colors.grey.shade600;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: textColor),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.domain_add, size: 70, color: primaryColor),
                  const SizedBox(height: 10),
                  Text(
                    "Register School",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: textColor,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    "Create your TriDeta Administrative Account",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: hintColor),
                  ),
                  const SizedBox(height: 40),

                  // School Name Field
                  _buildTextField(
                    controller: _schoolNameController,
                    label: "Full School Name",
                    icon: Icons.account_balance,
                    hintColor: hintColor,
                    fieldColor: fieldColor,
                    primaryColor: primaryColor,
                    textColor: textColor,
                    validator: (val) => val == null || val.length < 5
                        ? 'Enter a valid school name (min 5 chars)'
                        : null,
                  ),
                  const SizedBox(height: 20),

                  // Official Email Field
                  _buildTextField(
                    controller: _emailController,
                    label: "Official School Email",
                    icon: Icons.email,
                    inputType: TextInputType.emailAddress,
                    hintColor: hintColor,
                    fieldColor: fieldColor,
                    primaryColor: primaryColor,
                    textColor: textColor,
                    validator: (val) => val == null || !val.contains('@')
                        ? 'Enter a valid email address'
                        : null,
                  ),
                  const SizedBox(height: 20),

                  // Official Phone Field
                  _buildTextField(
                    controller: _phoneController,
                    label: "Admin Phone Number",
                    icon: Icons.phone,
                    inputType: TextInputType.phone,
                    hintColor: hintColor,
                    fieldColor: fieldColor,
                    primaryColor: primaryColor,
                    textColor: textColor,
                    validator: (val) => val == null || val.length < 10
                        ? 'Enter a valid phone number'
                        : null,
                  ),
                  const SizedBox(height: 20),

                  // Password Field
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _isObscure1,
                    onChanged: _checkPasswordStrength,
                    style: TextStyle(color: textColor),
                    decoration: InputDecoration(
                      prefixIcon: Icon(Icons.lock, color: hintColor),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _isObscure1 ? Icons.visibility : Icons.visibility_off,
                          color: hintColor,
                        ),
                        onPressed: () =>
                            setState(() => _isObscure1 = !_isObscure1),
                      ),
                      labelText: "Admin Password",
                      labelStyle: TextStyle(color: hintColor),
                      filled: true,
                      fillColor: fieldColor,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: BorderSide(color: primaryColor, width: 2),
                      ),
                    ),
                    validator: (val) => val == null || val.length < 6
                        ? 'Password must be at least 6 characters'
                        : null,
                  ),
                  if (_passwordStrength.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0, left: 12.0),
                      child: Text(
                        _passwordStrength,
                        style: TextStyle(
                          color: _strengthColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),

                  // Confirm Password Field
                  TextFormField(
                    controller: _confirmPasswordController,
                    obscureText: _isObscure2,
                    onChanged: _checkPasswordMatch,
                    style: TextStyle(color: textColor),
                    decoration: InputDecoration(
                      prefixIcon: Icon(Icons.lock_clock, color: hintColor),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _isObscure2 ? Icons.visibility : Icons.visibility_off,
                          color: hintColor,
                        ),
                        onPressed: () =>
                            setState(() => _isObscure2 = !_isObscure2),
                      ),
                      labelText: "Confirm Password",
                      labelStyle: TextStyle(color: hintColor),
                      filled: true,
                      fillColor: fieldColor,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: BorderSide(color: primaryColor, width: 2),
                      ),
                    ),
                  ),
                  if (_matchStatus.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0, left: 12.0),
                      child: Text(
                        _matchStatus,
                        style: TextStyle(
                          color: _matchColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  const SizedBox(height: 30),

                  // Agreement Checkboxes
                  Container(
                    decoration: BoxDecoration(
                      color: primaryColor.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(
                        color: primaryColor.withValues(alpha: 0.3),
                      ),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        CheckboxListTile(
                          value: _isAgreed,
                          onChanged: (val) => setState(() => _isAgreed = val!),
                          activeColor: primaryColor,
                          title: Row(
                            children: [
                              Text(
                                "I agree to the ",
                                style: TextStyle(
                                  fontSize: 13,
                                  color: textColor,
                                ),
                              ),
                              GestureDetector(
                                onTap: _showPrivacyDialog,
                                child: Text(
                                  "Privacy Policy",
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: primaryColor,
                                    fontWeight: FontWeight.bold,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                        ),
                        CheckboxListTile(
                          value: _isFreeTierAgreed,
                          onChanged: (val) =>
                              setState(() => _isFreeTierAgreed = val!),
                          activeColor: primaryColor,
                          title: Row(
                            children: [
                              Text(
                                "I accept the ",
                                style: TextStyle(
                                  fontSize: 13,
                                  color: textColor,
                                ),
                              ),
                              GestureDetector(
                                onTap: _showFreeTierDialog,
                                child: Text(
                                  "Free Tier Limits",
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: primaryColor,
                                    fontWeight: FontWeight.bold,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),

                  // Register Button
                  SizedBox(
                    height: 55,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                        elevation: 5,
                      ),
                      onPressed: _isLoading ? null : _handleRegistration,
                      child: _isLoading
                          ? const SizedBox(
                              height: 24,
                              width: 24,
                              child: TridetaLoader(color: Colors.white),
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
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required Color hintColor,
    required Color fieldColor,
    required Color primaryColor,
    required Color textColor,
    TextInputType inputType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: inputType,
      style: TextStyle(color: textColor),
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: hintColor),
        labelText: label,
        labelStyle: TextStyle(color: hintColor),
        filled: true,
        fillColor: fieldColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide(color: primaryColor, width: 2),
        ),
      ),
      validator: validator,
    );
  }

  // 🚨 REFACTORED PRIVACY DIALOG
  Widget _buildPrivacyAgreement(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    Color textColor = isDark ? Colors.white : Colors.black87;
    Color primaryColor = Theme.of(context).primaryColor;
    Color hintColor = isDark ? Colors.grey.shade400 : Colors.grey.shade600;

    return Dialog(
      backgroundColor: bgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.privacy_tip, color: primaryColor, size: 30),
                  const SizedBox(width: 10),
                  Text(
                    "Terms & Privacy Policy",
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // 🚨 NEW LINK-BASED UI
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "By registering your school on TriDeta, you agree to our comprehensive Terms of Service and Privacy Policy, which dictate how we handle your school's data, communications, and security.",
                        style: TextStyle(
                          color: hintColor,
                          fontSize: 15,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 20),
                      GestureDetector(
                        onTap: () async {
                          final Uri url = Uri.parse(
                            'https://trideta.vercel.app/privacy-policy.html',
                          );
                          if (await canLaunchUrl(url)) {
                            await launchUrl(
                              url,
                              mode: LaunchMode.externalApplication,
                            );
                          } else {
                            if (context.mounted) {
                              showAuthErrorDialog(
                                "Could not open the privacy policy link.",
                              );
                            }
                          }
                        },
                        child: Text(
                          "Learn more...",
                          style: TextStyle(
                            color: primaryColor,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
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
    );
  }

  Widget _buildFreeTierAgreement(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    Color textColor = isDark ? Colors.white : Colors.black87;
    Color primaryColor = Theme.of(context).primaryColor;
    Color hintColor = isDark ? Colors.grey.shade400 : Colors.grey.shade600;

    return Dialog(
      backgroundColor: bgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.star_outline, color: primaryColor, size: 30),
                  const SizedBox(width: 10),
                  Text(
                    "Free Tier Limits",
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Your school will be automatically placed on the Free Tier upon registration. Please note the following constraints:",
                        style: TextStyle(color: hintColor, fontSize: 15),
                      ),
                      const SizedBox(height: 20),
                      _buildLimitItem(
                        Icons.people,
                        "Maximum of 50 Students",
                        textColor,
                        primaryColor,
                      ),
                      const SizedBox(height: 15),
                      _buildLimitItem(
                        Icons.storage,
                        "500MB Data Storage",
                        textColor,
                        primaryColor,
                      ),
                      const SizedBox(height: 15),
                      _buildLimitItem(
                        Icons.message,
                        "No Mass SMS Messaging",
                        textColor,
                        primaryColor,
                      ),
                      const SizedBox(height: 15),
                      _buildLimitItem(
                        Icons.support_agent,
                        "Standard Support Response Times",
                        textColor,
                        primaryColor,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        "You can upgrade to a Premium plan at any time from your Admin Dashboard to lift these limits.",
                        style: TextStyle(
                          color: primaryColor,
                          fontWeight: FontWeight.bold,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),
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
    );
  }

  Widget _buildLimitItem(
    IconData icon,
    String text,
    Color textColor,
    Color iconColor,
  ) {
    return Row(
      children: [
        Icon(icon, color: iconColor, size: 24),
        const SizedBox(width: 15),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: textColor,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
