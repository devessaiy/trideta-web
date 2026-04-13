import 'package:trideta_v2/utils/auth_error_handler.dart';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';

// --- IMPORT YOUR ADMIN MODULAR SCREENS ---
import 'package:trideta_v2/screens/admin/record_payment_screen.dart';
import 'package:trideta_v2/screens/admin/receipt_history_screen.dart';
import 'package:trideta_v2/screens/admin/fee_structure_screen.dart';

import 'package:trideta_v2/screens/auth/login_screen.dart';

class FinanceDashboardScreen extends StatefulWidget {
  final String userRole;

  const FinanceDashboardScreen({super.key, this.userRole = 'bursar'});

  @override
  State<FinanceDashboardScreen> createState() => _FinanceDashboardScreenState();
}

class _FinanceDashboardScreenState extends State<FinanceDashboardScreen>
    with AuthErrorHandler {
  final _supabase = Supabase.instance.client;

  int _currentIndex = 0;
  bool _isLoading = true;
  String? _schoolId;
  String _schoolName = "Loading...";
  String? _schoolLogoUrl;

  String? _bursarName;
  String? _bursarAvatar;
  String _currentSession = "";

  // Data Stores
  List<Map<String, dynamic>> _students = [];
  List<String> _activeClasses = ['All Classes'];
  String _selectedClassFilter = 'All Classes';

  double _totalOutstanding = 0.0;
  double _totalCollected = 0.0;

  // Avatar State
  Uint8List? _newAvatarBytes;
  String _newAvatarExtension = 'jpg';
  bool _isUploadingAvatar = false;

  @override
  void initState() {
    super.initState();
    _fetchAllData();
  }

  Future<void> _fetchAllData() async {
    setState(() => _isLoading = true);
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      // 1. Get Bursar Profile
      final profile = await _supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .single();
      _schoolId = profile['school_id'];
      _bursarName = profile['full_name'];
      _bursarAvatar = profile['passport_url'];

      if (_schoolId == null) {
        setState(() => _isLoading = false);
        return;
      }

      // Fetch School Details for Header
      final schoolData = await _supabase
          .from('schools')
          .select('name, logo_url, active_classes, current_session')
          .eq('id', _schoolId!)
          .single();
      _schoolName = schoolData['name'] ?? "My School";
      _schoolLogoUrl = schoolData['logo_url'];
      _currentSession = schoolData['current_session'] ?? "";

      final fetchedClasses = List<String>.from(
        schoolData['active_classes'] ?? [],
      );
      _activeClasses = ['All Classes', ...fetchedClasses];

      // 3. Fetch from the dedicated tables
      final studentsRes = await _supabase
          .from('students')
          .select()
          .eq('school_id', _schoolId!);

      final feesRes = await _supabase
          .from('fee_structures')
          .select()
          .eq('school_id', _schoolId!)
          .eq('academic_session', _currentSession);

      final paymentsRes = await _supabase
          .from('transactions')
          .select('student_id, amount')
          .eq('school_id', _schoolId!)
          .eq('academic_session', _currentSession);

      // 4. PROCESS THE DYNAMIC CALCULATIONS
      double totalCollected = 0.0;
      double totalExpected = 0.0;

      for (var p in paymentsRes) {
        totalCollected += (p['amount'] ?? 0).toDouble();
      }

      // Process Students List
      List<Map<String, dynamic>> processedStudents = [];

      for (var student in studentsRes) {
        String sId = student['id'].toString();
        String sClass = student['class_level'] ?? '';
        String sCategory = student['category'] ?? 'Regular';

        // Calculate how much this specific student is supposed to pay
        double expectedFee = 0.0;
        for (var fee in feesRes) {
          List<dynamic> appClasses = fee['applicable_classes'] ?? [];
          List<dynamic> appCategories = fee['applicable_categories'] ?? [];

          if (appClasses.contains(sClass) &&
              appCategories.contains(sCategory)) {
            expectedFee += (fee['amount'] ?? 0).toDouble();
          }
        }

        // Calculate how much this student has actually paid
        double amountPaid = 0.0;
        for (var p in paymentsRes) {
          if (p['student_id'].toString() == sId) {
            amountPaid += (p['amount'] ?? 0).toDouble();
          }
        }

        // Determine Balance and Status
        double balance = expectedFee - amountPaid;
        totalExpected += expectedFee;

        String status = 'Unpaid';
        if (expectedFee > 0 && amountPaid >= expectedFee) {
          status = 'Fully Paid';
          balance = 0.0; // Cap it
        } else if (amountPaid > 0 && amountPaid < expectedFee) {
          status = 'Partly Paid';
        } else if (expectedFee == 0) {
          status = 'Fully Paid';
          balance = 0.0;
        }

        processedStudents.add({
          'id': student['id'],
          'full_name': '${student['first_name']} ${student['last_name']}',
          'student_class': sClass,
          'admission_no': student['admission_no'] ?? 'N/A',
          'balance': balance,
          'payment_status': status,
          'passport_url': student['passport_url'],
        });
      }

      double outstanding = totalExpected - totalCollected;
      if (outstanding < 0) outstanding = 0;

      if (mounted) {
        setState(() {
          _students = processedStudents;
          _totalOutstanding = outstanding;
          _totalCollected = totalCollected;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Finance Fetch Error: $e");
      if (mounted) {
        setState(() => _isLoading = false);
        showAuthErrorDialog(
          "Failed to sync financial data. Check your connection.",
        );
      }
    }
  }

  Future<void> _onTabTapped(int index) async {
    if (_newAvatarBytes != null && index != 3) {
      bool? discard = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Unsaved Profile Picture"),
          content: const Text(
            "You have an unsaved profile picture. Discard it?",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Keep Editing"),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("Discard", style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );
      if (discard != true) return;
      setState(() => _newAvatarBytes = null);
    }
    setState(() => _currentIndex = index);
  }

  void _showChangePasswordDialog() {
    final newPasswordCtrl = TextEditingController();
    final confirmPasswordCtrl = TextEditingController();
    bool isSaving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text("Change Password"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: newPasswordCtrl,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: "New Password",
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: confirmPasswordCtrl,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: "Confirm Password",
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.pop(context),
                child: const Text(
                  "Cancel",
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                ),
                onPressed: isSaving
                    ? null
                    : () async {
                        if (newPasswordCtrl.text.isEmpty ||
                            newPasswordCtrl.text.length < 6)
                          return;
                        if (newPasswordCtrl.text != confirmPasswordCtrl.text) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("Passwords do not match"),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return;
                        }
                        setDialogState(() => isSaving = true);
                        try {
                          await _supabase.auth.updateUser(
                            UserAttributes(password: newPasswordCtrl.text),
                          );
                          if (mounted) {
                            Navigator.pop(context);
                            showSuccessDialog(
                              "Password Updated",
                              "Your account is secured.",
                            );
                          }
                        } catch (e) {
                          setDialogState(() => isSaving = false);
                          showAuthErrorDialog("Error: $e");
                        }
                      },
                child: isSaving
                    ? const SizedBox(
                        height: 15,
                        width: 15,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        "Update",
                        style: TextStyle(color: Colors.white),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _uploadAvatar() async {
    if (_newAvatarBytes == null) return;
    setState(() => _isUploadingAvatar = true);
    try {
      final user = _supabase.auth.currentUser;
      final fileName =
          'bursar_${user!.id}_${DateTime.now().millisecondsSinceEpoch}.$_newAvatarExtension';
      await _supabase.storage
          .from('staff_passports')
          .uploadBinary(fileName, _newAvatarBytes!);
      final newUrl = _supabase.storage
          .from('staff_passports')
          .getPublicUrl(fileName);
      await _supabase
          .from('profiles')
          .update({'passport_url': newUrl})
          .eq('id', user.id);

      setState(() {
        _bursarAvatar = newUrl;
        _newAvatarBytes = null;
        _isUploadingAvatar = false;
      });
      if (mounted)
        showSuccessDialog(
          "Profile Updated",
          "Your profile picture has been saved.",
        );
    } catch (e) {
      setState(() => _isUploadingAvatar = false);
      if (mounted) showAuthErrorDialog("Upload failed. Try again.");
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC);
    Color navBarColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    Color primaryColor = Theme.of(context).primaryColor;

    final List<Widget> pages = [
      _buildDashboardTab(isDark, primaryColor),
      _buildStudentsTab(isDark, primaryColor),
      const ReceiptHistoryScreen(),
      _buildProfileTab(isDark, primaryColor),
    ];

    // 🚨 SHAPE-SHIFTER: LayoutBuilder
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth > 800) {
          // 💻 DESKTOP LAYOUT (Side Navigation Rail)
          return Scaffold(
            backgroundColor: bgColor,
            body: Row(
              children: [
                NavigationRail(
                  backgroundColor: navBarColor,
                  selectedIndex: _currentIndex,
                  onDestinationSelected: _onTabTapped,
                  selectedIconTheme: IconThemeData(color: primaryColor),
                  selectedLabelTextStyle: TextStyle(
                    color: primaryColor,
                    fontWeight: FontWeight.bold,
                  ),
                  unselectedIconTheme: const IconThemeData(color: Colors.grey),
                  unselectedLabelTextStyle: const TextStyle(color: Colors.grey),
                  indicatorColor: primaryColor.withOpacity(0.1),
                  labelType: NavigationRailLabelType.all,
                  leading: Padding(
                    padding: const EdgeInsets.only(bottom: 20, top: 15),
                    child: CircleAvatar(
                      radius: 24,
                      backgroundColor: primaryColor.withOpacity(0.1),
                      backgroundImage: _bursarAvatar != null
                          ? NetworkImage(_bursarAvatar!)
                          : null,
                      child: _bursarAvatar == null
                          ? Icon(Icons.person, color: primaryColor)
                          : null,
                    ),
                  ),
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.dashboard_outlined),
                      selectedIcon: Icon(Icons.dashboard),
                      label: Text('Dashboard'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.people_outline),
                      selectedIcon: Icon(Icons.people),
                      label: Text('Students'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.receipt_long_outlined),
                      selectedIcon: Icon(Icons.receipt_long),
                      label: Text('History'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.person_outline),
                      selectedIcon: Icon(Icons.person),
                      label: Text('Profile'),
                    ),
                  ],
                ),
                const VerticalDivider(thickness: 1, width: 1),
                Expanded(
                  child: _isLoading
                      ? Center(
                          child: CircularProgressIndicator(color: primaryColor),
                        )
                      : Center(
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 1100),
                            child: IndexedStack(
                              index: _currentIndex,
                              children: pages,
                            ),
                          ),
                        ),
                ),
              ],
            ),
          );
        } else {
          // 📱 MOBILE LAYOUT (Bottom Navigation Bar)
          return Scaffold(
            backgroundColor: bgColor,
            body: _isLoading
                ? Center(child: CircularProgressIndicator(color: primaryColor))
                : IndexedStack(index: _currentIndex, children: pages),
            bottomNavigationBar: Container(
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: NavigationBar(
                selectedIndex: _currentIndex,
                onDestinationSelected: _onTabTapped,
                backgroundColor: navBarColor,
                elevation: 0,
                indicatorColor: primaryColor.withOpacity(0.1),
                height: 70,
                destinations:
                    [
                      const NavigationDestination(
                        icon: Icon(Icons.dashboard_outlined),
                        selectedIcon: Icon(Icons.dashboard),
                        label: 'Dashboard',
                      ),
                      const NavigationDestination(
                        icon: Icon(Icons.people_outline),
                        selectedIcon: Icon(Icons.people),
                        label: 'Students',
                      ),
                      const NavigationDestination(
                        icon: Icon(Icons.receipt_long_outlined),
                        selectedIcon: Icon(Icons.receipt_long),
                        label: 'History',
                      ),
                      const NavigationDestination(
                        icon: Icon(Icons.person_outline),
                        selectedIcon: Icon(Icons.person),
                        label: 'Profile',
                      ),
                    ].map((dest) {
                      return NavigationDestination(
                        icon: dest.icon,
                        selectedIcon: Icon(
                          (dest.selectedIcon as Icon).icon,
                          color: primaryColor,
                        ),
                        label: dest.label,
                      );
                    }).toList(),
              ),
            ),
          );
        }
      },
    );
  }

  // --- SLEEK TABS ---

  Widget _buildDashboardTab(bool isDark, Color primaryColor) {
    Color textColor = isDark ? Colors.white : Colors.black87;
    Color subTextColor = isDark ? Colors.white70 : Colors.grey[600]!;

    return SafeArea(
      child: RefreshIndicator(
        color: primaryColor,
        onRefresh: _fetchAllData,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 25),
          children: [
            Row(
              children: [
                Container(
                  height: 65,
                  width: 65,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 8,
                      ),
                    ],
                    border: Border.all(
                      color: primaryColor.withOpacity(0.2),
                      width: 2,
                    ),
                    image: _schoolLogoUrl != null
                        ? DecorationImage(
                            image: NetworkImage(_schoolLogoUrl!),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: _schoolLogoUrl == null
                      ? Icon(
                          Icons.account_balance_rounded,
                          color: primaryColor,
                          size: 32,
                        )
                      : null,
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _schoolName,
                        style: TextStyle(
                          fontSize: 14,
                          color: subTextColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        _bursarName ?? "Bursar",
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 30),
            Row(
              children: [
                Expanded(
                  child: _buildMetricCard(
                    "Collected (NGN)",
                    _totalCollected,
                    Colors.green,
                    Icons.trending_up_rounded,
                    isDark,
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: _buildMetricCard(
                    "Outstanding (NGN)",
                    _totalOutstanding,
                    Colors.red,
                    Icons.warning_amber_rounded,
                    isDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 30),
            Text(
              "FINANCIAL ACTIONS",
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: primaryColor.withOpacity(0.8),
                fontSize: 13,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 15),

            _buildActionTile(
              "Record a Payment",
              "Process fees & print thermal receipts",
              Icons.add_card_rounded,
              primaryColor,
              isDark,
              () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const RecordPaymentScreen(),
                  ),
                ).then((_) => _fetchAllData());
              },
            ),

            // Re-adding the Fee Structures tile with proper RBAC.
            // Bursars are locked out of editing/deleting inside FeeStructureScreen due to widget.userRole.
            _buildActionTile(
              "Fee Structures",
              "View active school fee configurations",
              Icons.list_alt_rounded,
              Colors.orange,
              isDark,
              () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const FeeStructureScreen()),
                ).then((_) => _fetchAllData());
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStudentsTab(bool isDark, Color primaryColor) {
    Color cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    return SafeArea(
      child: DefaultTabController(
        length: 3,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
              child: Text(
                "Debtors Roster",
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
            ),
            // Class Filter Dropdown
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? Colors.white10 : Colors.grey.shade300,
                ),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: _selectedClassFilter,
                  icon: Icon(Icons.filter_list_rounded, color: primaryColor),
                  items: _activeClasses
                      .map(
                        (c) => DropdownMenuItem(
                          value: c,
                          child: Text(
                            c,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (val) =>
                      setState(() => _selectedClassFilter = val!),
                  dropdownColor: cardColor,
                ),
              ),
            ),
            const SizedBox(height: 10),
            // Payment Status Tabs
            TabBar(
              labelColor: primaryColor,
              unselectedLabelColor: Colors.grey,
              indicatorColor: primaryColor,
              indicatorWeight: 3,
              tabs: const [
                Tab(text: "Unpaid"),
                Tab(text: "Partly Paid"),
                Tab(text: "Cleared"),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _buildStudentListByStatus(
                    'Unpaid',
                    isDark,
                    primaryColor,
                    cardColor,
                  ),
                  _buildStudentListByStatus(
                    'Partly Paid',
                    isDark,
                    primaryColor,
                    cardColor,
                  ),
                  _buildStudentListByStatus(
                    'Fully Paid',
                    isDark,
                    primaryColor,
                    cardColor,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helper widget to build the lists based on the selected tab
  Widget _buildStudentListByStatus(
    String status,
    bool isDark,
    Color primaryColor,
    Color cardColor,
  ) {
    final filtered = _students.where((s) {
      final matchesClass =
          _selectedClassFilter == 'All Classes' ||
          s['student_class'] == _selectedClassFilter;
      final matchesStatus = s['payment_status'] == status;
      return matchesClass && matchesStatus;
    }).toList();

    if (filtered.isEmpty) {
      return Center(
        child: Text(
          "No students found in this category.",
          style: TextStyle(color: Colors.grey[500]),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: filtered.length,
      itemBuilder: (ctx, i) {
        final s = filtered[i];
        final bool isClear = s['payment_status'] == 'Fully Paid';
        String fName = s['full_name']?.toString() ?? "";
        String initial = fName.isNotEmpty ? fName[0].toUpperCase() : "?";

        return Card(
          color: cardColor,
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
            side: BorderSide(
              color: isDark ? Colors.white10 : Colors.grey.shade200,
            ),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            leading: CircleAvatar(
              backgroundColor: primaryColor.withOpacity(0.1),
              backgroundImage: s['passport_url'] != null
                  ? NetworkImage(s['passport_url'])
                  : null,
              child: s['passport_url'] == null
                  ? Text(
                      initial,
                      style: TextStyle(
                        color: primaryColor,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  : null,
            ),
            title: Text(
              fName.toUpperCase(),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            subtitle: Text(
              "${s['student_class']} • ${s['admission_no']}",
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  isClear ? "CLEARED" : "OWES",
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: isClear ? Colors.green : Colors.red,
                  ),
                ),
                Text(
                  isClear ? "₦0" : "₦${s['balance'].toStringAsFixed(0)}",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: isClear ? Colors.green : Colors.red,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildProfileTab(bool isDark, Color primaryColor) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            "My Profile",
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 30),
          Center(
            child: Stack(
              children: [
                CircleAvatar(
                  radius: 50,
                  backgroundColor: isDark ? Colors.white10 : Colors.grey[200],
                  backgroundImage: _newAvatarBytes != null
                      ? MemoryImage(_newAvatarBytes!) as ImageProvider
                      : (_bursarAvatar != null
                            ? NetworkImage(_bursarAvatar!)
                            : null),
                  child: (_bursarAvatar == null && _newAvatarBytes == null)
                      ? const Icon(Icons.person, size: 50, color: Colors.grey)
                      : null,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: InkWell(
                    onTap: () async {
                      final image = await ImagePicker().pickImage(
                        source: ImageSource.gallery,
                        imageQuality: 50,
                      );
                      if (image != null) {
                        final bytes = await image.readAsBytes();
                        setState(() {
                          _newAvatarBytes = bytes;
                          _newAvatarExtension = image.name.split('.').last;
                        });
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: primaryColor,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.camera_alt,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_newAvatarBytes != null) ...[
            const SizedBox(height: 15),
            Center(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                onPressed: _isUploadingAvatar ? null : _uploadAvatar,
                icon: _isUploadingAvatar
                    ? const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.check, color: Colors.white),
                label: Text(
                  _isUploadingAvatar ? "Saving..." : "Save Profile Picture",
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          Center(
            child: Text(
              _bursarName ?? "Bursar",
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
          ),
          const Center(
            child: Text(
              "Finance Operations",
              style: TextStyle(
                color: Colors.green,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 40),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text("Change Password"),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: _showChangePasswordDialog,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text(
              "Secure Logout",
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
            onTap: () async {
              bool? confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text("Logout"),
                  content: const Text("Are you sure you want to log out?"),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text("Cancel"),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text(
                        "Logout",
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                await _supabase.auth.signOut();
                if (mounted)
                  Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
                    MaterialPageRoute(
                      builder: (context) => const LoginScreen(),
                    ),
                    (route) => false,
                  );
              }
            },
          ),
        ],
      ),
    );
  }

  // --- HELPERS ---

  Widget _buildMetricCard(
    String title,
    double amount,
    Color color,
    IconData icon,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? Colors.white10 : Colors.transparent),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 15),
          Text(
            title,
            style: TextStyle(
              color: Colors.grey[500],
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 5),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              amount.toStringAsFixed(0),
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 26,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionTile(
    String title,
    String subtitle,
    IconData icon,
    Color color,
    bool isDark,
    VoidCallback onTap,
  ) {
    Color cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    Color textColor = isDark ? Colors.white : Colors.black87;

    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.05) : Colors.transparent,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(icon, color: color, size: 28),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                          color: textColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.white54 : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 24,
                  color: isDark ? Colors.white24 : Colors.grey[300],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
