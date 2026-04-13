import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:screenshot/screenshot.dart';
import 'package:intl/intl.dart';

// 🚨 NEW: The modern gallery saver package
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    if (widget.accessibleClasses.isNotEmpty) {
      final validClasses = widget.accessibleClasses
          .where((c) => c != 'All My Classes')
          .toList();
      if (validClasses.isNotEmpty) {
        _selectedClass = validClasses.first;
        _fetchStudentsAndTodayAttendance();
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scannerController.dispose();
    super.dispose();
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
          .eq('class_level', _selectedClass!);

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
          _students = List<Map<String, dynamic>>.from(studentsRes);
          _attendanceState = existingData;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
    }
  }

  Future<void> _saveManualAttendance() async {
    if (_attendanceState.isEmpty) return;
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
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Save Error: $e"),
            backgroundColor: Colors.red,
          ),
        );
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
      final student = _students.firstWhere(
        (s) => s['admission_no'] == scannedAdmNo,
      );
      await _showScannerActionPopup(student);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Admission No. $scannedAdmNo not found in $_selectedClass",
            ),
            backgroundColor: Colors.orange,
          ),
        );
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
                style: ElevatedButton.styleFrom(backgroundColor: _tridetaBlue),
                onPressed: () async {
                  Navigator.pop(ctx);
                  try {
                    await _supabase.from('attendance').insert({
                      'school_id': widget.schoolId,
                      'student_id': student['id'],
                      'class_level': _selectedClass,
                      'date': todayStr,
                      'status': selectedStatus,
                      'recorded_by': _supabase.auth.currentUser!.id,
                    });

                    setState(
                      () => _attendanceState[student['id']] = selectedStatus,
                    );
                    if (mounted)
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            "${student['first_name']} marked $selectedStatus",
                          ),
                          backgroundColor: Colors.green,
                        ),
                      );
                  } catch (e) {
                    if (mounted)
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Failed to save"),
                          backgroundColor: Colors.red,
                        ),
                      );
                  }
                },
                child: const Text(
                  "SAVE",
                  style: TextStyle(color: Colors.white),
                ),
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
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_selectedClass == null)
      return const Center(child: Text("Please select a class."));
    if (_students.isEmpty)
      return const Center(child: Text("No students found in this class."));

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
                          selectedColor: _getStatusColor(s).withOpacity(0.2),
                          labelStyle: TextStyle(
                            color: isSelected
                                ? _getStatusColor(s)
                                : Colors.black,
                          ),
                          onSelected: (selected) {
                            if (selected)
                              setState(
                                () => _attendanceState[student['id']] = s,
                              );
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
              backgroundColor: _tridetaBlue,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: _saveManualAttendance,
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
    if (_selectedClass == null)
      return const Center(child: Text("Please select a class first."));

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
              child: const Text(
                "Scan Student QR on ID Card",
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ),
        ),
        if (_isProcessingScan)
          Container(
            color: Colors.black54,
            child: const Center(
              child: CircularProgressIndicator(color: Colors.white),
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
}

// ============================================================================
// QR GENERATOR & DOWNLOADER COMPONENT
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

          // FIX: Fixed size prevents the 'No size' render box error
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

              // 🚨 NEW: Simple, modern Gal saving logic
              onPressed: () async {
                final Uint8List? imageBytes = await screenshotController
                    .capture();
                if (imageBytes != null) {
                  try {
                    // Check and request permissions automatically
                    if (!await Gal.hasAccess(toAlbum: true)) {
                      await Gal.requestAccess(toAlbum: true);
                    }

                    // Save the image directly to the gallery
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
