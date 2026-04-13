import 'package:trideta_v2/utils/auth_error_handler.dart';
import 'package:flutter/foundation.dart'; // Required for kIsWeb
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import '../../main.dart';
import '../../dashboard.dart';

class SetupWizardScreen extends StatefulWidget {
  const SetupWizardScreen({super.key});

  @override
  State<SetupWizardScreen> createState() => _SetupWizardScreenState();
}

class _SetupWizardScreenState extends State<SetupWizardScreen>
    with AuthErrorHandler {
  final _supabase = Supabase.instance.client;

  int _currentStep = 1;
  final int _totalSteps = 4;
  bool _isLoading = false;
  bool _isChecking = true;
  String? _schoolId;

  // --- STEP 1: TIMELINE ---
  String _selectedSession = "2025/2026";
  String _selectedTerm = "1st Term";

  // --- STEP 2: CLASSES (Relational State) ---
  final List<Map<String, dynamic>> _classes = [];
  final _classController = TextEditingController();

  // --- STEP 3: SUBJECTS (Relational State) ---
  final List<Map<String, dynamic>> _classSubjects = [];
  final _subjectController = TextEditingController();
  String? _selectedClassForSubject;
  String _subjectType = 'Compulsory';

  // --- STEP 4: PROFILE (SLIMMED) ---
  XFile? _pickedFile;
  Uint8List? _webImage; // Display bytes for Chrome compatibility
  final _addressController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchSchoolId();
  }

  Future<void> _fetchSchoolId() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user != null) {
        final profile = await _supabase
            .from('profiles')
            .select('school_id')
            .eq('id', user.id)
            .single();
        _schoolId = profile['school_id'];

        final school = await _supabase
            .from('schools')
            .select('current_session, current_term')
            .eq('id', _schoolId!)
            .single();

        // If the school already has a session and term, they finished setup!
        if (school['current_session'] != null &&
            school['current_term'] != null) {
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => const DashboardScreen(userRole: "Admin"),
              ),
            );
          }
        } else {
          if (mounted) setState(() => _isChecking = false);
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  Future<void> _pickImage() async {
    setState(() => isInteractingWithSystem = true);

    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );

    setState(() => isInteractingWithSystem = false);

    if (image != null) {
      final bytes = await image.readAsBytes();
      setState(() {
        _pickedFile = image;
        _webImage = bytes;
      });
    }
  }

  // --- 🚨 FIXED: RELATIONAL SAVE ENGINE ---
  Future<void> _finishSetup() async {
    setState(() => _isLoading = true);
    const bucketName = 'school_logos';

    try {
      String? logoUrl;

      // 1. Upload Logo if selected
      if (_pickedFile != null && _webImage != null) {
        final fileExt = _pickedFile!.name.split('.').last;
        final fileName =
            'logo_${_schoolId}_${DateTime.now().millisecondsSinceEpoch}.$fileExt';
        final path = 'logos/$fileName';

        try {
          await _supabase.storage
              .from(bucketName)
              .uploadBinary(
                path,
                _webImage!,
                fileOptions: FileOptions(contentType: 'image/$fileExt'),
              );
          logoUrl = _supabase.storage.from(bucketName).getPublicUrl(path);
        } catch (storageError) {
          if (storageError.toString().contains("bucket not found")) {
            throw "We couldn't find the cloud folder '$bucketName'. Please ensure it's created and public in your Supabase dashboard.";
          }
          rethrow;
        }
      }

      // 2. Update Basic School Info
      await _supabase
          .from('schools')
          .update({
            'current_session': _selectedSession,
            'current_term': _selectedTerm,
            'address': _addressController.text.trim().isNotEmpty
                ? _addressController.text.trim()
                : null,
            'logo_url': logoUrl,
            'setup_completed': true,
          })
          .eq('id', _schoolId!);

      // 3. Save Classes to Relational Table
      List<Map<String, dynamic>> classesToInsert = [];
      for (int i = 0; i < _classes.length; i++) {
        classesToInsert.add({
          'school_id': _schoolId,
          'name': _classes[i]['name'],
          'list_order': i,
        });
      }
      if (classesToInsert.isNotEmpty) {
        await _supabase.from('classes').upsert(classesToInsert);
      }

      // 4. Save Subjects to Relational Table
      List<Map<String, dynamic>> subjectsToInsert = [];
      for (var s in _classSubjects) {
        subjectsToInsert.add({
          'school_id': _schoolId,
          'class_name': s['class_name'],
          'subject_name': s['subject_name'],
          'type': s['type'],
        });
      }
      if (subjectsToInsert.isNotEmpty) {
        await _supabase.from('class_subjects').upsert(subjectsToInsert);
      }

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => const DashboardScreen(userRole: "Admin"),
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);

      String displayError = "Setup failed. Please try again.";
      if (e.toString().contains("cloud folder")) displayError = e.toString();
      if (e.toString().contains("network")) {
        displayError = "Connection error. Please check your internet.";
      }

      showAuthErrorDialog(displayError);
    }
  }

  void _showDuplicateAlert(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.info, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.orange.shade800,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
    );
  }

  // --- UPDATED CLASS LOGIC (RELATIONAL MAPS) ---
  void _addClass() {
    final clsName = _classController.text.trim().toUpperCase();
    if (clsName.isEmpty) return;

    if (_classes.any((c) => c['name'].toString().toUpperCase() == clsName)) {
      _showDuplicateAlert("'$clsName' is already added.");
      return;
    }

    setState(() {
      _classes.add({'name': clsName, 'list_order': _classes.length});
      _selectedClassForSubject ??= clsName;
      _classController.clear();
    });
  }

  void _removeClass(Map<String, dynamic> cls) {
    setState(() {
      _classes.remove(cls);

      // Cascade Remove subjects for this class
      _classSubjects.removeWhere((s) => s['class_name'] == cls['name']);

      if (_selectedClassForSubject == cls['name']) {
        _selectedClassForSubject = _classes.isNotEmpty
            ? _classes.first['name']
            : null;
      }
    });
  }

  // --- UPDATED SUBJECT LOGIC (RELATIONAL MAPS) ---
  void _addSubject() {
    final subName = _subjectController.text.trim().toUpperCase();
    if (subName.isEmpty || _selectedClassForSubject == null) return;

    bool exists = _classSubjects.any(
      (s) =>
          s['class_name'] == _selectedClassForSubject &&
          s['subject_name'].toString().toUpperCase() == subName,
    );

    if (exists) {
      _showDuplicateAlert(
        "'$subName' is already a $_subjectType subject here.",
      );
      return;
    }

    setState(() {
      _classSubjects.add({
        'subject_name': subName,
        'type': _subjectType,
        'class_name': _selectedClassForSubject,
      });
      _subjectController.clear();
    });
  }

  void _removeSubject(Map<String, dynamic> subject) {
    setState(() {
      _classSubjects.remove(subject);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = isDark ? const Color(0xFF121212) : Colors.grey.shade50;
    Color textColor = isDark ? Colors.white : Colors.black87;
    Color fieldColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    Color hintColor = isDark ? Colors.grey.shade500 : Colors.grey.shade600;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text(
          "Setup Wizard",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF007ACC), // Original Trideta Blue
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      // 🚨 SHAPE-SHIFTER: LayoutBuilder
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth > 800) {
            // 💻 DESKTOP LAYOUT (Constrained Card)
            return Center(
              child: Container(
                width: 600, // Fixed width for comfortable data entry
                margin: const EdgeInsets.symmetric(vertical: 40),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Column(
                    children: [
                      _buildProgressHeader(),
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: Padding(
                            key: ValueKey<int>(_currentStep),
                            padding: const EdgeInsets.all(
                              32.0,
                            ), // More padding on web
                            child: _buildCurrentStepContent(
                              fieldColor,
                              hintColor,
                              textColor,
                              isDark,
                            ),
                          ),
                        ),
                      ),
                      _buildBottomControls(isDark),
                    ],
                  ),
                ),
              ),
            );
          } else {
            // 📱 MOBILE LAYOUT (Full Screen)
            return SafeArea(
              child: Column(
                children: [
                  _buildProgressHeader(),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Padding(
                        key: ValueKey<int>(_currentStep),
                        padding: const EdgeInsets.all(24.0),
                        child: _buildCurrentStepContent(
                          fieldColor,
                          hintColor,
                          textColor,
                          isDark,
                        ),
                      ),
                    ),
                  ),
                  _buildBottomControls(isDark),
                ],
              ),
            );
          }
        },
      ),
    );
  }

  Widget _buildProgressHeader() {
    double progress = _currentStep / _totalSteps;
    return Container(
      color: const Color(0xFF007ACC),
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Step $_currentStep of $_totalSteps",
                style: const TextStyle(color: Colors.white70),
              ),
              Text(
                _getStepTitle(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.white24,
              valueColor: const AlwaysStoppedAnimation<Color>(
                Colors.orangeAccent,
              ),
              minHeight: 8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentStepContent(
    Color fieldColor,
    Color hintColor,
    Color textColor,
    bool isDark,
  ) {
    switch (_currentStep) {
      case 1:
        return _buildSessionStep(fieldColor, hintColor);
      case 2:
        return _buildClassStep(fieldColor, hintColor, textColor, isDark);
      case 3:
        return _buildSubjectStep(fieldColor, hintColor, textColor, isDark);
      case 4:
        return _buildProfileStep(fieldColor, hintColor, textColor);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildSessionStep(Color fieldColor, Color hintColor) {
    return Column(
      children: [
        DropdownButtonFormField(
          initialValue: _selectedSession,
          decoration: _wizardInput(
            "Current Session",
            Icons.calendar_today,
            fieldColor,
            hintColor,
          ),
          items: [
            "2024/2025",
            "2025/2026",
            "2026/2027",
          ].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
          onChanged: (val) => setState(() => _selectedSession = val.toString()),
        ),
        const SizedBox(height: 20),
        DropdownButtonFormField(
          initialValue: _selectedTerm,
          decoration: _wizardInput(
            "Current Term",
            Icons.timer_outlined,
            fieldColor,
            hintColor,
          ),
          items: [
            "1st Term",
            "2nd Term",
            "3rd Term",
          ].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
          onChanged: (val) => setState(() => _selectedTerm = val.toString()),
        ),
      ],
    );
  }

  Widget _buildClassStep(
    Color fieldColor,
    Color hintColor,
    Color textColor,
    bool isDark,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Add classes and reorder them serially:",
          style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 15),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _classController,
                textCapitalization: TextCapitalization.characters,
                decoration: _wizardInput(
                  "e.g. NURSERY 1",
                  Icons.school,
                  fieldColor,
                  hintColor,
                ),
              ),
            ),
            const SizedBox(width: 10),
            IconButton.filled(
              onPressed: _addClass,
              icon: const Icon(Icons.add, color: Colors.white),
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFF007ACC),
                padding: const EdgeInsets.all(16),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Expanded(
          child: _classes.isEmpty
              ? const Center(
                  child: Text(
                    "No classes added yet.",
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ReorderableListView.builder(
                  itemCount: _classes.length,
                  onReorder: (oldIdx, newIdx) {
                    setState(() {
                      if (newIdx > oldIdx) newIdx -= 1;
                      _classes.insert(newIdx, _classes.removeAt(oldIdx));
                    });
                  },
                  itemBuilder: (ctx, i) => Container(
                    key: ValueKey(_classes[i]['name']),
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withOpacity(0.02)
                          : Colors.grey.shade50, // Slight contrast for web
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isDark ? Colors.white10 : Colors.grey.shade200,
                      ),
                    ),
                    child: ListTile(
                      dense: true,
                      leading: Text(
                        "${i + 1}.",
                        style: const TextStyle(
                          color: Color(0xFF007ACC),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      title: Text(
                        _classes[i]['name'],
                        style: TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.remove_circle_outline,
                              color: Colors.red,
                              size: 20,
                            ),
                            onPressed: () => _removeClass(_classes[i]),
                          ),
                          const Icon(Icons.drag_handle, color: Colors.grey),
                        ],
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildSubjectStep(
    Color fieldColor,
    Color hintColor,
    Color textColor,
    bool isDark,
  ) {
    if (_classes.isEmpty) {
      return const Center(
        child: Text(
          "Please go back and add at least one class first.",
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          value: _selectedClassForSubject,
          decoration: _wizardInput(
            "Target Class",
            Icons.class_,
            fieldColor,
            hintColor,
          ),
          items: _classes
              .map(
                (c) => DropdownMenuItem<String>(
                  value: c['name'],
                  child: Text(c['name']),
                ),
              )
              .toList(),
          onChanged: (val) => setState(() => _selectedClassForSubject = val),
        ),
        const SizedBox(height: 15),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'Compulsory', label: Text('Compulsory')),
              ButtonSegment(value: 'Elective', label: Text('Elective')),
            ],
            selected: {_subjectType},
            onSelectionChanged: (Set<String> newSelection) =>
                setState(() => _subjectType = newSelection.first),
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? const Color(0xFF007ACC).withOpacity(0.1)
                    : Colors.transparent,
              ),
              foregroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? const Color(0xFF007ACC)
                    : Colors.grey,
              ),
            ),
          ),
        ),
        const SizedBox(height: 15),

        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _subjectController,
                textCapitalization: TextCapitalization.characters,
                decoration: _wizardInput(
                  "Subject Name",
                  Icons.book,
                  fieldColor,
                  hintColor,
                ),
              ),
            ),
            const SizedBox(width: 10),
            IconButton.filled(
              onPressed: _addSubject,
              icon: const Icon(Icons.add, color: Colors.white),
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFF007ACC),
                padding: const EdgeInsets.all(16),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        Expanded(
          child: _selectedClassForSubject == null
              ? const Center(child: Text("Select a class"))
              : ListView(
                  children: [
                    _buildSubjectChipWrap("Compulsory Subjects", 'Compulsory'),
                    const SizedBox(height: 15),
                    _buildSubjectChipWrap("Elective Subjects", 'Elective'),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildSubjectChipWrap(String label, String type) {
    if (_selectedClassForSubject == null) return const SizedBox();

    final subjects = _classSubjects
        .where(
          (s) =>
              s['class_name'] == _selectedClassForSubject && s['type'] == type,
        )
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 5),
        if (subjects.isEmpty)
          const Text(
            "None added",
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey,
              fontStyle: FontStyle.italic,
            ),
          ),
        Wrap(
          spacing: 8,
          children: subjects
              .map(
                (s) => InputChip(
                  label: Text(
                    s['subject_name'],
                    style: const TextStyle(fontSize: 11),
                  ),
                  deleteIconColor: Colors.red,
                  onDeleted: () => _removeSubject(s),
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  Widget _buildProfileStep(Color fieldColor, Color hintColor, Color textColor) {
    return SingleChildScrollView(
      child: Column(
        children: [
          const Text(
            "Final step: Set your school logo and address.",
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 30),
          GestureDetector(
            onTap: _pickImage,
            child: CircleAvatar(
              radius: 65,
              backgroundColor: const Color(0xFF007ACC).withOpacity(0.1),
              backgroundImage: _webImage != null
                  ? MemoryImage(_webImage!)
                  : null,
              child: _webImage == null
                  ? const Icon(
                      Icons.add_a_photo,
                      color: Color(0xFF007ACC),
                      size: 35,
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            "Tap to add School Logo",
            style: TextStyle(color: hintColor, fontSize: 13),
          ),
          const SizedBox(height: 30),
          TextField(
            controller: _addressController,
            maxLines: 3,
            style: TextStyle(color: textColor),
            decoration: _wizardInput(
              "Physical School Address",
              Icons.location_on,
              fieldColor,
              hintColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls(bool isDark) {
    // If we are on web (and wide), the container has its own color.
    // If mobile, it respects the dark mode setting.
    bool isDesktop = MediaQuery.of(context).size.width > 800;
    Color bgColor = isDesktop
        ? Colors.transparent
        : (isDark ? const Color(0xFF1E1E1E) : Colors.white);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: bgColor,
        border: isDesktop
            ? Border(top: BorderSide(color: Colors.grey.withOpacity(0.2)))
            : null,
        boxShadow: isDesktop
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                ),
              ],
      ),
      child: Row(
        children: [
          if (_currentStep > 1)
            Expanded(
              child: OutlinedButton(
                onPressed: () => setState(() => _currentStep--),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                child: const Text("Back"),
              ),
            ),
          if (_currentStep > 1) const SizedBox(width: 15),
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _nextStep,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF007ACC),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      _currentStep == _totalSteps ? "FINISH SETUP" : "CONTINUE",
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _wizardInput(
    String label,
    IconData icon,
    Color fieldColor,
    Color hintColor,
  ) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: hintColor),
      prefixIcon: Icon(icon, color: const Color(0xFF007ACC)),
      filled: true,
      fillColor: fieldColor,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(color: Color(0xFF007ACC), width: 2),
      ),
    );
  }

  String _getStepTitle() {
    switch (_currentStep) {
      case 1:
        return "Timeline";
      case 2:
        return "Classes";
      case 3:
        return "Subjects";
      case 4:
        return "Final Details";
      default:
        return "";
    }
  }

  void _nextStep() async {
    if (_currentStep == 1) {
      bool confirm = await _showSessionConfirmation();
      if (!confirm) return;
    }
    if (_currentStep < _totalSteps) {
      setState(() => _currentStep++);
    } else {
      _finishSetup();
    }
  }

  Future<bool> _showSessionConfirmation() async {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    return await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            title: const Column(
              children: [
                Icon(Icons.lock_clock, color: Colors.orange, size: 40),
                SizedBox(height: 10),
                Text("Lock Timeline?", textAlign: TextAlign.center),
              ],
            ),
            content: Text(
              "Setting $_selectedSession - $_selectedTerm is permanent.",
              textAlign: TextAlign.center,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("Edit"),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF007ACC),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  "Yes, Lock It",
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ) ??
        false;
  }
}
