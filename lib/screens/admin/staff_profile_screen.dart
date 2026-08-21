import 'dart:typed_data';
import 'package:trideta_v2/utils/auth_error_handler.dart';
import 'package:trideta_v2/widgets/trideta_loader.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:ui' as ui;
import 'package:pro_image_editor/pro_image_editor.dart';

class StaffProfileScreen extends StatefulWidget {
  final Map<String, dynamic> staffData;

  const StaffProfileScreen({super.key, required this.staffData});

  @override
  State<StaffProfileScreen> createState() => _StaffProfileScreenState();
}

class _StaffProfileScreenState extends State<StaffProfileScreen>
    with AuthErrorHandler {
  final _supabase = Supabase.instance.client;

  bool _isLoading = true;
  String? _schoolId;
  List<Map<String, dynamic>> _myAssignments = [];

  // RELATIONAL STATE DATA
  List<String> _activeClasses = [];
  List<String> _activeSubjects = [];
  final Map<String, List<String>> _subjectToClassMap = {};

  // 🚨 DP EDITOR STATE
  String? _currentImagePath;
  bool _isInteractingWithSystem = false;
  XFile? _pickedFile;
  Uint8List? _webImage;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _currentImagePath = widget.staffData['passport_url'];
    _fetchData();
  }

  // --- DATA FETCHING LOGIC ---
  Future<void> _fetchData() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final profile = await _supabase
          .from('profiles')
          .select('school_id')
          .eq('id', user.id)
          .single();

      final schoolId = profile['school_id'];
      if (schoolId == null) {
        throw StateError('School ID not found for current user.');
      }
      _schoolId = schoolId.toString();

      // 1. Fetch active classes from relational table
      final classesData = await _supabase
          .from('classes')
          .select('name')
          .eq('school_id', _schoolId!)
          .order('list_order', ascending: true);

      // 2. Fetch subjects from relational table
      final subjectsData = await _supabase
          .from('class_subjects')
          .select('class_name, subject_name')
          .eq('school_id', _schoolId!);

      // 3. Fetch the staff's current roles
      final assignmentsData = await _supabase
          .from('staff_assignments')
          .select()
          .eq('staff_id', widget.staffData['id'])
          .order('class_assigned');

      // Process Relational Data
      _activeClasses = classesData.map((c) => c['name'].toString()).toList();

      Set<String> uniqueSubjects = {};
      _subjectToClassMap.clear();

      for (var row in subjectsData) {
        String sName = row['subject_name'].toString();
        String cName = row['class_name'].toString();

        uniqueSubjects.add(sName);

        if (!_subjectToClassMap.containsKey(sName)) {
          _subjectToClassMap[sName] = [];
        }
        if (!_subjectToClassMap[sName]!.contains(cName)) {
          _subjectToClassMap[sName]!.add(cName);
        }
      }

      if (mounted) {
        setState(() {
          _activeSubjects = uniqueSubjects.toList()..sort();
          _myAssignments = List<Map<String, dynamic>>.from(assignmentsData);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Fetch Error: $e");
      if (mounted) {
        setState(() => _isLoading = false);
        showAuthErrorDialog("Failed to load staff data.");
      }
    }
  }

  // --- DP PREVIEW & EDITOR ENGINE ---
  void _showImagePreview(String imageUrl) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          alignment: Alignment.center,
          children: [
            InteractiveViewer(
              child: Image.network(
                imageUrl,
                fit: BoxFit.contain,
                width: double.infinity,
                height: double.infinity,
              ),
            ),
            Positioned(
              top: 40,
              left: 20,
              child: IconButton(
                icon: const Icon(
                  Icons.arrow_back_rounded,
                  color: Colors.white,
                  size: 30,
                ),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
            Positioned(
              bottom: 40,
              child: Column(
                children: [
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white24,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () async {
                      final Uri url = Uri.parse(imageUrl);
                      if (await canLaunchUrl(url)) {
                        await launchUrl(
                          url,
                          mode: LaunchMode.externalApplication,
                        );
                      }
                    },
                    icon: const Icon(Icons.download_rounded),
                    label: const Text("SAVE TO DEVICE"),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await _pickImage();
                      if (_pickedFile != null) {
                        await _saveQuickPhotoChange();
                      }
                    },
                    icon: const Icon(Icons.edit_rounded),
                    label: const Text("CHANGE PHOTO"),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage() async {
    setState(() => _isInteractingWithSystem = true);

    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
        maxWidth: 1000,
        maxHeight: 1000,
      );

      if (image != null) {
        final bytes = await image.readAsBytes();
        if (!mounted) return;

        Uint8List imageToEdit = bytes;

        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) =>
              const Center(child: TridetaLoader(color: Colors.white)),
        );

        try {
          final request = http.MultipartRequest(
            'POST',
            Uri.parse('https://api.remove.bg/v1.0/removebg'),
          );

          request.headers['X-Api-Key'] = 'xDZscf4d861ip44UcfKRuaYN';
          request.files.add(
            http.MultipartFile.fromBytes(
              'image_file',
              bytes,
              filename: 'upload.jpg',
            ),
          );

          final response = await request.send();

          if (response.statusCode == 200) {
            final transparentBytes = await response.stream.toBytes();

            final codec = await ui.instantiateImageCodec(transparentBytes);
            final frame = await codec.getNextFrame();
            final ui.Image aiImage = frame.image;

            final ui.PictureRecorder recorder = ui.PictureRecorder();
            final ui.Canvas canvas = ui.Canvas(recorder);

            final ui.Paint paint = ui.Paint()
              ..color = Theme.of(context).primaryColor;
            final Rect rect = Rect.fromLTWH(
              0,
              0,
              aiImage.width.toDouble(),
              aiImage.height.toDouble(),
            );
            canvas.drawRect(rect, paint);
            canvas.drawImage(aiImage, Offset.zero, ui.Paint());

            final ui.Picture picture = recorder.endRecording();
            final ui.Image mergedImage = await picture.toImage(
              aiImage.width,
              aiImage.height,
            );
            final ByteData? byteData = await mergedImage.toByteData(
              format: ui.ImageByteFormat.png,
            );

            imageToEdit = byteData!.buffer.asUint8List();
          } else {
            debugPrint("Cloud API Failed. Status: ${response.statusCode}");
          }
        } catch (error) {
          debugPrint("Background Removal Skipped (Network Error): $error");
        }

        if (mounted) Navigator.pop(context);

        bool hasPopped = false;

        final Uint8List? editedBytes = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (editorContext) => ProImageEditor.memory(
              imageToEdit,
              callbacks: ProImageEditorCallbacks(
                onImageEditingComplete: (Uint8List result) async {
                  if (!hasPopped) {
                    hasPopped = true;
                    Navigator.pop(editorContext, result);
                  }
                },
                onCloseEditor: (mode) {
                  if (!hasPopped) {
                    hasPopped = true;
                    Navigator.pop(editorContext, null);
                  }
                },
              ),
            ),
          ),
        );

        if (editedBytes != null) {
          if (editedBytes.lengthInBytes > 500 * 1024) {
            if (mounted) setState(() => _isInteractingWithSystem = false);
            showAuthErrorDialog(
              "Image is too large. Please choose a simpler photo.",
            );
            return;
          }
          setState(() {
            _pickedFile = image;
            _webImage = editedBytes;
          });
        }
      }
    } catch (e) {
      debugPrint("Image Picker Error: $e");
    } finally {
      if (mounted) setState(() => _isInteractingWithSystem = false);
    }
  }

  Future<void> _saveQuickPhotoChange() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: TridetaLoader(color: Colors.white)),
    );
    try {
      if (_pickedFile != null && _webImage != null && _schoolId != null) {
        final fileExt = _pickedFile!.name.split('.').last;
        final fileName =
            '$_schoolId/staff_${widget.staffData['id']}_update_${DateTime.now().millisecondsSinceEpoch}.$fileExt';

        await _supabase.storage
            .from('staff_passports') // Using staff bucket
            .uploadBinary(
              fileName,
              _webImage!,
              fileOptions: const FileOptions(upsert: true),
            );
        String newPassportUrl = _supabase.storage
            .from('staff_passports')
            .getPublicUrl(fileName);

        await _supabase
            .from('profiles')
            .update({'passport_url': newPassportUrl})
            .eq('id', widget.staffData['id']);

        if (mounted) {
          setState(() {
            _currentImagePath = newPassportUrl;
          });
          Navigator.pop(context);
          showSuccessDialog(
            "Photo Updated",
            "Staff profile picture has been successfully updated.",
          );
        }
      } else {
        if (mounted) Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        showAuthErrorDialog("Failed to update photo: $e");
      }
    }
  }

  // --- VALIDATION CHECKER ---
  Future<String?> _checkAvailability(
    String className,
    String? subjectName,
  ) async {
    try {
      final user = _supabase.auth.currentUser!;
      final profile = await _supabase
          .from('profiles')
          .select('school_id')
          .eq('id', user.id)
          .single();

      var query = _supabase
          .from('staff_assignments')
          .select('staff_id, profiles!inner(full_name)')
          .eq('school_id', profile['school_id'])
          .eq('class_assigned', className);

      if (subjectName == null) {
        query = query.filter('subject_assigned', 'is', null);
      } else {
        query = query.eq('subject_assigned', subjectName);
      }

      final response = await query.maybeSingle();

      if (response != null && response['profiles'] != null) {
        return response['profiles']['full_name'];
      }
      return null;
    } catch (e) {
      debugPrint("Availability Check Error: $e");
      return null;
    }
  }

  // --- THE UI MODAL ---
  Future<void> _showAddResponsibilityModal() async {
    String roleType = 'class_teacher';
    String? selectedClass;
    String? selectedSubject;
    Map<String, String?> classAvailabilityStatus = {};
    List<String> selectedClassesForSubject = [];
    String? classTeacherError;
    bool isChecking = false;

    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    Color primaryColor = Theme.of(context).primaryColor;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: 600),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            List<String> validClasses = _activeClasses;
            if (roleType == 'subject_teacher' && selectedSubject != null) {
              if (_subjectToClassMap.containsKey(selectedSubject)) {
                validClasses = _subjectToClassMap[selectedSubject]!
                    .where((c) => _activeClasses.contains(c))
                    .toList();
              } else {
                validClasses = [];
              }
            }

            return Container(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                left: 24,
                right: 24,
                top: 20,
              ),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(30),
                ),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      "Assign Role",
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),

                    Row(
                      children: [
                        _buildRoleCard(
                          "Class Teacher",
                          Icons.star_border,
                          roleType == 'class_teacher',
                          isDark,
                          primaryColor,
                          () {
                            setModalState(() {
                              roleType = 'class_teacher';
                              selectedClass = null;
                              classTeacherError = null;
                            });
                          },
                        ),
                        const SizedBox(width: 12),
                        _buildRoleCard(
                          "Subject Teacher",
                          Icons.book_outlined,
                          roleType == 'subject_teacher',
                          isDark,
                          primaryColor,
                          () {
                            setModalState(() {
                              roleType = 'subject_teacher';
                              selectedSubject = null;
                              selectedClassesForSubject.clear();
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    if (roleType == 'class_teacher') ...[
                      Text(
                        "Assign Class",
                        style: TextStyle(
                          color: isDark ? Colors.white54 : Colors.grey[600],
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.05)
                              : Colors.grey[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark
                                ? Colors.white10
                                : Colors.grey.shade300,
                          ),
                        ),
                        child: DropdownButtonFormField<String>(
                          dropdownColor: cardColor,
                          initialValue: selectedClass,
                          hint: const Text("Select Class"),
                          isExpanded: true,
                          items: _activeClasses
                              .map(
                                (c) =>
                                    DropdownMenuItem(value: c, child: Text(c)),
                              )
                              .toList(),
                          onChanged: (val) async {
                            setModalState(() {
                              selectedClass = val;
                              isChecking = true;
                              classTeacherError = null;
                            });
                            final takenBy = await _checkAvailability(
                              val!,
                              null,
                            );
                            setModalState(() {
                              isChecking = false;
                              if (takenBy != null) {
                                classTeacherError = "Taken by $takenBy";
                              }
                            });
                          },
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                          ),
                        ),
                      ),
                      if (isChecking)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: LinearProgressIndicator(minHeight: 2),
                        ),
                      if (classTeacherError != null)
                        Container(
                          margin: const EdgeInsets.only(top: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.warning_amber_rounded,
                                color: Colors.red,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  classTeacherError!,
                                  style: const TextStyle(
                                    color: Colors.red,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],

                    if (roleType == 'subject_teacher') ...[
                      Text(
                        "1. Select Subject",
                        style: TextStyle(
                          color: isDark ? Colors.white54 : Colors.grey[600],
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.05)
                              : Colors.grey[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark
                                ? Colors.white10
                                : Colors.grey.shade300,
                          ),
                        ),
                        child: DropdownButtonFormField<String>(
                          dropdownColor: cardColor,
                          initialValue: selectedSubject,
                          hint: const Text("Choose Subject"),
                          isExpanded: true,
                          items: _activeSubjects
                              .map(
                                (s) =>
                                    DropdownMenuItem(value: s, child: Text(s)),
                              )
                              .toList(),
                          onChanged: (val) {
                            setModalState(() {
                              selectedSubject = val;
                              selectedClassesForSubject.clear();
                              classAvailabilityStatus.clear();
                            });
                          },
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        "2. Target Classes",
                        style: TextStyle(
                          color: isDark ? Colors.white54 : Colors.grey[600],
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: 200,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: isDark
                                ? Colors.white10
                                : Colors.grey.shade300,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.02)
                              : Colors.white,
                        ),
                        child: selectedSubject == null
                            ? Center(
                                child: Text(
                                  "Select a subject first",
                                  style: TextStyle(color: Colors.grey[400]),
                                ),
                              )
                            : validClasses.isEmpty
                            ? Center(
                                child: Text(
                                  "No classes offer this subject",
                                  style: TextStyle(color: Colors.red[300]),
                                ),
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                separatorBuilder: (ctx, i) => Divider(
                                  height: 1,
                                  color: isDark
                                      ? Colors.white10
                                      : Colors.grey[100],
                                ),
                                itemCount: validClasses.length,
                                itemBuilder: (ctx, index) {
                                  final className = validClasses[index];
                                  final errorMsg =
                                      classAvailabilityStatus[className];
                                  final isSelected = selectedClassesForSubject
                                      .contains(className);

                                  return CheckboxListTile(
                                    title: Text(
                                      className,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w500,
                                        color: errorMsg != null
                                            ? Colors.grey
                                            : (isDark
                                                  ? Colors.white
                                                  : Colors.black87),
                                      ),
                                    ),
                                    subtitle: errorMsg != null
                                        ? Text(
                                            errorMsg,
                                            style: const TextStyle(
                                              color: Colors.red,
                                              fontSize: 11,
                                            ),
                                          )
                                        : null,
                                    value: isSelected,
                                    activeColor: primaryColor,
                                    checkboxShape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    onChanged: errorMsg != null && !isSelected
                                        ? null
                                        : (checked) async {
                                            if (checked == true) {
                                              final takenBy =
                                                  await _checkAvailability(
                                                    className,
                                                    selectedSubject,
                                                  );
                                              if (takenBy != null) {
                                                setModalState(
                                                  () =>
                                                      classAvailabilityStatus[className] =
                                                          "Taken by $takenBy",
                                                );
                                              } else {
                                                setModalState(() {
                                                  classAvailabilityStatus
                                                      .remove(className);
                                                  selectedClassesForSubject.add(
                                                    className,
                                                  );
                                                });
                                              }
                                            } else {
                                              setModalState(() {
                                                selectedClassesForSubject
                                                    .remove(className);
                                                classAvailabilityStatus.remove(
                                                  className,
                                                );
                                              });
                                            }
                                          },
                                  );
                                },
                              ),
                      ),
                    ],
                    const SizedBox(height: 30),
                    SizedBox(
                      width: double.infinity,
                      height: 55,
                      child: ElevatedButton(
                        onPressed: (isChecking || classTeacherError != null)
                            ? null
                            : () {
                                if (roleType == 'class_teacher') {
                                  if (selectedClass == null) return;
                                  _saveAssignments([selectedClass!], null);
                                } else {
                                  if (selectedSubject == null ||
                                      selectedClassesForSubject.isEmpty) {
                                    return;
                                  }
                                  _saveAssignments(
                                    selectedClassesForSubject,
                                    selectedSubject,
                                  );
                                }
                                Navigator.pop(context);
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                          elevation: 0,
                        ),
                        child: const Text(
                          "AUTHORIZE ROLE",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: Colors.white,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildRoleCard(
    String title,
    IconData icon,
    bool isSelected,
    bool isDark,
    Color primaryColor,
    VoidCallback onTap,
  ) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: isSelected
                ? primaryColor.withValues(alpha: 0.1)
                : (isDark
                      ? Colors.white.withValues(alpha: 0.02)
                      : Colors.white),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: isSelected
                  ? primaryColor
                  : (isDark ? Colors.white10 : Colors.grey.shade300),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: isSelected ? primaryColor : Colors.grey,
                size: 28,
              ),
              const SizedBox(height: 8),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isSelected
                      ? primaryColor
                      : (isDark ? Colors.white54 : Colors.grey[700]),
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveAssignments(List<String> classes, String? subject) async {
    setState(() => _isLoading = true);
    try {
      final user = _supabase.auth.currentUser!;
      final profile = await _supabase
          .from('profiles')
          .select('school_id')
          .eq('id', user.id)
          .single();

      final List<Map<String, dynamic>> updates = classes.map((className) {
        return {
          'school_id': profile['school_id'],
          'staff_id': widget.staffData['id'],
          'class_assigned': className,
          'subject_assigned': subject,
        };
      }).toList();

      await _supabase.from('staff_assignments').insert(updates);
      if (mounted) {
        _fetchData();
        showSuccessDialog(
          "Role Assigned",
          "The role was successfully assigned to this staff member.",
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        showAuthErrorDialog(
          "Failed to assign role. Please check your network connection.",
        );
      }
    }
  }

  Future<void> _deleteAssignment(String id) async {
    try {
      await _supabase.from('staff_assignments').delete().eq('id', id);
      _fetchData();
    } catch (e) {
      debugPrint("Error deleting: $e");
    }
  }

  // 🚨 UI FIX: Security check added to require typing "CONFIRM"
  Future<void> _deleteStaffProfile() async {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    String confirmText = "";

    bool confirm =
        await showDialog(
          context: context,
          builder: (ctx) => StatefulBuilder(
            builder: (ctx, setS) => AlertDialog(
              backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Row(
                children: [
                  Icon(Icons.person_off_rounded, color: Colors.red),
                  SizedBox(width: 10),
                  Text(
                    "Remove Staff?",
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "Are you sure you want to remove ${widget.staffData['full_name']}? This will revoke their access to the app.",
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    onChanged: (val) => setS(() => confirmText = val),
                    decoration: InputDecoration(
                      labelText: "Type CONFIRM to continue",
                      labelStyle: TextStyle(color: Colors.red.shade300),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Colors.red,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text(
                    "CANCEL",
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: confirmText == "CONFIRM"
                      ? () => Navigator.pop(ctx, true)
                      : null,
                  child: const Text(
                    "CONFIRM",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ) ??
        false;

    if (!confirm) return;

    try {
      setState(() => _isLoading = true);

      await _supabase
          .from('staff_assignments')
          .delete()
          .eq('staff_id', widget.staffData['id']);
      await _supabase
          .from('profiles')
          .delete()
          .eq('id', widget.staffData['id']);

      if (mounted) {
        showSuccessDialog(
          "Staff Removed",
          "The staff member has been completely removed from the system.",
          onOkay: () {
            Navigator.pop(context, true);
          },
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      showAuthErrorDialog(
        "Failed to remove staff member. They might have active dependencies.",
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color primaryColor = Theme.of(context).primaryColor;

    // 🚨 UI FIX: Pure Material Matte Backgrounds globally applied
    Color bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC);
    Color textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);

    final staff = widget.staffData;
    final String fullName = staff['full_name'] ?? "Staff Member";
    final String rawRole = staff['role']?.toString().toLowerCase() ?? 'staff';
    final String displayRole = staff['designation'] ?? rawRole.toUpperCase();
    final String id = staff['id'].toString();
    final String staffEmail = staff['email'] ?? 'No email available';

    final bool isBursar = rawRole == 'bursar' || rawRole == 'finance';
    Color roleBadgeColor = (isBursar) ? Colors.green : primaryColor;

    Widget mainContent = SingleChildScrollView(
      child: Column(
        children: [
          // 🚨 HEADER: Restored Student Profile look (Big centered avatar with border ring)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.only(top: 30, bottom: 30),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Hero(
                  tag: 'staff_avatar_$id',
                  child: GestureDetector(
                    onTap: () {
                      if (_currentImagePath != null &&
                          _currentImagePath!.startsWith('http')) {
                        _showImagePreview(_currentImagePath!);
                      } else {
                        _pickImage().then((_) {
                          if (_pickedFile != null) _saveQuickPhotoChange();
                        });
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: roleBadgeColor.withValues(alpha: 0.3),
                          width: 2,
                        ),
                      ),
                      child: CircleAvatar(
                        radius: 65,
                        backgroundColor: roleBadgeColor.withValues(alpha: 0.1),
                        backgroundImage:
                            _currentImagePath != null &&
                                _currentImagePath!.startsWith('http')
                            ? NetworkImage(_currentImagePath!)
                            : null,
                        child:
                            _currentImagePath == null ||
                                !_currentImagePath!.startsWith('http')
                            ? Center(
                                child: Text(
                                  fullName.isNotEmpty
                                      ? fullName[0].toUpperCase()
                                      : "?",
                                  style: TextStyle(
                                    fontSize: 40,
                                    fontWeight: FontWeight.bold,
                                    color: roleBadgeColor,
                                  ),
                                ),
                              )
                            : null,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  fullName,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                    color: textColor,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  displayRole,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  staffEmail,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                ),
                const SizedBox(height: 12),
                Text(
                  "Tap photo to preview or change",
                  style: TextStyle(
                    fontSize: 11,
                    color: primaryColor,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          if (isBursar) ...[
            ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 12,
              ),
              leading: const Icon(
                Icons.account_balance_wallet_rounded,
                size: 28,
                color: Colors.green,
              ),
              title: Text(
                "Financial Access",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: textColor,
                ),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  "This staff member has full access to the Finance Centre to record payments and manage fee structures.",
                  style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.grey[600],
                    fontSize: 13,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ] else ...[
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(24, 24, 24, 8),
                  child: Text(
                    "ACTIVE ROLES",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: Colors.grey,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),

                // 🚨 RESTORED: Assign New Role perfectly formatted as a native WhatsApp row
                InkWell(
                  onTap: _showAddResponsibilityModal,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 8,
                    ),
                    leading: CircleAvatar(
                      radius: 20,
                      backgroundColor: primaryColor.withValues(alpha: 0.1),
                      child: Icon(Icons.add_rounded, color: primaryColor),
                    ),
                    title: Text(
                      "Assign New Role",
                      style: TextStyle(
                        color: primaryColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 80, right: 24),
                  child: Divider(
                    height: 1,
                    color: isDark ? Colors.white10 : Colors.grey.shade200,
                  ),
                ),

                if (_isLoading)
                  const Padding(
                    padding: EdgeInsets.all(30),
                    child: TridetaLoader(),
                  )
                else if (_myAssignments.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(40),
                    child: Center(
                      child: Text(
                        "No classes or subjects assigned.",
                        style: TextStyle(
                          color: isDark ? Colors.white38 : Colors.grey[400],
                        ),
                      ),
                    ),
                  )
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: EdgeInsets.zero,
                    itemCount: _myAssignments.length,
                    itemBuilder: (context, index) {
                      final item = _myAssignments[index];
                      final isClassTeacher = item['subject_assigned'] == null;

                      return Column(
                        children: [
                          ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 4,
                            ),
                            leading: CircleAvatar(
                              radius: 20,
                              backgroundColor: isClassTeacher
                                  ? Colors.orange.withValues(alpha: 0.1)
                                  : primaryColor.withValues(alpha: 0.1),
                              child: Icon(
                                isClassTeacher
                                    ? Icons.star_rounded
                                    : Icons.menu_book_rounded,
                                color: isClassTeacher
                                    ? Colors.orange
                                    : primaryColor,
                                size: 18,
                              ),
                            ),
                            title: Text(
                              item['class_assigned'],
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: textColor,
                              ),
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                isClassTeacher
                                    ? "Form Master"
                                    : "${item['subject_assigned']} Teacher",
                                style: TextStyle(
                                  color: isClassTeacher
                                      ? Colors.orange[700]
                                      : Colors.grey[500],
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            trailing: IconButton(
                              icon: const Icon(
                                Icons.remove_circle_outline_rounded,
                                color: Colors.red,
                              ),
                              onPressed: () => _deleteAssignment(item['id']),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(left: 80, right: 24),
                            child: Divider(
                              height: 1,
                              color: isDark
                                  ? Colors.white10
                                  : Colors.grey.shade200,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                const SizedBox(height: 24),
              ],
            ),
          ],

          // 🚨 RESTORED: Remove Staff Member perfectly placed at the bottom
          InkWell(
            onTap: _deleteStaffProfile,
            child: const ListTile(
              contentPadding: EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 12,
              ),
              leading: Icon(
                Icons.delete_outline_rounded,
                color: Colors.red,
                size: 28,
              ),
              title: Text(
                "Remove Staff Member",
                style: TextStyle(
                  color: Colors.red,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        foregroundColor: textColor,
        title: const Text(
          "Staff Profile",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
      ),
      // 🚨 SHAPE-SHIFTER: LayoutBuilder
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth > 800) {
            // 💻 DESKTOP LAYOUT (Constrained Center Column)
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Container(
                  decoration: BoxDecoration(
                    color: bgColor,
                    border: Border(
                      left: BorderSide(
                        color: isDark ? Colors.white10 : Colors.grey.shade200,
                        width: 1,
                      ),
                      right: BorderSide(
                        color: isDark ? Colors.white10 : Colors.grey.shade200,
                        width: 1,
                      ),
                    ),
                  ),
                  child: mainContent,
                ),
              ),
            );
          } else {
            // 📱 MOBILE LAYOUT
            return mainContent;
          }
        },
      ),
    );
  }
}
