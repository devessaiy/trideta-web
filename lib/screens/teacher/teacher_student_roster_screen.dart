import 'package:trideta_v2/utils/auth_error_handler.dart';
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

      // Find allowed classes
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
        // Fetch Students for selected class
        final studentsRes = await _supabase
            .from('students')
            .select(
              'id, first_name, last_name, admission_no, class_level, gender, passport_url',
            )
            .eq('school_id', _schoolId!)
            .eq('class_level', _selectedClass!)
            .order('first_name', ascending: true);

        // Fetch Today's Attendance for selected class
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

  Future<void> _showScannerActionPopup(Map<String, dynamic> student) async {
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    Color primaryColor = Theme.of(context).primaryColor;

    if (_attendanceState.containsKey(student['id'].toString())) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Already Marked"),
          content: Text(
            "${student['first_name']} was already marked '${_attendanceState[student['id'].toString()]}' today.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("OK"),
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
            title: Text("${student['first_name']} ${student['last_name']}"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: ['Punctual', 'Late', 'Absent', 'Sick'].map((status) {
                return RadioListTile<String>(
                  title: Text(status),
                  value: status,
                  groupValue: selectedStatus,
                  activeColor: primaryColor,
                  onChanged: (val) =>
                      setDialogState(() => selectedStatus = val!),
                );
              }).toList(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Cancel"),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
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
                child: const Text("SAVE"),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC);
    Color cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    Color primaryColor = Theme.of(context).primaryColor;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text(
          "My Students & Attendance",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          tabs: const [
            Tab(icon: Icon(Icons.list_alt_rounded), text: "Manual List"),
            Tab(icon: Icon(Icons.qr_code_scanner_rounded), text: "QR Scanner"),
          ],
        ),
      ),
      body: Column(
        children: [
          // CLASS FILTER
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
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
            ),
          ),

          // TABS CONTENT
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator(color: primaryColor))
                : TabBarView(
                    controller: _tabController,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      _buildManualTab(cardColor, isDark, primaryColor),
                      _buildScannerTab(primaryColor),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildManualTab(Color cardColor, bool isDark, Color primaryColor) {
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
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12),
          color: isDark
              ? primaryColor.withOpacity(0.1)
              : primaryColor.withOpacity(0.05),
          child: Text(
            "Date: ${DateFormat('EEEE, MMM d, yyyy').format(DateTime.now())}",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: primaryColor,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _allMyStudents.length,
            itemBuilder: (context, index) {
              final student = _allMyStudents[index];
              final String sId = student['id'].toString();
              final status = _attendanceState[sId] ?? 'Unmarked';

              String fName = student['first_name']?.toString() ?? "";
              String lName = student['last_name']?.toString() ?? "";
              String initial = fName.isNotEmpty ? fName[0].toUpperCase() : "?";
              String passportUrl = student['passport_url']?.toString() ?? "";

              return Card(
                elevation: 0,
                color: cardColor,
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                  side: BorderSide(
                    color: isDark ? Colors.white10 : Colors.grey.shade300,
                  ),
                ),
                child: Theme(
                  data: Theme.of(context).copyWith(
                    dividerColor: Colors.transparent,
                  ), // Removes line inside ExpansionTile
                  child: ExpansionTile(
                    tilePadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    leading: CircleAvatar(
                      backgroundColor: primaryColor.withOpacity(0.1),
                      backgroundImage: passportUrl.isNotEmpty
                          ? NetworkImage(passportUrl)
                          : null,
                      child: passportUrl.isEmpty
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
                      "$lName $fName".trim().toUpperCase(),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          Text(
                            student['admission_no']?.toString() ?? "N/A",
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _getStatusColor(status).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              status,
                              style: TextStyle(
                                color: _getStatusColor(status),
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    childrenPadding: const EdgeInsets.only(
                      left: 16,
                      right: 16,
                      bottom: 16,
                    ),
                    children: [
                      const Divider(height: 1),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                                          fontSize: 12,
                                          fontWeight: isSelected
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                        ),
                                      ),
                                      selected: isSelected,
                                      selectedColor: _getStatusColor(
                                        s,
                                      ).withOpacity(0.2),
                                      backgroundColor: isDark
                                          ? Colors.white10
                                          : Colors.grey[100],
                                      labelStyle: TextStyle(
                                        color: isSelected
                                            ? _getStatusColor(s)
                                            : (isDark
                                                  ? Colors.white70
                                                  : Colors.black87),
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        side: const BorderSide(
                                          color: Colors.transparent,
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
                          IconButton(
                            icon: Icon(
                              Icons.qr_code_rounded,
                              color: primaryColor,
                            ),
                            tooltip: "View ID Card QR",
                            onPressed: () => showStudentQrCode(
                              context,
                              student,
                              primaryColor,
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
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: cardColor,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            onPressed: _saveManualAttendance,
            child: const Text(
              "SAVE BATCH ATTENDANCE",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                letterSpacing: 1,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildScannerTab(Color primaryColor) {
    if (_selectedClass == null) {
      return const Center(child: Text("Please select a class first."));
    }

    return Stack(
      children: [
        MobileScanner(controller: _scannerController, onDetect: _onDetect),
        // Scanner Overlay Guide
        Center(
          child: Container(
            width: 250,
            height: 250,
            decoration: BoxDecoration(
              border: Border.all(color: primaryColor, width: 3),
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),
        Positioned(
          bottom: 40,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(30),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.qr_code_scanner, color: Colors.white, size: 20),
                  SizedBox(width: 10),
                  Text(
                    "Scan Student QR Code",
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
            color: Colors.black54,
            child: Center(
              child: CircularProgressIndicator(color: primaryColor),
            ),
          ),
      ],
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Punctual':
        return Colors.green;
      case 'Late':
        return Colors.orange;
      case 'Absent':
        return Colors.red;
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
  ) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade300,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: value,
          hint: Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Text(
              hint,
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ),
          icon: Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Icon(Icons.class_rounded, color: primaryColor),
          ),
          items: items
              .map(
                (e) => DropdownMenuItem(
                  value: e,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Text(
                      e,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
          onChanged: onChanged,
          dropdownColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
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
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 80,
            color: isDark ? Colors.white10 : Colors.grey[300],
          ),
          const SizedBox(height: 15),
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[500], fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// QR GENERATOR & DOWNLOADER COMPONENT
// ============================================================================

void showStudentQrCode(
  BuildContext context,
  Map<String, dynamic> student,
  Color primaryColor,
) {
  final screenshotController = ScreenshotController();
  final String admNo = student['admission_no'] ?? 'NO_ID';

  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            "Student ID QR Code",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          const SizedBox(height: 5),
          Text(
            admNo,
            style: TextStyle(
              color: Colors.grey[600],
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),

          SizedBox(
            width: 220,
            height: 220,
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

          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
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
              icon: const Icon(Icons.download, color: Colors.white, size: 18),
              label: const Text(
                "Save to Gallery",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
