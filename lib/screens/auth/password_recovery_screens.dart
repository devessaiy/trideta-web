import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trideta_v2/utils/auth_error_handler.dart';

// ============================================================================
// 1. REQUEST OTP SCREEN
// ============================================================================
class ForgotPasswordScreen extends StatefulWidget {
  final String initialEmail;
  static DateTime? globalLastOtpRequestTime;
  static String? globalLastOtpRequestEmail;

  const ForgotPasswordScreen({super.key, required this.initialEmail});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen>
    with AuthErrorHandler {
  late TextEditingController _emailController;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  void _showRateLimitCountdownDialog(int initialSeconds) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color primaryColor = Theme.of(context).primaryColor;
    Timer? dialogTimer;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        int secondsLeft = initialSeconds;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            dialogTimer ??= Timer.periodic(const Duration(seconds: 1), (t) {
              if (secondsLeft > 0) {
                setDialogState(() => secondsLeft--);
              } else {
                t.cancel();
                if (Navigator.canPop(ctx)) Navigator.pop(ctx);
              }
            });

            return AlertDialog(
              backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              title: Column(
                children: [
                  const Icon(Icons.timer, color: Colors.orange, size: 50),
                  const SizedBox(height: 10),
                  Text(
                    "Please Wait",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                ],
              ),
              content: Text(
                "You recently requested a code.\nPlease wait before requesting another one:\n\n00:${secondsLeft.toString().padLeft(2, '0')}",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark ? Colors.white70 : Colors.black87,
                  fontSize: 14,
                ),
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
                      dialogTimer?.cancel();
                      Navigator.pop(ctx);
                    },
                    child: const Text(
                      "GOT IT",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    ).then((_) => dialogTimer?.cancel());
  }

  Future<void> _requestOTP() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      showAuthErrorDialog("Please enter your Login ID first.");
      return;
    }

    // 🚨 REQUIREMENT 3: ADMIN INTERCEPT FOR PHONE LOGINS
    final isPhoneLogin = !email.contains('@');

    if (isPhoneLogin) {
      bool isDark = Theme.of(context).brightness == Brightness.dark;

      // It's a phone number! Stop them and show the Admin message.
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Column(
            children: [
              Icon(Icons.admin_panel_settings, size: 50, color: Colors.orange),
              SizedBox(height: 10),
              Text(
                "Admin Assistance Required",
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: const Text(
            "For security reasons, phone number logins cannot be reset via SMS.\n\nPlease contact your School Administrator to securely reset your password.",
            textAlign: TextAlign.center,
            style: TextStyle(height: 1.5),
          ),
          actions: [
            Center(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
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
            ),
          ],
        ),
      );
      return; // 🚨 Stop the function here so it doesn't contact Supabase!
    }

    if (ForgotPasswordScreen.globalLastOtpRequestTime != null &&
        ForgotPasswordScreen.globalLastOtpRequestEmail == email) {
      final secondsPassed = DateTime.now()
          .difference(ForgotPasswordScreen.globalLastOtpRequestTime!)
          .inSeconds;
      if (secondsPassed < 60) {
        showSuccessDialog(
          "Code Already Sent",
          "We recently sent a code. Please check your inbox and spam folder.",
          onOkay: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => OtpVerificationScreen(email: email),
              ),
            );
          },
        );
        return;
      }
    }

    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color primaryColor = Theme.of(context).primaryColor;

    bool? proceed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              "Select Account to Reset",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: primaryColor.withOpacity(0.1),
                child: Icon(Icons.admin_panel_settings, color: primaryColor),
              ),
              title: const Text(
                "School Administrative Account",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              onTap: () => Navigator.pop(ctx, true),
            ),
            const Divider(),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.green.withOpacity(0.1),
                child: const Icon(Icons.family_restroom, color: Colors.green),
              ),
              title: const Text(
                "Parent Dashboard Account",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              onTap: () => Navigator.pop(ctx, true),
            ),
            const SizedBox(height: 15),
            const Text(
              "*Note: If you use this email for both the Admin and Parent portals, your new password will securely update your login access for BOTH dashboards.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );

    if (proceed != true) return;

    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(email);
      ForgotPasswordScreen.globalLastOtpRequestTime = DateTime.now();
      ForgotPasswordScreen.globalLastOtpRequestEmail = email;

      if (mounted) {
        setState(() => _isLoading = false);
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => OtpVerificationScreen(email: email),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        if (e.toString().toLowerCase().contains("rate limit")) {
          _showRateLimitCountdownDialog(60);
        } else {
          showAuthErrorDialog(e.toString());
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = isDark ? const Color(0xFF121212) : Colors.white;
    Color textColor = isDark ? Colors.white : Colors.black;
    Color subTextColor = isDark ? Colors.grey.shade400 : Colors.grey.shade600;
    Color fieldColor = isDark ? const Color(0xFF1E1E1E) : Colors.grey.shade100;
    Color primaryColor = Theme.of(context).primaryColor;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        iconTheme: IconThemeData(color: textColor),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 20),
                  Text(
                    "Reset Password",
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    "Enter your Email or Phone Number to recover your account.",
                    style: TextStyle(fontSize: 16, color: subTextColor),
                  ),
                  const SizedBox(height: 40),
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    style: TextStyle(color: textColor),
                    decoration: InputDecoration(
                      labelText: "Email or Phone Number",
                      prefixIcon: Icon(
                        Icons.person_outline,
                        color: subTextColor,
                      ),
                      labelStyle: TextStyle(color: subTextColor),
                      filled: true,
                      fillColor: fieldColor,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: BorderSide.none,
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
                      onPressed: _isLoading ? null : _requestOTP,
                      child: _isLoading
                          ? const SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              "SEND RECOVERY CODE",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
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
}

// ============================================================================
// 2. VERIFY OTP SCREEN
// ============================================================================
class OtpVerificationScreen extends StatefulWidget {
  final String email;
  const OtpVerificationScreen({super.key, required this.email});

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen>
    with AuthErrorHandler {
  String _otpCode = "";
  bool _isLoading = false;
  Timer? _timer;
  int _start = 60;

  @override
  void initState() {
    super.initState();
    if (ForgotPasswordScreen.globalLastOtpRequestTime != null) {
      final secondsPassed = DateTime.now()
          .difference(ForgotPasswordScreen.globalLastOtpRequestTime!)
          .inSeconds;
      _start = 60 - secondsPassed;
      if (_start < 0) _start = 0;
    }
    if (_start > 0) _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      if (_start == 0) {
        setState(() => timer.cancel());
      } else {
        setState(() => _start--);
      }
    });
  }

  Future<void> _resendCode() async {
    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(widget.email);
      ForgotPasswordScreen.globalLastOtpRequestTime = DateTime.now();
      ForgotPasswordScreen.globalLastOtpRequestEmail = widget.email;

      if (mounted) {
        showSuccessDialog(
          "Code Resent",
          "A new 6-digit code has been sent to ${widget.email}.",
        );
        setState(() => _start = 60);
        _startTimer();
      }
    } catch (e) {
      if (mounted) showAuthErrorDialog(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _verifyCode() async {
    if (_otpCode.length != 6) {
      showAuthErrorDialog("Please enter all 6 digits of the code we sent you.");
      return;
    }

    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client.auth.verifyOTP(
        type: OtpType.recovery,
        token: _otpCode,
        email: widget.email,
      );
      if (mounted) {
        setState(() => _isLoading = false);
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const SetNewPasswordScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        showAuthErrorDialog(e.toString());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = isDark ? const Color(0xFF121212) : Colors.white;
    Color textColor = isDark ? Colors.white : Colors.black;
    Color subTextColor = isDark ? Colors.grey.shade400 : Colors.grey.shade600;
    Color boxColor = isDark ? const Color(0xFF1E1E1E) : Colors.grey.shade100;
    Color primaryColor = Theme.of(context).primaryColor;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        iconTheme: IconThemeData(color: textColor),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 20),
                  Text(
                    "Enter Code",
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    "We sent a 6-digit code to ${widget.email}.",
                    style: TextStyle(fontSize: 16, color: subTextColor),
                  ),
                  const SizedBox(height: 40),
                  Stack(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: List.generate(6, (index) {
                          bool isFilled = _otpCode.length > index;
                          return Flexible(
                            child: Container(
                              height: 60,
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: boxColor,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isFilled
                                      ? primaryColor
                                      : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                              child: Text(
                                isFilled ? _otpCode[index] : "",
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: textColor,
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                      Positioned.fill(
                        child: TextField(
                          maxLength: 6,
                          keyboardType: TextInputType.number,
                          cursorColor: Colors.transparent,
                          style: const TextStyle(color: Colors.transparent),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            counterText: "",
                          ),
                          onChanged: (val) => setState(() => _otpCode = val),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 30),
                  if (_start > 0)
                    Text(
                      "Resend code in 00:${_start.toString().padLeft(2, '0')}",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: subTextColor,
                        fontWeight: FontWeight.w500,
                      ),
                    )
                  else
                    TextButton(
                      onPressed: _isLoading ? null : _resendCode,
                      child: Text(
                        "Resend Code",
                        style: TextStyle(
                          color: primaryColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 55,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      onPressed: _isLoading ? null : _verifyCode,
                      child: _isLoading
                          ? const SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              "VERIFY CODE",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
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
}

// ============================================================================
// 3. CREATE NEW PASSWORD SCREEN
// ============================================================================
class SetNewPasswordScreen extends StatefulWidget {
  const SetNewPasswordScreen({super.key});

  @override
  State<SetNewPasswordScreen> createState() => _SetNewPasswordScreenState();
}

class _SetNewPasswordScreenState extends State<SetNewPasswordScreen>
    with AuthErrorHandler {
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isObscure1 = true;
  bool _isObscure2 = true;
  bool _isLoading = false;

  String _passwordStrength = "";
  Color _strengthColor = Colors.transparent;

  String _matchStatus = "";
  Color _matchColor = Colors.transparent;

  @override
  void dispose() {
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

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
    if (val == _newPasswordController.text) {
      _matchStatus = "Passwords match";
      _matchColor = Colors.green;
    } else {
      _matchStatus = "Passwords do not match";
      _matchColor = Colors.red;
    }
    setState(() {});
  }

  Future<void> _updatePassword() async {
    String newPassword = _newPasswordController.text.trim();
    String confirmPassword = _confirmPasswordController.text.trim();

    if (newPassword.length < 6 ||
        !RegExp(r'[a-zA-Z]').hasMatch(newPassword) ||
        !RegExp(r'[0-9]').hasMatch(newPassword)) {
      showAuthErrorDialog("Please enter a valid, strong password.");
      return;
    }
    if (newPassword != confirmPassword) {
      showAuthErrorDialog("The passwords do not match.");
      return;
    }

    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: newPassword),
      );
      await Supabase.instance.client.auth.signOut();
      if (mounted) {
        setState(() => _isLoading = false);
        showSuccessDialog(
          "Password Updated!",
          "Your password has been changed successfully. You can now log in securely.",
          onOkay: () =>
              Navigator.of(context).popUntil((route) => route.isFirst),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        showAuthErrorDialog(e.toString());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = isDark ? const Color(0xFF121212) : Colors.white;
    Color textColor = isDark ? Colors.white : Colors.black;
    Color subTextColor = isDark ? Colors.grey.shade400 : Colors.grey.shade600;
    Color fieldColor = isDark ? const Color(0xFF1E1E1E) : Colors.grey.shade100;
    Color primaryColor = Theme.of(context).primaryColor;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 20),
                  Text(
                    "Secure Account",
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    "Create a new strong password for your Trideta account.",
                    style: TextStyle(fontSize: 16, color: subTextColor),
                  ),
                  const SizedBox(height: 40),
                  TextField(
                    controller: _newPasswordController,
                    obscureText: _isObscure1,
                    style: TextStyle(color: textColor),
                    onChanged: (v) => _checkPasswordStrength(v, primaryColor),
                    decoration: InputDecoration(
                      labelText: "New Password",
                      prefixIcon: Icon(Icons.lock_reset, color: subTextColor),
                      labelStyle: TextStyle(color: subTextColor),
                      helperText:
                          "Must be at least 6 characters with letters & numbers.",
                      helperStyle: TextStyle(color: subTextColor, fontSize: 12),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _isObscure1 ? Icons.visibility : Icons.visibility_off,
                          color: subTextColor,
                        ),
                        onPressed: () =>
                            setState(() => _isObscure1 = !_isObscure1),
                      ),
                      filled: true,
                      fillColor: fieldColor,
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
                  const SizedBox(height: 20),
                  TextField(
                    controller: _confirmPasswordController,
                    obscureText: _isObscure2,
                    style: TextStyle(color: textColor),
                    onChanged: _checkMatch,
                    decoration: InputDecoration(
                      labelText: "Confirm Password",
                      prefixIcon: Icon(Icons.lock_outline, color: subTextColor),
                      labelStyle: TextStyle(color: subTextColor),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _isObscure2 ? Icons.visibility : Icons.visibility_off,
                          color: subTextColor,
                        ),
                        onPressed: () =>
                            setState(() => _isObscure2 = !_isObscure2),
                      ),
                      filled: true,
                      fillColor: fieldColor,
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
                  const SizedBox(height: 40),
                  SizedBox(
                    height: 55,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      onPressed: _isLoading ? null : _updatePassword,
                      child: _isLoading
                          ? const SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              "UPDATE PASSWORD",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
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
}
