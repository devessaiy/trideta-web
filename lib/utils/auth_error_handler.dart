import 'dart:io';
import 'package:flutter/material.dart';

mixin AuthErrorHandler<T extends StatefulWidget> on State<T> {
  Future<bool> hasInternetConnection() async {
    try {
      final result = await InternetAddress.lookup(
        'google.com',
      ).timeout(const Duration(seconds: 5));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  void showNoInternetDialog({VoidCallback? onRetry}) {
    if (!mounted) return;
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color primaryColor = Theme.of(context).primaryColor;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Column(
          children: [
            Icon(Icons.wifi_off_rounded, color: Colors.red, size: 50),
            SizedBox(height: 10),
            Text(
              "Connection Lost",
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
            ),
          ],
        ),
        content: Text(
          "We couldn't connect to the server. Please check your internet connection and try again.",
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isDark ? Colors.white70 : Colors.black87,
            fontSize: 14,
          ),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          if (onRetry != null)
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                "CANCEL",
                style: TextStyle(
                  color: Colors.grey,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              if (onRetry != null) onRetry();
            },
            child: Text(
              onRetry != null ? "RETRY NOW" : "OKAY",
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void showAuthErrorDialog(String errorMsg, {VoidCallback? onRetry}) {
    if (!mounted) return;
    final errorLower = errorMsg.toLowerCase();
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color primaryColor = Theme.of(context).primaryColor;

    if (errorLower.contains("socketexception") ||
        errorLower.contains("failed host lookup") ||
        errorLower.contains("clientexception")) {
      showNoInternetDialog(onRetry: onRetry);
      return;
    }

    String title = "Oops! Something went wrong";
    String message = "We encountered an unexpected issue. Please try again.";

    if (errorLower.contains("invalid login credentials")) {
      title = "Incorrect Details";
      message =
          "The password you entered is wrong, or this email is not registered. Please check your spelling and try again.";
    } else if (errorLower.contains("not confirmed")) {
      title = "Email Not Verified";
      message =
          "You haven't verified your email address yet. Please check your inbox for the welcome link.";
    } else if (errorLower.contains("rate limit")) {
      title = "Too Many Attempts";
      message =
          "You've requested too many codes recently. Please wait a moment and try again.";
    } else if (errorLower.contains("token has expired")) {
      title = "Invalid Code";
      message =
          "The 6-digit code you entered is incorrect or has expired. Please request a new one.";
    } else if (errorMsg.isNotEmpty) {
      message = errorMsg;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Column(
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: Colors.red,
              size: 50,
            ),
            const SizedBox(height: 10),
            Text(
              title,
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
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: isDark ? Colors.white70 : Colors.black87,
          ),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          if (onRetry != null)
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                "CANCEL",
                style: TextStyle(
                  color: Colors.grey,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              if (onRetry != null) onRetry();
            },
            child: Text(
              onRetry != null ? "TRY AGAIN" : "GOT IT",
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void showSuccessDialog(String title, String message, {VoidCallback? onOkay}) {
    if (!mounted) return;
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color primaryColor = Theme.of(context).primaryColor;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Column(
          children: [
            const Icon(
              Icons.check_circle_rounded,
              color: Colors.green,
              size: 60,
            ),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 20,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
          ],
        ),
        content: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: isDark ? Colors.white70 : Colors.black87,
          ),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              if (onOkay != null) onOkay();
            },
            child: const Text(
              "AWESOME",
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
}
