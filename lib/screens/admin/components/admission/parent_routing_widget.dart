import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ParentRoutingWidget extends StatelessWidget {
  final bool usePhoneAsLogin;
  final Function(bool) onLoginMethodChanged;
  final bool isExistingParentFound;

  final TextEditingController parentNameController;
  final TextEditingController parentEmailController;
  final TextEditingController loginPhoneController;
  final TextEditingController parentPhoneController;
  final TextEditingController addressController;
  final TextEditingController parentPasswordController;
  final TextEditingController parentConfirmPasswordController;

  final bool isObscure1;
  final bool isObscure2;
  final Function(bool) onObscure1Changed;
  final Function(bool) onObscure2Changed;

  final bool pwdHasMinLength;
  final bool pwdHasNumber;
  final bool pwdMatch;
  final Function(String) onParentLoginChanged;

  final Color primaryColor;
  final bool isDark;
  final Color cardColor;
  final Color textColor;

  const ParentRoutingWidget({
    super.key,
    required this.usePhoneAsLogin,
    required this.onLoginMethodChanged,
    required this.isExistingParentFound,
    required this.parentNameController,
    required this.parentEmailController,
    required this.loginPhoneController,
    required this.parentPhoneController,
    required this.addressController,
    required this.parentPasswordController,
    required this.parentConfirmPasswordController,
    required this.isObscure1,
    required this.isObscure2,
    required this.onObscure1Changed,
    required this.onObscure2Changed,
    required this.pwdHasMinLength,
    required this.pwdHasNumber,
    required this.pwdMatch,
    required this.onParentLoginChanged,
    required this.primaryColor,
    required this.isDark,
    required this.cardColor,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(
          "Parent / Guardian Routing",
          Icons.family_restroom_rounded,
          Colors.green,
        ),
        const SizedBox(height: 20),

        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.grey.shade200,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => onLoginMethodChanged(false),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: !usePhoneAsLogin ? cardColor : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: !usePhoneAsLogin
                          ? [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : [],
                    ),
                    child: Center(
                      child: Text(
                        "Email Login",
                        style: TextStyle(
                          color: !usePhoneAsLogin
                              ? textColor
                              : Colors.grey.shade500,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () => onLoginMethodChanged(true),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: usePhoneAsLogin ? cardColor : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: usePhoneAsLogin
                          ? [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : [],
                    ),
                    child: Center(
                      child: Text(
                        "Phone Login",
                        style: TextStyle(
                          color: usePhoneAsLogin
                              ? textColor
                              : Colors.grey.shade500,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
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

        AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SizeTransition(sizeFactor: animation, child: child),
          ),
          child: usePhoneAsLogin
              ? _buildPhoneLoginFields()
              : _buildEmailLoginFields(),
        ),
        const SizedBox(height: 20),

        if (isExistingParentFound)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.verified_user_rounded,
                  color: Colors.green,
                  size: 24,
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    "Linked Parent Profile Found! Name auto-filled and password setup bypassed.",
                    style: TextStyle(
                      color: Colors.green,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),

        _buildTextField(
          parentNameController,
          "Parent Full Name",
          Icons.account_circle_rounded,
          readOnly: isExistingParentFound,
        ),
        const SizedBox(height: 16),
        _buildTextField(
          addressController,
          "Home Address",
          Icons.location_on_rounded,
          maxLines: 2,
        ),

        if (!isExistingParentFound) ...[
          const SizedBox(height: 35),
          _buildSectionTitle(
            "Security & Authorization",
            Icons.security_rounded,
            Colors.redAccent,
          ),
          const SizedBox(height: 20),
          _buildPasswordField(
            parentPasswordController,
            "Create Parent Password",
            isObscure1,
            onObscure1Changed,
          ),

          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _trackerChip("6+ Chars", pwdHasMinLength),
                _trackerChip("Number", pwdHasNumber),
                _trackerChip("Match", pwdMatch),
              ],
            ),
          ),

          _buildPasswordField(
            parentConfirmPasswordController,
            "Confirm Password",
            isObscure2,
            onObscure2Changed,
          ),
        ],
      ],
    );
  }

  Widget _buildSectionTitle(String title, IconData icon, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 12),
            Text(
              title.toUpperCase(),
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: color,
                letterSpacing: 1.5,
                fontSize: 11,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Divider(height: 1, color: Colors.grey.withValues(alpha: 0.2)),
      ],
    );
  }

  Widget _trackerChip(String label, bool isValid) {
    return Row(
      children: [
        Icon(
          isValid
              ? Icons.check_circle_rounded
              : Icons.radio_button_unchecked_rounded,
          size: 16,
          color: isValid ? Colors.green : Colors.grey.shade400,
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isValid ? Colors.green : Colors.grey.shade500,
            fontWeight: isValid ? FontWeight.bold : FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildEmailLoginFields() {
    return Column(
      key: const ValueKey('email_login'),
      children: [
        _buildTextField(
          parentEmailController,
          "Parent Login Email",
          Icons.email_rounded,
          onChanged: onParentLoginChanged,
        ),
        const SizedBox(height: 16),
        _buildTextField(
          parentPhoneController,
          "Contact Phone Number (Optional)",
          Icons.phone_rounded,
          isRequired: false,
        ),
      ],
    );
  }

  Widget _buildPhoneLoginFields() {
    return Column(
      key: const ValueKey('phone_login'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: loginPhoneController,
          keyboardType: TextInputType.phone,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: onParentLoginChanged,
          validator: (v) =>
              v!.trim().isEmpty ? "Phone required for login" : null,
          decoration: InputDecoration(
            labelText: "Login Phone Number",
            labelStyle: TextStyle(color: Colors.grey.shade500, fontSize: 13),
            hintText: "08012345678",
            hintStyle: TextStyle(color: Colors.grey.shade400),
            prefixIcon: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
              child: Text(
                "🇳🇬 +234",
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ),
            filled: true,
            fillColor: isDark
                ? Colors.white.withValues(alpha: 0.03)
                : Colors.grey.shade50,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color: isDark ? Colors.white10 : Colors.grey.shade200,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color: primaryColor.withValues(alpha: 0.5),
                width: 2,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.info_outline_rounded,
                color: Colors.orange,
                size: 14,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Parents will log in using this number exactly as entered.",
                  style: TextStyle(
                    color: Colors.orange.shade700,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTextField(
    TextEditingController ctrl,
    String label,
    IconData? icon, {
    bool isRequired = true,
    int maxLines = 1,
    bool readOnly = false,
    Function(String)? onChanged,
  }) {
    return TextFormField(
      controller: ctrl,
      maxLines: maxLines,
      readOnly: readOnly,
      onChanged: onChanged,
      validator: isRequired
          ? (v) => v!.trim().isEmpty ? "Required field" : null
          : null,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey.shade500, fontSize: 13),
        prefixIcon: icon != null
            ? Icon(icon, color: readOnly ? Colors.grey : primaryColor, size: 20)
            : null,
        filled: true,
        fillColor: readOnly
            ? (isDark
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.grey.shade200)
            : (isDark
                  ? Colors.white.withValues(alpha: 0.03)
                  : Colors.grey.shade50),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: isDark ? Colors.white10 : Colors.grey.shade200,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: primaryColor.withValues(alpha: 0.5),
            width: 2,
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
  ) {
    return TextFormField(
      controller: ctrl,
      obscureText: isObscure,
      validator: (v) {
        if (v!.isEmpty) return "Password required";
        if (v.length < 6) return "Must be at least 6 chars";
        if (ctrl == parentConfirmPasswordController &&
            v != parentPasswordController.text)
          return "Passwords do not match";
        return null;
      },
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey.shade500, fontSize: 13),
        prefixIcon: Icon(Icons.lock_rounded, color: primaryColor, size: 20),
        suffixIcon: IconButton(
          icon: Icon(
            isObscure ? Icons.visibility_off_rounded : Icons.visibility_rounded,
            color: Colors.grey.shade400,
            size: 20,
          ),
          onPressed: () => onToggle(!isObscure),
        ),
        filled: true,
        fillColor: isDark
            ? Colors.white.withValues(alpha: 0.03)
            : Colors.grey.shade50,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: isDark ? Colors.white10 : Colors.grey.shade200,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: primaryColor.withValues(alpha: 0.5),
            width: 2,
          ),
        ),
      ),
    );
  }
}
