import 'package:flutter/material.dart';
import 'package:trideta_v2/utils/app_info.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutTridetaScreen extends StatelessWidget {
  const AboutTridetaScreen({super.key});

  static const List<_Feature> _features = [
    _Feature(
      Icons.how_to_reg_rounded,
      'Admissions & student records',
      'Admit students and keep every record in one place.',
    ),
    _Feature(
      Icons.fact_check_rounded,
      'Attendance',
      'Mark attendance by hand or by scanning student QR codes.',
    ),
    _Feature(
      Icons.assignment_turned_in_rounded,
      'Results & report cards',
      'Enter scores, compute results and publish report cards.',
    ),
    _Feature(
      Icons.account_balance_wallet_rounded,
      'Fees, payments & receipts',
      'Record payments, track balances and print receipts.',
    ),
    _Feature(
      Icons.campaign_rounded,
      'Alerts & announcements',
      'Keep staff and parents informed.',
    ),
    _Feature(
      Icons.family_restroom_rounded,
      'Parent portal',
      'Parents follow their children\'s progress and fees.',
    ),
  ];

  Future<void> _open(BuildContext context, String url) async {
    try {
      final ok = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!ok && context.mounted) _failed(context);
    } catch (_) {
      if (context.mounted) _failed(context);
    }
  }

  void _failed(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Could not open the link. Please check your connection."),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;
    final bg = isDark ? const Color(0xFF121212) : const Color(0xFFF5F7FA);
    final card = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final subColor = isDark ? Colors.white60 : Colors.grey.shade600;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: const Text('About Trideta'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: textColor,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    Container(
                      width: 96,
                      height: 96,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: card,
                        borderRadius: BorderRadius.circular(26),
                        boxShadow: [
                          BoxShadow(
                            color: primary.withValues(alpha: 0.18),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Image.asset(
                        'assets/icon/app_icon.png',
                        errorBuilder: (_, _, _) => Icon(
                          Icons.school_rounded,
                          color: primary,
                          size: 48,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Trideta',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'School management, made simple.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: subColor),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: card,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        children: [
                          for (final f in _features)
                            ListTile(
                              leading: CircleAvatar(
                                radius: 20,
                                backgroundColor: primary.withValues(
                                  alpha: 0.12,
                                ),
                                child: Icon(f.icon, color: primary, size: 20),
                              ),
                              title: Text(
                                f.title,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14.5,
                                  color: textColor,
                                ),
                              ),
                              subtitle: Text(
                                f.subtitle,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: subColor,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: card,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: ListTile(
                        leading: Icon(
                          Icons.privacy_tip_outlined,
                          color: primary,
                        ),
                        title: Text(
                          'Privacy Policy',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: textColor,
                          ),
                        ),
                        trailing: Icon(
                          Icons.open_in_new_rounded,
                          size: 18,
                          color: subColor,
                        ),
                        onTap: () => _open(context, kPrivacyUrl),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ---- footer: version + from Skynex ----
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Version $kAppVersion',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: subColor,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Semantics(
                    button: true,
                    label: 'From Skynex. Visit skynex.com.ng',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _open(context, kSkynexUrl),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 8,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'from',
                              style: TextStyle(fontSize: 12, color: subColor),
                            ),
                            Text(
                              'SKYNEX',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 3,
                                color: textColor,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'skynex.com.ng',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: primary,
                                decoration: TextDecoration.underline,
                                decorationColor: primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Feature {
  final IconData icon;
  final String title;
  final String subtitle;
  const _Feature(this.icon, this.title, this.subtitle);
}
