import 'package:trideta_v2/utils/auth_error_handler.dart';
import 'package:trideta_v2/widgets/trideta_loader.dart';
import 'package:trideta_v2/widgets/trideta_ui_kit.dart';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:screenshot/screenshot.dart';
import 'package:gal/gal.dart';

class TeacherStudentRosterScreen extends StatefulWidget {
  const TeacherStudentRosterScreen({super.key});

  @override
  State<TeacherStudentRosterScreen> createState() =>
      _TeacherStudentRosterScreenState();
}

class _TeacherStudentRosterScreenState extends State<TeacherStudentRosterScreen>
    with SingleTickerProviderStateMixin, AuthErrorHandler {
  final _supabase = Supabase.instance.client;

  bool _isLoading = true;
  String? _schoolId;

  late TabController _tabController;

  List<String> _myClasses = [];
  String? _selectedClass;
  List<Map<String, dynamic>> _allMyStudents = [];

  // Attendance State
  Map<String, String> _attendanceState = {};
  final MobileScannerController _scannerController = MobileScannerController();
  bool _isProcessingScan = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchMyStudentsAndAttendance();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  // 🚨 LOGIC UNTOUCHED
  Future<void> _fetchMyStudentsAndAttendance() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final profile = await _supabase
          .from('profiles')
          .select('school_id')
          .eq('id', user.id)
          .single();
      _schoolId = profile['school_id'];

      final assignments = await _supabase
          .from('staff_assignments')
          .select('class_assigned')
          .eq('staff_id', user.id);

      Set<String> allowedClasses = assignments
          .map((a) => a['class_assigned'].toString())
          .toSet();

      _myClasses = allowedClasses.toList()..sort();
      if (_myClasses.isNotEmpty && _selectedClass == null) {
        _selectedClass = _myClasses.first;
      }

      if (_selectedClass != null) {
        final studentsRes = await _supabase
            .from('students')
            .select(
              'id, first_name, last_name, admission_no, class_level, gender, passport_url',
            )
            .eq('school_id', _schoolId!)
            .eq('class_level', _selectedClass!)
            .order('first_name', ascending: true);

        final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
        final attendanceRes = await _supabase
            .from('attendance')
            .select('student_id, status')
            .eq('class_level', _selectedClass!)
            .eq('date', todayStr);

        Map<String, String> existingData = {};
        for (var record in attendanceRes) {
          existingData[record['student_id'].toString()] = record['status']
              .toString();
        }

        if (mounted) {
          setState(() {
            _allMyStudents = List<Map<String, dynamic>>.from(studentsRes);
            _attendanceState = existingData;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        showAuthErrorDialog("Failed to load roster and attendance: $e");
      }
    }
  }

  // 🚨 LOGIC UNTOUCHED
  Future<void> _saveManualAttendance() async {
    if (_attendanceState.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("No attendance marked yet."),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final user = _supabase.auth.currentUser!;

      List<Map<String, dynamic>> upsertData = [];
      _attendanceState.forEach((studentId, status) {
        upsertData.add({
          'school_id': _schoolId,
          'student_id': studentId,
          'class_level': _selectedClass,
          'date': todayStr,
          'status': status,
          'recorded_by': user.id,
        });
      });

      await _supabase
          .from('attendance')
          .delete()
          .eq('class_level', _selectedClass!)
          .eq('date', todayStr);
      await _supabase.from('attendance').insert(upsertData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Attendance saved successfully!"),
            backgroundColor: Colors.green,
          ),
        );
        setState(() => _isLoading = false);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) showAuthErrorDialog("Save Error: $e");
    }
  }

  // 🚨 LOGIC UNTOUCHED
  void _onDetect(BarcodeCapture capture) async {
    if (_isProcessingScan) return;
    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty || barcodes.first.rawValue == null) return;

    final String scannedAdmNo = barcodes.first.rawValue!;
    setState(() => _isProcessingScan = true);
    _scannerController.stop();

    try {
      final student = _allMyStudents.firstWhere(
        (s) => s['admission_no'] == scannedAdmNo,
      );
      await _showScannerActionPopup(student);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Admission No. $scannedAdmNo not found in $_selectedClass",
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
      await Future.delayed(const Duration(seconds: 2));
    }

    setState(() => _isProcessingScan = false);
    _scannerController.start();
  }

  // 🚨 UI POLISHED (Premium Dialog)
  Future<void> _showScannerActionPopup(Map<String, dynamic> student) async {
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    Color primaryColor = Theme.of(context).primaryColor;
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    if (_attendanceState.containsKey(student['id'].toString())) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Text(
            "Already Marked",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Text(
            "${student['first_name']} was already marked '${_attendanceState[student['id'].toString()]}' today.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                "OK",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );
      return;
    }

    String selectedStatus = 'Punctual';

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            title: Text(
              "${student['first_name']} ${student['last_name']}",
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: ['Punctual', 'Late', 'Absent', 'Sick'].map((status) {
                return RadioListTile<String>(
                  title: Text(
                    status,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  value: status,
                  groupValue: selectedStatus,
                  activeColor: primaryColor,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (val) =>
                      setDialogState(() => selectedStatus = val!),
                );
              }).toList(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text(
                  "Cancel",
                  style: TextStyle(
                    color: Colors.grey,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () async {
                  Navigator.pop(ctx);
                  try {
                    await _supabase.from('attendance').insert({
                      'school_id': _schoolId,
                      'student_id': student['id'],
                      'class_level': _selectedClass,
                      'date': todayStr,
                      'status': selectedStatus,
                      'recorded_by': _supabase.auth.currentUser!.id,
                    });

                    setState(
                      () => _attendanceState[student['id'].toString()] =
                          selectedStatus,
                    );
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            "${student['first_name']} marked $selectedStatus",
                          ),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Failed to save"),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
                child: const Text(
                  "SAVE",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ===========================================================================
  // 🖼️ UI ONLY — presentation below. Fetching, saving attendance, the QR scan
  // handler and the scan pop-up above are untouched.
  // ===========================================================================
  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = PUi.bg(isDark);
    Color cardColor = PUi.surface(isDark);
    Color primaryColor = Theme.of(context).primaryColor;
    Color textColor = PUi.ink(isDark);

    return Scaffold(
      backgroundColor: bgColor,
      body: PBackdrop(
        accent: primaryColor,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final bool wide = constraints.maxWidth >= 700;
              final double hPad = wide ? 32.0 : 20.0;

              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 860),
                  child: Column(
                    children: [
                      // ─── TOP BAR ───
                      Padding(
                        padding: EdgeInsets.fromLTRB(hPad - 8, 8, hPad, 0),
                        child: Row(
                          children: [
                            IconButton(
                              onPressed: () => Navigator.maybePop(context),
                              style: IconButton.styleFrom(
                                backgroundColor: cardColor,
                                side: BorderSide(color: PUi.border(isDark)),
                                minimumSize: const Size(44, 44),
                              ),
                              icon: Icon(
                                Icons.arrow_back_rounded,
                                color: textColor,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              "Class Roster",
                              style: PUi.title(isDark, size: 24),
                            ),
                          ],
                        ),
                      ),

                      // ─── CLASS FILTER ───
                      Container(
                        margin: EdgeInsets.fromLTRB(hPad, 18, hPad, 0),
                        child: _buildFilterDropdown(
                          "Select Class",
                          _myClasses,
                          _selectedClass,
                          (val) {
                            setState(() {
                              _selectedClass = val;
                              _isLoading = true;
                            });
                            _fetchMyStudentsAndAttendance();
                          },
                          isDark,
                          primaryColor,
                          cardColor,
                        ),
                      ),

                      // ─── PILL TAB BAR ───
                      Container(
                        margin: EdgeInsets.fromLTRB(hPad, 14, hPad, 10),
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: PUi.surfaceAlt(isDark),
                          borderRadius: BorderRadius.circular(40),
                        ),
                        child: TabBar(
                          controller: _tabController,
                          labelColor: Colors.white,
                          unselectedLabelColor: PUi.muted(isDark),
                          indicatorSize: TabBarIndicatorSize.tab,
                          dividerColor: Colors.transparent,
                          splashBorderRadius: BorderRadius.circular(40),
                          indicator: BoxDecoration(
                            color: primaryColor,
                            borderRadius: BorderRadius.circular(40),
                          ),
                          tabs: const [
                            Tab(
                              height: 42,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.list_alt_rounded, size: 18),
                                  SizedBox(width: 8),
                                  Text(
                                    "Manual List",
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Tab(
                              height: 42,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.qr_code_scanner_rounded, size: 18),
                                  SizedBox(width: 8),
                                  Text(
                                    "Scanner",
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      // ─── TABS CONTENT ───
                      Expanded(
                        child: _isLoading
                            ? Center(child: TridetaLoader(color: primaryColor))
                            : TabBarView(
                                controller: _tabController,
                                physics: const NeverScrollableScrollPhysics(),
                                children: [
                                  _buildManualTab(
                                    cardColor,
                                    isDark,
                                    primaryColor,
                                    textColor,
                                    hPad,
                                  ),
                                  _buildScannerTab(primaryColor, isDark, hPad),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildManualTab(
    Color cardColor,
    bool isDark,
    Color primaryColor,
    Color textColor,
    double hPad,
  ) {
    if (_myClasses.isEmpty) {
      return _buildEmptyState(
        "No classes assigned.",
        "You have not been assigned to teach any classes yet.",
        Icons.class_outlined,
        isDark,
      );
    }
    if (_allMyStudents.isEmpty) {
      return _buildEmptyState(
        "No students found.",
        "There are currently no students in this class.",
        Icons.people_outline,
        isDark,
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 14),
          child: Text(
            DateFormat('EEEE, MMMM d, yyyy').format(DateTime.now()),
            style: TextStyle(
              color: PUi.muted(isDark),
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              fontSize: 13,
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.symmetric(horizontal: hPad),
            itemCount: _allMyStudents.length,
            itemBuilder: (context, index) {
              final student = _allMyStudents[index];
              final String sId = student['id'].toString();
              final status = _attendanceState[sId] ?? 'Unmarked';

              String fName = student['first_name']?.toString() ?? "";
              String lName = student['last_name']?.toString() ?? "";
              String initial = fName.isNotEmpty ? fName[0].toUpperCase() : "?";
              String passportUrl = student['passport_url']?.toString() ?? "";

              return Container(
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: PUi.border(isDark)),
                  boxShadow: PUi.softShadow(isDark),
                ),
                child: Theme(
                  data: Theme.of(
                    context,
                  ).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.all(Radius.circular(26)),
                    ),
                    collapsedShape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.all(Radius.circular(26)),
                    ),
                    tilePadding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 8,
                    ),
                    leading: PAvatar(
                      initial: initial,
                      imageUrl: passportUrl,
                      radius: 21,
                      ringColor: primaryColor,
                    ),
                    title: Text(
                      "$lName $fName".trim().toUpperCase(),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5,
                        color: textColor,
                      ),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              student['admission_no']?.toString() ?? "N/A",
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: PUi.muted(isDark),
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          PPill(text: status, color: _getStatusColor(status)),
                        ],
                      ),
                    ),
                    childrenPadding: const EdgeInsets.only(
                      left: 18,
                      right: 18,
                      bottom: 18,
                    ),
                    children: [
                      Divider(height: 1, color: PUi.border(isDark)),
                      const SizedBox(height: 16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: ['Punctual', 'Late', 'Absent', 'Sick']
                                  .map((s) {
                                    final isSelected = status == s;
                                    return ChoiceChip(
                                      label: Text(
                                        s,
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: isSelected
                                              ? FontWeight.w800
                                              : FontWeight.w600,
                                        ),
                                      ),
                                      selected: isSelected,
                                      selectedColor: _getStatusColor(
                                        s,
                                      ).withValues(alpha: 0.15),
                                      backgroundColor: PUi.surfaceAlt(isDark),
                                      labelStyle: TextStyle(
                                        color: isSelected
                                            ? _getStatusColor(s)
                                            : PUi.muted(isDark),
                                      ),
                                      showCheckmark: false,
                                      shape: StadiumBorder(
                                        side: BorderSide(
                                          color: isSelected
                                              ? _getStatusColor(
                                                  s,
                                                ).withValues(alpha: 0.5)
                                              : Colors.transparent,
                                        ),
                                      ),
                                      onSelected: (selected) {
                                        if (selected) {
                                          setState(
                                            () => _attendanceState[sId] = s,
                                          );
                                        }
                                      },
                                    );
                                  })
                                  .toList(),
                            ),
                          ),
                          Container(
                            margin: const EdgeInsets.only(left: 12),
                            decoration: BoxDecoration(
                              color: PUi.tint(primaryColor, isDark, 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: IconButton(
                              icon: Icon(
                                Icons.qr_code_rounded,
                                color: primaryColor,
                                size: 22,
                              ),
                              tooltip: "View ID Card QR",
                              onPressed: () => showStudentQrCode(
                                context,
                                student,
                                primaryColor,
                                isDark,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(hPad, 16, hPad, 20),
          decoration: BoxDecoration(
            color: PUi.surface(isDark),
            border: Border(top: BorderSide(color: PUi.border(isDark))),
          ),
          child: FilledButton(
            style: PUi.filledPill(primaryColor, height: 56).copyWith(
              textStyle: const WidgetStatePropertyAll(
                TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
            ),
            onPressed: _saveManualAttendance,
            child: const Text("Save Batch Attendance"),
          ),
        ),
      ],
    );
  }

  Widget _buildScannerTab(Color primaryColor, bool isDark, double hPad) {
    if (_selectedClass == null) {
      return Center(
        child: Text(
          "Please select a class first.",
          style: TextStyle(color: PUi.muted(isDark)),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(hPad, 4, hPad, 20),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: Stack(
          fit: StackFit.expand,
          children: [
            MobileScanner(controller: _scannerController, onDetect: _onDetect),
            Center(
              child: Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  border: Border.all(color: primaryColor, width: 3),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: primaryColor.withValues(alpha: 0.2),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              bottom: 28,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E).withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.qr_code_scanner, color: Colors.white, size: 20),
                      SizedBox(width: 12),
                      Text(
                        "Scan Student ID Card",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_isProcessingScan)
              Container(
                color: Colors.black.withValues(alpha: 0.6),
                child: Center(child: TridetaLoader(color: primaryColor)),
              ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Punctual':
        return Colors.green;
      case 'Late':
        return Colors.orange;
      case 'Absent':
        return Colors.redAccent;
      case 'Sick':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  Widget _buildFilterDropdown(
    String hint,
    List<String> items,
    String? value,
    Function(String?) onChanged,
    bool isDark,
    Color primaryColor,
    Color cardColor,
  ) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: PUi.border(isDark)),
        boxShadow: PUi.softShadow(isDark),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: value,
          hint: Text(
            hint,
            style: TextStyle(
              color: PUi.muted(isDark),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          icon: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: PUi.tint(primaryColor, isDark, 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.keyboard_arrow_down_rounded,
              color: primaryColor,
              size: 20,
            ),
          ),
          items: items
              .map(
                (e) => DropdownMenuItem(
                  value: e,
                  child: Text(
                    e,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: PUi.ink(isDark),
                    ),
                  ),
                ),
              )
              .toList(),
          onChanged: onChanged,
          dropdownColor: PUi.surface(isDark),
          borderRadius: BorderRadius.circular(20),
        ),
      ),
    );
  }

  Widget _buildEmptyState(
    String title,
    String message,
    IconData icon,
    bool isDark,
  ) {
    final Color accent = Theme.of(context).primaryColor;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PIconBadge(icon: icon, color: accent, size: 96, iconSize: 44),
            const SizedBox(height: 22),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: PUi.ink(isDark),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: PUi.muted(isDark), fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// QR GENERATOR & DOWNLOADER COMPONENT (POLISHED)
// ============================================================================

void showStudentQrCode(
  BuildContext context,
  Map<String, dynamic> student,
  Color primaryColor,
  bool isDark,
) {
  final screenshotController = ScreenshotController();
  final String admNo = student['admission_no'] ?? 'NO_ID';

  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      contentPadding: const EdgeInsets.all(30),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            "ID QR Code",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
          ),
          const SizedBox(height: 8),
          Text(
            admNo,
            style: TextStyle(
              color: Colors.grey[500],
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 30),

          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.grey.shade200, width: 2),
            ),
            child: SizedBox(
              width: 200,
              height: 200,
              child: Screenshot(
                controller: screenshotController,
                child: Container(
                  color: Colors.white,
                  alignment: Alignment.center,
                  child: QrImageView(
                    data: admNo,
                    version: QrVersions.auto,
                    size: 200.0,
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 30),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: primaryColor,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: () async {
                final Uint8List? imageBytes = await screenshotController
                    .capture();
                if (imageBytes != null) {
                  try {
                    if (!await Gal.hasAccess(toAlbum: true)) {
                      await Gal.requestAccess(toAlbum: true);
                    }
                    await Gal.putImageBytes(imageBytes);
                    if (ctx.mounted) {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("QR Code saved to Gallery!"),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } catch (e) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            "Failed to save. Ensure permissions are granted.",
                          ),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                }
              },
              icon: const Icon(
                Icons.download_rounded,
                color: Colors.white,
                size: 20,
              ),
              label: const Text(
                "Save to Gallery",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
