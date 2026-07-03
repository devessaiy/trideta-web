import 'package:flutter/material.dart';
import 'package:trideta_v2/widgets/trideta_loader.dart';
import 'package:trideta_v2/screens/auth/password_recovery_screens.dart';

class PasswordEntryStep extends StatefulWidget {
  final TextEditingController passwordController;
  final String emailText;
  final bool isLoading;
  final VoidCallback onLogin;
  final VoidCallback onEditEmail;

  const PasswordEntryStep({
    super.key,
    required this.passwordController,
    required this.emailText,
    required this.isLoading,
    required this.onLogin,
    required this.onEditEmail,
  });

  @override
  State<PasswordEntryStep> createState() => _PasswordEntryStepState();
}

class _PasswordEntryStepState extends State<PasswordEntryStep> {
  bool _isObscure = true; // Moved visibility state directly into the component

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
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: fieldColor,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: isDark ? Colors.white24 : Colors.grey.shade300,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  widget.emailText,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              GestureDetector(
                onTap: widget.onEditEmail,
                child: Text(
                  "Edit",
                  style: TextStyle(
                    color: primaryColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        TextField(
          controller: widget.passwordController,
          obscureText: _isObscure,
          style: TextStyle(color: textColor),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => widget.onLogin(),
          decoration: InputDecoration(
            prefixIcon: Icon(Icons.lock_outline, color: hintColor),
            suffixIcon: IconButton(
              icon: Icon(
                _isObscure ? Icons.visibility : Icons.visibility_off,
                color: hintColor,
              ),
              onPressed: () => setState(() => _isObscure = !_isObscure),
            ),
            labelText: "Password",
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

        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    ForgotPasswordScreen(initialEmail: widget.emailText),
              ),
            ),
            child: Text(
              "Forgot Password?",
              style: TextStyle(
                color: primaryColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),

        SizedBox(
          height: 55,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
            ),
            onPressed: widget.isLoading ? null : widget.onLogin,
            child: widget.isLoading
                ? const SizedBox(
                    height: 24,
                    width: 24,
                    child: TridetaLoader(color: Colors.white),
                  )
                : const Text(
                    "SECURE LOGIN",
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
    );
  }
}
