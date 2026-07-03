import 'package:flutter/material.dart';

class LoginBrandingPanel extends StatelessWidget {
  final Color primaryColor;

  const LoginBrandingPanel({super.key, required this.primaryColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [primaryColor.withValues(alpha: 0.8), primaryColor],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.school_rounded, size: 100, color: Colors.white),
            const SizedBox(height: 20),
            const Text(
              "TRIDETA",
              style: TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 3.0,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              "Next-Generation School Management",
              style: TextStyle(
                fontSize: 18,
                color: Colors.white.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
