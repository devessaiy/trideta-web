import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';

import 'package:trideta_v2/screens/auth/login_screen.dart';

class LandingPageScreen extends StatefulWidget {
  const LandingPageScreen({super.key});

  @override
  State<LandingPageScreen> createState() => _LandingPageScreenState();
}

class _LandingPageScreenState extends State<LandingPageScreen> {
  final _supabase = Supabase.instance.client;

  // Keys for smooth scrolling
  final GlobalKey _productsKey = GlobalKey();
  final GlobalKey _announcementsKey = GlobalKey();

  List<Map<String, dynamic>> _announcements = [];
  bool _isLoadingAnnouncements = true;

  @override
  void initState() {
    super.initState();
    _fetchGlobalAnnouncements();
  }

  // 🚨 FETCH DYNAMIC PLATFORM ANNOUNCEMENTS
  Future<void> _fetchGlobalAnnouncements() async {
    try {
      // Create a table called 'trideta_announcements' in your Supabase for this!
      final data = await _supabase
          .from('trideta_announcements')
          .select()
          .order('created_at', ascending: false)
          .limit(6); // Fetch latest 6

      if (mounted) {
        setState(() {
          _announcements = List<Map<String, dynamic>>.from(data);
          _isLoadingAnnouncements = false;
        });
      }
    } catch (e) {
      debugPrint("Failed to fetch announcements: $e");
      if (mounted) {
        setState(() => _isLoadingAnnouncements = false);
      }
    }
  }

  // 🚨 URL LAUNCHER FOR QUICK LINKS & CONTACTS
  Future<void> _launchURL(String urlString) async {
    final Uri url = Uri.parse(urlString);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Could not open link.")));
      }
    }
  }

  // Smooth scroll helper
  void _scrollToSection(GlobalKey key) {
    if (key.currentContext != null) {
      Scrollable.ensureVisible(
        key.currentContext!,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isDesktop = MediaQuery.of(context).size.width > 800;
    Color primaryColor = Theme.of(context).primaryColor;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        title: Row(
          children: [
            Icon(Icons.school_rounded, color: primaryColor, size: 30),
            const SizedBox(width: 10),
            Text(
              "TRIDETA",
              style: TextStyle(
                color: primaryColor,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
        actions: [
          if (isDesktop) ...[
            TextButton(
              onPressed: () => _scrollToSection(_productsKey),
              child: const Text(
                "Products",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 10),
            TextButton(
              onPressed: () => _scrollToSection(_announcementsKey),
              child: const Text(
                "Announcements",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 20),
          ],
          Padding(
            padding: const EdgeInsets.only(right: 20, top: 10, bottom: 10),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                );
              },
              child: const Text(
                "Portals",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // ==========================================
            // 1. HERO SECTION
            // ==========================================
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(
                horizontal: isDesktop ? 100 : 20,
                vertical: 100,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [primaryColor.withOpacity(0.05), Colors.white],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 15,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      "By Afritech Solutions Company",
                      style: TextStyle(
                        color: primaryColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    "Next-Generation\nSchool Management",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: isDesktop ? 64 : 40,
                      fontWeight: FontWeight.w900,
                      height: 1.1,
                      color: const Color(0xFF1E1E1E),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    "Trideta brings administrators, teachers, and parents together\nin one seamless, cloud-powered platform.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: isDesktop ? 20 : 16,
                      color: Colors.grey[600],
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 40),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 40,
                        vertical: 20,
                      ),
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                      elevation: 5,
                    ),
                    onPressed: () => _scrollToSection(_productsKey),
                    child: const Text(
                      "Discover Our Products",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ==========================================
            // 2. QUICK LINKS / PRODUCTS SECTION
            // ==========================================
            Container(
              key: _productsKey,
              width: double.infinity,
              constraints: const BoxConstraints(maxWidth: 1200),
              padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text(
                    "Our Portfolio",
                    style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    "Explore our deployed solutions powered by Afritech",
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 40),
                  Wrap(
                    spacing: 20,
                    runSpacing: 20,
                    alignment: WrapAlignment.center,
                    children: [
                      _buildQuickLinkCard(
                        title: "Arrida College",
                        subtitle: "Official Website Portal",
                        icon: Icons.account_balance_rounded,
                        color: Colors.blue,
                        url: "https://arrida.vercel.app",
                        isDesktop: isDesktop,
                      ),
                      _buildQuickLinkCard(
                        title: "Subulussalaam",
                        subtitle: "Official Website Portal",
                        icon: Icons.menu_book_rounded,
                        color: Colors.green,
                        url: "https://subulussalaam.vercel.app",
                        isDesktop: isDesktop,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // ==========================================
            // 3. OFFICIAL ANNOUNCEMENTS SECTION
            // ==========================================
            Container(
              key: _announcementsKey,
              width: double.infinity,
              color: Colors.white,
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 1200),
                  padding: const EdgeInsets.symmetric(
                    vertical: 80,
                    horizontal: 20,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.campaign_rounded,
                            color: Colors.orange,
                            size: 30,
                          ),
                          SizedBox(width: 15),
                          Text(
                            "Platform Announcements",
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 40),

                      if (_isLoadingAnnouncements)
                        Center(
                          child: CircularProgressIndicator(color: primaryColor),
                        )
                      else if (_announcements.isEmpty)
                        Center(
                          child: Text(
                            "No official announcements at this time.",
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 16,
                            ),
                          ),
                        )
                      else
                        Wrap(
                          spacing: 20,
                          runSpacing: 20,
                          children: _announcements.map((announcement) {
                            return _buildNewsCard(
                              title: announcement['title'] ?? 'Update',
                              summary: announcement['content'] ?? '',
                              dateStr: announcement['created_at'],
                              isDesktop: isDesktop,
                            );
                          }).toList(),
                        ),
                    ],
                  ),
                ),
              ),
            ),

            // ==========================================
            // 4. FOOTER & CONTACT
            // ==========================================
            Container(
              width: double.infinity,
              color: const Color(0xFF1E1E1E),
              padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 40),
              child: Column(
                children: [
                  const Text(
                    "Ready to digitize your school?",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 30),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildContactButton(
                        icon: Icons.chat_rounded,
                        label: "WhatsApp Us",
                        color: Colors.green,
                        onTap: () => _launchURL("https://wa.me/2347040686186"),
                      ),
                      const SizedBox(width: 15),
                      _buildContactButton(
                        icon: Icons.email_rounded,
                        label: "Email Us",
                        color: Colors.blue,
                        onTap: () => _launchURL("mailto:trideta.app@gmail.com"),
                      ),
                    ],
                  ),
                  const SizedBox(height: 60),
                  const Divider(color: Colors.white24),
                  const SizedBox(height: 20),
                  const Text(
                    "© 2026 Afritech Solutions Company. All rights reserved.",
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    "Powered by Trideta Engine",
                    style: TextStyle(color: Colors.white38, fontSize: 10),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- WIDGET HELPERS ---

  Widget _buildQuickLinkCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required String url,
    required bool isDesktop,
  }) {
    return InkWell(
      onTap: () => _launchURL(url),
      borderRadius: BorderRadius.circular(15),
      child: Container(
        width: isDesktop ? 380 : double.infinity,
        padding: const EdgeInsets.all(30),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 30),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(Icons.open_in_new_rounded, color: Colors.grey[400], size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildNewsCard({
    required String title,
    required String summary,
    required String? dateStr,
    required bool isDesktop,
  }) {
    String formattedDate = "Recent";
    if (dateStr != null) {
      formattedDate = DateFormat(
        'MMM dd, yyyy',
      ).format(DateTime.parse(dateStr));
    }

    return Container(
      width: isDesktop ? 350 : double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              formattedDate,
              style: const TextStyle(
                color: Colors.blue,
                fontWeight: FontWeight.bold,
                fontSize: 10,
              ),
            ),
          ),
          const SizedBox(height: 15),
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 18,
              color: Color(0xFF1E1E1E),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            summary,
            style: TextStyle(
              color: Colors.grey[700],
              fontSize: 14,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      ),
      onPressed: onTap,
      icon: Icon(icon, size: 20),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }
}
