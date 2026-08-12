import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:trideta_v2/widgets/trideta_loader.dart';
import 'package:screenshot/screenshot.dart';
import 'package:intl/intl.dart';
import 'package:gal/gal.dart';

class AttendanceScreen extends StatefulWidget {
  final List<String> accessibleClasses;
  final String schoolId;

  const AttendanceScreen({
    super.key,
    required this.accessibleClasses,
    required this.schoolId,
  });

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen>
    with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  final Color _tridetaBlue = const Color(0xFF007ACC);

  late TabController _tabController;
  bool _isLoading = false;

  String? _selectedClass;
  List<Map<String, dynamic>> _students = [];

  Map<String, String> _attendanceState = {};

  final MobileScannerController _scannerController = MobileScannerController();
  bool _isProcessingScan = false;

  // 🚨 NEW: Calendar Tracking
  String _currentSession = "";
  String _currentTerm = "";
  List<String> _customOffDays = ['Saturday', 'Sunday']; // Default

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchSchoolCalendar();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  // 🚨 NEW: Fetch Custom Weekends and Active Term
  Future<void> _fetchSchoolCalendar() async {
    setState(() => _isLoading = true);
    try {
      final schoolData = await _supabase
          .from('schools')
          .select('current_session, current_term, off_days')
          .eq('id', widget.schoolId)
          .single();

      setState(() {
        _currentSession = schoolData['current_session'] ?? '';
        _currentTerm = schoolData['current_term'] ?? '';
        if (schoolData['off_days'] != null) {
          _customOffDays = List<String>.from(schoolData['off_days']);
        }
      });

      if (widget.accessibleClasses.isNotEmpty) {
        final validClasses = widget.accessibleClasses
            .where((c) => c != 'All My Classes')
            .toList();
        if (validClasses.isNotEmpty) {
          _selectedClass = validClasses.first;
          _fetchStudentsAndTodayAttendance();
        }
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      debugPrint("Calendar Fetch Error: $e");
    }
  }

  // 🚨 NEW: Custom Weekend & Nigerian Public Holiday Engine
  bool _isOffDayOrHoliday() {
    DateTime today = DateTime.now();
    String weekdayName = DateFormat('EEEE').format(today); // e.g., 'Friday'

    // 1. Check Custom School Weekends (e.g., Thu/Fri for Islamic Schools)
    if (_customOffDays.contains(weekdayName)) return true;

    // 2. Check Fixed Nigerian Public Holidays
    if (today.month == 1 && today.day == 1) return true; // New Year's Day
    if (today.month == 5 && today.day == 1) return true; // Workers' Day
    if (today.month == 6 && today.day == 12) return true; // Democracy Day
    if (today.month == 10 && today.day == 1) return true; // Independence Day
    if (today.month == 12 && today.day == 25) return true; // Christmas Day
    if (today.month == 12 && today.day == 26) return true; // Boxing Day

    return false;
  }

  Future<void> _fetchStudentsAndTodayAttendance() async {
    if (_selectedClass == null) return;
    setState(() => _isLoading = true);

    try {
      final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());

      final studentsRes = await _supabase
          .from('students')
          .select('id, first_name, last_name, admission_no, passport_url')
          .eq('school_id', widget.schoolId)
          .eq('class_level', _selectedClass!)
          .timeout(const Duration(seconds: 15));

      final attendanceRes = await _supabase
          .from('attendance')
          .select('student_id, status')
          .eq('class_level', _selectedClass!)
          .eq('date', todayStr)
          // 🚨 NOW FILTERED BY SESSION AND TERM
          .eq('academic_session', _currentSession)
          .eq('term', _currentTerm)
          .timeout(const Duration(seconds: 15));

      Map<String, String> existingData = {};
      for (var record in attendanceRes) {
        existingData[record['student_id'].toString()] = record['status']
            .toString();
      }

      if (mounted) {
        setState(() {
          _students = List<Map<String, dynamic>>.from(studentsRes);
          _attendanceState = existingData;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Network Timeout: Please check your connection."),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _saveManualAttendance() async {
    if (_attendanceState.isEmpty) return;

    if (_isOffDayOrHoliday()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Attendance cannot be recorded on Off-Days or Public Holidays.",
          ),
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
          'school_id': widget.schoolId,
          'student_id': studentId,
          'class_level': _selectedClass,
          'date': todayStr,
          'academic_session': _currentSession, // 🚨 WRITTEN TO DB
          'term': _currentTerm, // 🚨 WRITTEN TO DB
          'status': status,
          'recorded_by': user.id,
        });
      });

      await _supabase
          .from('attendance')
          .upsert(upsertData, onConflict: 'student_id, date')
          .timeout(const Duration(seconds: 15));

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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Failed to save. Ensure your internet is stable."),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _onDetect(BarcodeCapture capture) async {
    if (_isProcessingScan) return;

    if (_isOffDayOrHoliday()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Attendance cannot be recorded on Off-Days or Holidays.",
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty || barcodes.first.rawValue == null) return;

    final String scannedAdmNo = barcodes.first.rawValue!;
    setState(() => _isProcessingScan = true);
    _scannerController.stop();

    try {
      final student = _students.firstWhere(
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

    if (_attendanceState.containsKey(student['id'])) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Already Marked"),
          content: Text(
            "${student['first_name']} was already marked '${_attendanceState[student['id']]}' today.",
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
    bool isSavingPopup = false;

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
                  activeColor: _tridetaBlue,
                  onChanged: isSavingPopup
                      ? null
                      : (val) => setDialogState(() => selectedStatus = val!),
                );
              }).toList(),
            ),
            actions: [
              if (!isSavingPopup)
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("Cancel"),
                ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: _tridetaBlue),
                onPressed: isSavingPopup
                    ? null
                    : () async {
                        setDialogState(() => isSavingPopup = true);
                        try {
                          await _supabase
                              .from('attendance')
                              .upsert({
                                'school_id': widget.schoolId,
                                'student_id': student['id'],
                                'class_level': _selectedClass,
                                'date': todayStr,
                                'academic_session':
                                    _currentSession, // 🚨 WRITTEN TO DB
                                'term': _currentTerm, // 🚨 WRITTEN TO DB
                                'status': selectedStatus,
                                'recorded_by': _supabase.auth.currentUser!.id,
                              }, onConflict: 'student_id, date')
                              .timeout(const Duration(seconds: 10));

                          setState(
                            () => _attendanceState[student['id']] =
                                selectedStatus,
                          );
                          if (mounted) {
                            Navigator.pop(ctx);
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
                          setDialogState(() => isSavingPopup = false);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text("Network Error. Tap Save again."),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      },
                child: isSavingPopup
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text("SAVE", style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final validClasses = widget.accessibleClasses
        .where((c) => c != 'All My Classes')
        .toList();

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text(
          "Daily Attendance",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: _tridetaBlue,
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(icon: Icon(Icons.list_alt), text: "Manual List"),
            Tab(icon: Icon(Icons.qr_code_scanner), text: "QR Scanner"),
          ],
        ),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: Colors.white,
            child: Row(
              children: [
                const Icon(Icons.class_, color: Colors.grey),
                const SizedBox(width: 15),
                Expanded(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedClass,
                      isExpanded: true,
                      hint: const Text("Select Class to Mark"),
                      items: validClasses
                          .map(
                            (c) => DropdownMenuItem(
                              value: c,
                              child: Text(
                                c,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (val) {
                        setState(() => _selectedClass = val);
                        _fetchStudentsAndTodayAttendance();
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              physics: const NeverScrollableScrollPhysics(),
              children: [_buildManualTab(), _buildScannerTab()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildManualTab() {
    if (_isLoading) return const Center(child: TridetaLoader());
    if (_selectedClass == null) {
      return const Center(child: Text("Please select a class."));
    }
    if (_students.isEmpty) {
      return const Center(child: Text("No students found in this class."));
    }

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          color: Colors.blue[50],
          child: Text(
            "Date: ${DateFormat('EEEE, MMM d, yyyy').format(DateTime.now())}",
            textAlign: TextAlign.center,
            style: TextStyle(color: _tridetaBlue, fontWeight: FontWeight.bold),
          ),
        ),

        if (_isOffDayOrHoliday())
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            color: Colors.orange.shade100,
            child: const Text(
              "Attendance recording is disabled on Off-Days and Holidays.",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.orange,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(10),
            itemCount: _students.length,
            itemBuilder: (context, index) {
              final student = _students[index];
              final status = _attendanceState[student['id']] ?? 'Unmarked';

              return Card(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.shade300),
                ),
                child: ExpansionTile(
                  leading: CircleAvatar(
                    backgroundImage: student['passport_url'] != null
                        ? NetworkImage(student['passport_url'])
                        : null,
                    child: student['passport_url'] == null
                        ? const Icon(Icons.person)
                        : null,
                  ),
                  title: Text(
                    "${student['first_name']} ${student['last_name']}",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    status,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _getStatusColor(status),
                    ),
                  ),
                  childrenPadding: const EdgeInsets.all(10),
                  children: [
                    TextButton.icon(
                      onPressed: () => showStudentQrCode(context, student),
                      icon: const Icon(Icons.qr_code, size: 18),
                      label: const Text("View ID QR Code"),
                    ),
                    const Divider(),
                    Wrap(
                      spacing: 10,
                      children: ['Punctual', 'Late', 'Absent', 'Sick'].map((s) {
                        final isSelected = status == s;
                        return ChoiceChip(
                          label: Text(s),
                          selected: isSelected,
                          selectedColor: _getStatusColor(
                            s,
                          ).withValues(alpha: 0.2),
                          labelStyle: TextStyle(
                            color: isSelected
                                ? _getStatusColor(s)
                                : Colors.black,
                          ),
                          onSelected: (selected) {
                            if (selected && !_isOffDayOrHoliday()) {
                              setState(
                                () => _attendanceState[student['id']] = s,
                              );
                            }
                          },
                        );
                      }).toList(),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.white,
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _isOffDayOrHoliday()
                  ? Colors.grey
                  : _tridetaBlue,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: _isOffDayOrHoliday() ? null : _saveManualAttendance,
            child: const Text(
              "SAVE BATCH ATTENDANCE",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildScannerTab() {
    if (_selectedClass == null) {
      return const Center(child: Text("Please select a class first."));
    }

    return Stack(
      children: [
        MobileScanner(controller: _scannerController, onDetect: _onDetect),
        Positioned(
          bottom: 40,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _isOffDayOrHoliday()
                    ? "Scanner disabled on Off-Days"
                    : "Scan Student QR on ID Card",
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ),
        ),
        if (_isProcessingScan)
          Container(
            color: Colors.black54,
            child: const Center(child: TridetaLoader(color: Colors.white)),
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
}

// ============================================================================
// QR GENERATOR
// ============================================================================
void showStudentQrCode(BuildContext context, Map<String, dynamic> student) {
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
          Text(admNo, style: TextStyle(color: Colors.grey[600])),
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
                backgroundColor: const Color(0xFF007ACC),
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
              icon: const Icon(Icons.download, color: Colors.white),
              label: const Text(
                "Download for ID Card",
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
