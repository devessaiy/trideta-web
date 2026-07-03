import 'package:flutter/material.dart';
import 'package:trideta_v2/screens/auth/school_registration_screen.dart';

class EmailEntryStep extends StatelessWidget {
  final TextEditingController emailController;
  final bool isLoading;
  final bool canCheckBiometrics;
  final VoidCallback onProceed;
  final VoidCallback onGoogleLogin;
  final VoidCallback onBiometricLogin;

  const EmailEntryStep({
    super.key,
    required this.emailController,
    required this.isLoading,
    required this.canCheckBiometrics,
    required this.onProceed,
    required this.onGoogleLogin,
    required this.onBiometricLogin,
  });

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color primaryColor = Theme.of(context).primaryColor;
    Color textColor = isDark ? Colors.white : Colors.black87;
    Color hintColor = isDark ? Colors.grey.shade500 : Colors.grey.shade600;
    Color fieldColor = isDark ? const Color(0xFF1E1E1E) : Colors.grey.shade100;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: emailController,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => onProceed(),
          style: TextStyle(color: textColor),
          decoration: InputDecoration(
            prefixIcon: Icon(Icons.person_outline, color: hintColor),
            labelText: "Email or Phone Number",
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
        const SizedBox(height: 16),
        SizedBox(
          height: 55,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
            ),
            onPressed: onProceed,
            child: const Text(
              "CONTINUE",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: Divider(
                color: isDark ? Colors.white24 : Colors.grey.shade300,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                "OR",
                style: TextStyle(color: hintColor, fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(
              child: Divider(
                color: isDark ? Colors.white24 : Colors.grey.shade300,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        SizedBox(
          height: 55,
          child: OutlinedButton.icon(
            onPressed: isLoading ? null : onGoogleLogin,
            style: OutlinedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              side: BorderSide(
                color: isDark ? Colors.white24 : Colors.grey.shade300,
              ),
            ),
            icon: const Icon(
              Icons.g_mobiledata_rounded,
              size: 32,
              color: Colors.blue,
            ),
            label: Text(
              "Sign in with Google",
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        ),

        if (canCheckBiometrics) ...[
          const SizedBox(height: 30),
          GestureDetector(
            onTap: onBiometricLogin,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.fingerprint, size: 40, color: primaryColor),
                ),
                const SizedBox(height: 10),
                Text(
                  "Login with Biometrics",
                  style: TextStyle(
                    color: primaryColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 20),
        TextButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const SchoolRegistrationScreen(),
              ),
            );
          },
          child: Text(
            "Don't have an account? Register your School",
            style: TextStyle(color: primaryColor, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
