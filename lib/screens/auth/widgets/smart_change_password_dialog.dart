import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trideta_v2/widgets/trideta_loader.dart';

class SmartChangePasswordDialog extends StatefulWidget {
  const SmartChangePasswordDialog({super.key});

  @override
  State<SmartChangePasswordDialog> createState() =>
      _SmartChangePasswordDialogState();
}

class _SmartChangePasswordDialogState extends State<SmartChangePasswordDialog> {
  final _newPasswordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();

  bool _isSaving = false;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  // Live Tracking States
  double _strength = 0.0;
  String _strengthLabel = "Weak";
  Color _strengthColor = Colors.redAccent;
  bool _passwordsMatch = false;

  @override
  void initState() {
    super.initState();
    _newPasswordCtrl.addListener(_evaluatePassword);
    _confirmPasswordCtrl.addListener(_evaluatePassword);
  }

  @override
  void dispose() {
    _newPasswordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  void _evaluatePassword() {
    String pass = _newPasswordCtrl.text;
    String confirm = _confirmPasswordCtrl.text;

    // 1. Calculate Strength
    double score = 0;
    if (pass.length >= 8) score += 0.25; // Length
    if (RegExp(r'[A-Z]').hasMatch(pass)) score += 0.25; // Uppercase
    if (RegExp(r'[0-9]').hasMatch(pass)) score += 0.25; // Number
    if (RegExp(r'[!@#\$&*~`%\^()_\-+=|{}\[\]:;\"<>,.?\/]').hasMatch(pass)) {
      score += 0.25; // Special Char
    }

    String label = "Weak";
    Color color = Colors.redAccent;

    if (pass.isEmpty) {
      score = 0;
      label = "Enter a password";
      color = Colors.grey;
    } else if (score <= 0.25) {
      label = "Weak";
      color = Colors.redAccent;
    } else if (score <= 0.5) {
      label = "Fair";
      color = Colors.orange;
    } else if (score <= 0.75) {
      label = "Good";
      color = Colors.blue;
    } else {
      label = "Strong";
      color = Colors.green;
    }

    setState(() {
      _strength = score;
      _strengthLabel = label;
      _strengthColor = color;
      _passwordsMatch = pass.isNotEmpty && pass == confirm;
    });
  }

  Future<void> _updatePassword() async {
    if (_strength < 0.75 || !_passwordsMatch) {
      return; // Prevent weak/mismatched submissions
    }

    setState(() => _isSaving = true);
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: _newPasswordCtrl.text),
      );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Password updated successfully!"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error: ${e.toString()}"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color primaryColor = Theme.of(context).primaryColor;
    Color bgColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    Color textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);

    return Dialog(
      backgroundColor: bgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.lock_reset_rounded,
                    color: Colors.orange,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  "Change Password",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // NEW PASSWORD
            TextField(
              controller: _newPasswordCtrl,
              obscureText: _obscureNew,
              style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                labelText: "New Password",
                labelStyle: TextStyle(color: Colors.grey.shade500),
                filled: true,
                fillColor: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.grey.shade50,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                prefixIcon: const Icon(
                  Icons.lock_outline_rounded,
                  color: Colors.grey,
                ),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureNew ? Icons.visibility_off : Icons.visibility,
                    color: Colors.grey,
                  ),
                  onPressed: () => setState(() => _obscureNew = !_obscureNew),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // STRENGTH INDICATOR
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: _strength,
                      backgroundColor: isDark
                          ? Colors.white10
                          : Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation<Color>(_strengthColor),
                      minHeight: 6,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  _strengthLabel,
                  style: TextStyle(
                    color: _strengthColor,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // CONFIRM PASSWORD
            TextField(
              controller: _confirmPasswordCtrl,
              obscureText: _obscureConfirm,
              style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                labelText: "Confirm Password",
                labelStyle: TextStyle(color: Colors.grey.shade500),
                filled: true,
                fillColor: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.grey.shade50,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                prefixIcon: const Icon(
                  Icons.check_circle_outline_rounded,
                  color: Colors.grey,
                ),
                suffixIcon: _confirmPasswordCtrl.text.isNotEmpty
                    ? Icon(
                        _passwordsMatch
                            ? Icons.check_circle_rounded
                            : Icons.cancel_rounded,
                        color: _passwordsMatch
                            ? Colors.green
                            : Colors.redAccent,
                      )
                    : IconButton(
                        icon: Icon(
                          _obscureConfirm
                              ? Icons.visibility_off
                              : Icons.visibility,
                          color: Colors.grey,
                        ),
                        onPressed: () =>
                            setState(() => _obscureConfirm = !_obscureConfirm),
                      ),
              ),
            ),

            const SizedBox(height: 30),

            // ACTION BUTTONS
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: _isSaving ? null : () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text(
                      "Cancel",
                      style: TextStyle(
                        color: Colors.grey,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: primaryColor,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed:
                        (_isSaving || _strength < 0.75 || !_passwordsMatch)
                        ? null
                        : _updatePassword,
                    child: _isSaving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: TridetaLoader(color: Colors.white),
                          )
                        : const Text(
                            "Secure Update",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
