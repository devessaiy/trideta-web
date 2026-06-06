import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trideta_v2/widgets/trideta_loader.dart';

class ParentSecurityDialogs {
  // 🚨 REDESIGNED "PARENT SECURITY & CONTACT" HUB
  static void showCredentialPopup({
    required BuildContext context,
    required String targetLoginId,
    required String? dbParentPhone,
    required String createdPassword,
    required Color primaryColor,
    required SupabaseClient supabase,
    required Function(String) onError,
    required Function(String, String) onSuccess,
  }) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    // 🚨 SMART EXTRACTOR: Pull phone from phantom email if necessary
    bool isPhantom = targetLoginId.endsWith('@trideta.com');
    String phantomPhone = isPhantom
        ? targetLoginId.replaceAll('@trideta.com', '')
        : "";

    // 🚨 SMART CONTACT FALLBACK
    String finalContactPhone = "";
    if (dbParentPhone != null && dbParentPhone!.isNotEmpty) {
      finalContactPhone = dbParentPhone;
    } else if (isPhantom && phantomPhone.isNotEmpty) {
      finalContactPhone = phantomPhone;
    }

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 450),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.1),
                blurRadius: 30,
                offset: const Offset(0, 15),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // --- PREMIUM HEADER ---
              Container(
                padding: const EdgeInsets.fromLTRB(24, 30, 24, 24),
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.05),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(30),
                  ),
                  border: Border(
                    bottom: BorderSide(
                      color: isDark ? Colors.white10 : Colors.grey.shade200,
                    ),
                  ),
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Center(
                      child: Column(
                        children: [
                          Container(
                            width: 70,
                            height: 70,
                            decoration: BoxDecoration(
                              color: primaryColor.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.admin_panel_settings_rounded,
                              size: 35,
                              color: primaryColor,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            "Parent Access Hub",
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: isDark ? Colors.white : Colors.black87,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "Call student's guardian.",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade500,
                              height: 1.4,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      right: -10,
                      top: -20,
                      child: IconButton(
                        icon: Icon(
                          Icons.close_rounded,
                          color: Colors.grey.shade400,
                        ),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ),
                  ],
                ),
              ),

              // --- ACTION CARDS SECTION ---
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    // 1. Success Message (Only shows if password was just generated)
                    if (createdPassword !=
                        "******** (Hidden for security)") ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          vertical: 20,
                          horizontal: 20,
                        ),
                        margin: const EdgeInsets.only(bottom: 24),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.green.withValues(alpha: 0.3),
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                          children: [
                            const Icon(
                              Icons.check_circle_rounded,
                              color: Colors.green,
                              size: 28,
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              "ACCOUNT ACTIVATED",
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                color: Colors.green,
                                letterSpacing: 1.5,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              createdPassword,
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 2.0,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "Provide this password to the parent.",
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.green.shade700,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // 2. Action Card: Call Parent
                    if (finalContactPhone.isNotEmpty)
                      _buildPremiumActionCard(
                        icon: Icons.phone_in_talk_rounded,
                        iconColor: Colors.blue,
                        title: "Phone Call",
                        subtitle: "Dial $finalContactPhone.",
                        onTap: () async {
                          final Uri url = Uri(
                            scheme: 'tel',
                            path: finalContactPhone,
                          );
                          if (await canLaunchUrl(url)) {
                            await launchUrl(url);
                          } else {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    "Calling is not supported on this device.",
                                    style: TextStyle(color: Colors.white),
                                  ),
                                  backgroundColor: Colors.orange,
                                ),
                              );
                            }
                          }
                        },
                        isDark: isDark,
                      )
                    else
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.03)
                              : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isDark
                                ? Colors.white10
                                : Colors.grey.shade200,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.phone_disabled_rounded,
                              color: Colors.grey.shade400,
                              size: 28,
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "No Contact Phone Available",
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      color: Colors.grey.shade500,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    "Update the student's profile biodata to add a valid phone number.",
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                    // 3. Action Card: Reset Password
                    _buildPremiumActionCard(
                      icon: Icons.lock_reset_rounded,
                      iconColor: Colors.redAccent,
                      title: "Password Reset",
                      subtitle: "Generate a secure login key for this parent.",
                      onTap: () {
                        Navigator.pop(ctx);
                        _showAdminResetPasswordDialog(
                          context: context,
                          targetLoginId: targetLoginId,
                          primaryColor: primaryColor,
                          supabase: supabase,
                          onError: onError,
                          onSuccess: onSuccess,
                        );
                      },
                      isDark: isDark,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 🚨 REUSABLE PREMIUM ACTION CARD WIDGET
  static Widget _buildPremiumActionCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
        ),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: iconColor, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 12,
                          height: 1.4,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: Colors.grey.shade400,
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 🚨 SMART PASSWORD RESET LOGIC (ALSO UPGRADED TO PREMIUM LOOK)
  static void _showAdminResetPasswordDialog({
    required BuildContext context,
    required String targetLoginId,
    required Color primaryColor,
    required SupabaseClient supabase,
    required Function(String) onError,
    required Function(String, String) onSuccess,
  }) {
    final pwdController = TextEditingController();
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    bool isLoading = false;

    bool isPhantom = targetLoginId.endsWith('@trideta.com');
    String displayId = isPhantom
        ? targetLoginId.replaceAll('@trideta.com', '')
        : targetLoginId;
    String loginType = isPhantom ? "Phone Number" : "Email Address";
    IconData typeIcon = isPhantom
        ? Icons.phone_android_rounded
        : Icons.email_outlined;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 450),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 30, 24, 20),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.05),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(30),
                    ),
                    border: Border(
                      bottom: BorderSide(
                        color: isDark ? Colors.white10 : Colors.grey.shade200,
                      ),
                    ),
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.lock_reset_rounded,
                          color: Colors.redAccent,
                          size: 40,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        "Reset Parent Password",
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: Colors.redAccent,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "This action will immediately invalidate their current app session and require them to log in with the new key.",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.blue.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(typeIcon, color: Colors.blue, size: 24),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Text(
                                "Targeting $loginType:\n$displayId",
                                style: const TextStyle(
                                  color: Colors.blue,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        controller: pwdController,
                        decoration: InputDecoration(
                          labelText: "New Temporary Password",
                          prefixIcon: const Icon(
                            Icons.vpn_key_rounded,
                            color: Colors.redAccent,
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
                              color: isDark
                                  ? Colors.white10
                                  : Colors.grey.shade200,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                              color: Colors.redAccent.withValues(alpha: 0.5),
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 30),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                side: BorderSide(color: Colors.grey.shade300),
                              ),
                              onPressed: () => Navigator.pop(ctx),
                              child: Text(
                                "CANCEL",
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 2,
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.redAccent,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              onPressed: isLoading
                                  ? null
                                  : () async {
                                      if (pwdController.text.length < 6) {
                                        onError(
                                          "Password must be at least 6 characters.",
                                        );
                                        return;
                                      }
                                      setDialogState(() => isLoading = true);
                                      try {
                                        final response = await supabase
                                            .functions
                                            .invoke(
                                              'reset-parent-password',
                                              body: {
                                                'email': targetLoginId,
                                                'newPassword':
                                                    pwdController.text,
                                              },
                                            );
                                        if (response.data != null &&
                                            response.data['error'] != null) {
                                          setDialogState(
                                            () => isLoading = false,
                                          );
                                          onError(
                                            "Reset Failed: ${response.data['error']}",
                                          );
                                          return;
                                        }
                                        if (context.mounted) {
                                          Navigator.pop(ctx);
                                          onSuccess(
                                            "Password Reset",
                                            "The parent's password has been successfully changed to: \n\n${pwdController.text}",
                                          );
                                        }
                                      } catch (e) {
                                        setDialogState(() => isLoading = false);
                                        onError("App Error: ${e.toString()}");
                                      }
                                    },
                              child: isLoading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: TridetaLoader(color: Colors.white),
                                    )
                                  : const Text(
                                      "CONFIRM RESET",
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ],
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
