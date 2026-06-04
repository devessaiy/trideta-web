import 'dart:async';
import 'package:flutter/material.dart';

class TeacherDashboardCarousel extends StatefulWidget {
  final Map<String, dynamic>? latestAlert;
  final Color primaryColor;
  final bool isDark;

  const TeacherDashboardCarousel({
    super.key,
    this.latestAlert,
    required this.primaryColor,
    required this.isDark,
  });

  @override
  State<TeacherDashboardCarousel> createState() =>
      _TeacherDashboardCarouselState();
}

class _TeacherDashboardCarouselState extends State<TeacherDashboardCarousel> {
  late PageController _pageController;
  int _currentPage = 0;
  Timer? _timer;
  late List<Widget> _carouselItems;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
    _buildItems();
    _startAutoSlide();
  }

  @override
  void didUpdateWidget(covariant TeacherDashboardCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Rebuild the list if the alert or theme changes
    if (oldWidget.latestAlert != widget.latestAlert ||
        oldWidget.isDark != widget.isDark) {
      _buildItems();
    }
  }

  void _buildItems() {
    _carouselItems = [];

    // 1. Add the latest alert if it exists
    if (widget.latestAlert != null) {
      _carouselItems.add(_buildAlertCard(widget.latestAlert!));
    }

    // 2. Add the Step-by-Step Instruction Cards
    _carouselItems.addAll([
      _buildInstructionCard(
        title: "Step 1: Daily Attendance",
        description:
            "Navigate to 'My Students & Attendance' to mark your class roster using the manual list or the QR scanner.",
        icon: Icons.qr_code_scanner_rounded,
        color: Colors.orange,
      ),
      _buildInstructionCard(
        title: "Step 2: Score Computation",
        description:
            "Use 'Enter Subject Scores' under Academic Tasks to seamlessly input Continuous Assessment and Exam marks.",
        icon: Icons.edit_document,
        color: widget.primaryColor,
      ),
      _buildInstructionCard(
        title: "Step 3: Affective Domain",
        description:
            "Finalize grading by rating student behavior and leaving your Form Master remarks for the term.",
        icon: Icons.psychology_alt_rounded,
        color: Colors.purple,
      ),
    ]);
  }

  void _startAutoSlide() {
    _timer = Timer.periodic(const Duration(seconds: 6), (timer) {
      if (_pageController.hasClients) {
        int nextPage = _currentPage + 1;
        if (nextPage >= _carouselItems.length) {
          nextPage = 0;
        }
        _pageController.animateToPage(
          nextPage,
          duration: const Duration(milliseconds: 600),
          curve: Curves.fastOutSlowIn,
        );
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  Widget _buildAlertCard(Map<String, dynamic> alert) {
    String title = alert['title'] ?? 'New Announcement';
    String message = alert['message'] ?? '';

    // Determine color based on alert type
    String type = (alert['type'] ?? '').toString().toLowerCase();
    Color alertColor = type.contains('urgent')
        ? Colors.redAccent
        : Colors.blueAccent;

    return _buildBaseCard(
      color: alertColor,
      icon: Icons.notifications_active_rounded,
      title: "LATEST: $title",
      description: message,
      isAlert: true,
    );
  }

  Widget _buildInstructionCard({
    required String title,
    required String description,
    required IconData icon,
    required Color color,
  }) {
    return _buildBaseCard(
      color: color,
      icon: icon,
      title: title,
      description: description,
      isAlert: false,
    );
  }

  Widget _buildBaseCard({
    required Color color,
    required IconData icon,
    required String title,
    required String description,
    required bool isAlert,
  }) {
    Color bgColor = widget.isDark ? const Color(0xFF1E1E1E) : Colors.white;
    Color textColor = widget.isDark ? Colors.white : const Color(0xFF1A1A2E);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isAlert
              ? color.withValues(alpha: 0.5)
              : (widget.isDark ? Colors.white10 : Colors.grey.shade200),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: isAlert ? 0.2 : 0.05),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 32),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                      color: isAlert ? color : textColor,
                      letterSpacing: -0.3,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 13,
                      color: widget.isDark
                          ? Colors.white70
                          : Colors.grey.shade600,
                      height: 1.4,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_carouselItems.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        SizedBox(
          height: 145,
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: (index) {
              setState(() => _currentPage = index);
            },
            itemCount: _carouselItems.length,
            itemBuilder: (context, index) {
              return _carouselItems[index];
            },
          ),
        ),
        const SizedBox(height: 12),
        // ─── PAGINATION DOTS ───
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_carouselItems.length, (index) {
            return AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              height: 6,
              width: _currentPage == index ? 24 : 6,
              decoration: BoxDecoration(
                color: _currentPage == index
                    ? widget.primaryColor
                    : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(3),
              ),
            );
          }),
        ),
      ],
    );
  }
}
