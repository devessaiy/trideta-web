import 'package:trideta_v2/utils/auth_error_handler.dart';
import 'package:flutter/foundation.dart'; // Required for kIsWeb and Uint8List
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:trideta_v2/main.dart'; // 🚨 Imports your global 'isInteractingWithSystem'

class SchoolProfileScreen extends StatefulWidget {
  const SchoolProfileScreen({super.key});

  @override
  State<SchoolProfileScreen> createState() => _SchoolProfileScreenState();
}

class _SchoolProfileScreenState extends State<SchoolProfileScreen>
    with AuthErrorHandler {
  final _supabase = Supabase.instance.client;

  // 🚨 Removed the hardcoded tridetaBlue here!

  bool _isLoading = true;
  bool _isSaving = false;
  String? _schoolId;

  // Form Controllers
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();

  // Image Data
  String? _currentLogoUrl;
  XFile? _pickedFile;
  Uint8List? _webImage;

  @override
  void initState() {
    super.initState();
    _fetchSchoolProfile();
  }

  // --- 1. FETCH EXACT DATA USED BY HOME SCREEN ---
  Future<void> _fetchSchoolProfile() async {
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
            .select('name, address, logo_url')
            .eq('id', _schoolId!)
            .single();

        if (mounted) {
          setState(() {
            _nameController.text = school['name'] ?? '';
            _addressController.text = school['address'] ?? '';
            _currentLogoUrl = school['logo_url'];
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        showAuthErrorDialog("Failed to load profile data.");
      }
    }
  }

  // --- 2. THE "HALL PASS" IMAGE PICKER ---
  Future<void> _pickImage() async {
    // 🚨 HALL PASS: Tell the app's security timer we are opening the OS Gallery
    isInteractingWithSystem = true;

    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
      );

      if (image != null) {
        final bytes = await image.readAsBytes();
        setState(() {
          _pickedFile = image;
          _webImage = bytes; // Use bytes for universal display (Web/Mobile)
        });
      }
    } catch (e) {
      debugPrint("Image Picker Error: $e");
    } finally {
      // 🚨 HALL PASS RETURNED: We are back in the app
      isInteractingWithSystem = false;
    }
  }

  // --- 3. SAVE TO DATABASE & CLOUD STORAGE ---
  Future<void> _saveProfile() async {
    if (_nameController.text.trim().isEmpty) {
      showAuthErrorDialog("School Name cannot be empty.");
      return;
    }

    setState(() => _isSaving = true);

    try {
      String? finalLogoUrl = _currentLogoUrl;

      // If a new image was picked, upload it to the 'school_logos' bucket
      if (_pickedFile != null && _webImage != null) {
        final fileExt = _pickedFile!.name.split('.').last;
        final fileName =
            'logo_${_schoolId}_${DateTime.now().millisecondsSinceEpoch}.$fileExt';
        final path = 'logos/$fileName';

        try {
          await _supabase.storage
              .from('school_logos')
              .uploadBinary(
                path,
                _webImage!,
                fileOptions: FileOptions(contentType: 'image/$fileExt'),
              );
          finalLogoUrl = _supabase.storage
              .from('school_logos')
              .getPublicUrl(path);
        } catch (storageError) {
          if (storageError.toString().contains("bucket not found")) {
            throw "Storage bucket 'school_logos' is missing. Please contact TriDeta support.";
          }
          rethrow;
        }
      }

      // Update the main schools table (This is what the Home Screen reads from)
      await _supabase
          .from('schools')
          .update({
            'name': _nameController.text.trim(),
            'address': _addressController.text.trim(),
            'logo_url': finalLogoUrl,
          })
          .eq('id', _schoolId!);

      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("School Profile Updated!"),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context); // Return to settings menu
      }
    } catch (e) {
      setState(() => _isSaving = false);
      showAuthErrorDialog(
        "Failed to update profile. Ensure your internet connection is active.",
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC);
    Color cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    // 🚨 DYNAMIC COLOR INJECTION
    Color tridetaBlue = Theme.of(context).primaryColor;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: bgColor,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text(
          "School Profile",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: tridetaBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // --- LOGO PICKER SECTION ---
            Center(
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  GestureDetector(
                    onTap: _pickImage,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: cardColor,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 15,
                          ),
                        ],
                      ),
                      child: CircleAvatar(
                        radius: 60,
                        backgroundColor: tridetaBlue.withOpacity(0.05),
                        backgroundImage: _webImage != null
                            ? MemoryImage(_webImage!)
                            : (_currentLogoUrl != null
                                      ? NetworkImage(_currentLogoUrl!)
                                      : null)
                                  as ImageProvider?,
                        child: (_webImage == null && _currentLogoUrl == null)
                            ? Icon(
                                Icons.school_rounded,
                                color: tridetaBlue.withOpacity(0.5),
                                size: 50,
                              )
                            : null,
                      ),
                    ),
                  ),
                  // Camera Icon Badge
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: tridetaBlue,
                      shape: BoxShape.circle,
                      border: Border.all(color: bgColor, width: 3),
                    ),
                    child: const Icon(
                      Icons.camera_alt_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 15),
            const Text(
              "Tap to update School Logo",
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 40),

            // --- FORM SECTION ---
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark ? Colors.white10 : Colors.grey.shade200,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionLabel("OFFICIAL IDENTITY", isDark, tridetaBlue),
                  TextField(
                    controller: _nameController,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                    decoration: _inputStyle(
                      "School Name",
                      Icons.account_balance_rounded,
                      isDark,
                      tridetaBlue,
                    ),
                  ),
                  const SizedBox(height: 20),

                  _buildSectionLabel("CONTACT & LOCATION", isDark, tridetaBlue),
                  TextField(
                    controller: _addressController,
                    maxLines: 3,
                    decoration: _inputStyle(
                      "Physical Address",
                      Icons.location_on_rounded,
                      isDark,
                      tridetaBlue,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),

            // --- SAVE BUTTON ---
            SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: tridetaBlue,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                onPressed: _isSaving ? null : _saveProfile,
                icon: _isSaving
                    ? const SizedBox()
                    : const Icon(
                        Icons.cloud_upload_rounded,
                        color: Colors.white,
                      ),
                label: _isSaving
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        "SAVE PROFILE CHANGES",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 🚨 Passed the dynamic color down to the helpers
  Widget _buildSectionLabel(String text, bool isDark, Color tridetaBlue) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 4),
      child: Text(
        text,
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: tridetaBlue,
          fontSize: 11,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  InputDecoration _inputStyle(
    String label,
    IconData icon,
    bool isDark,
    Color tridetaBlue,
  ) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: tridetaBlue, size: 20),
      filled: true,
      fillColor: isDark ? Colors.white.withOpacity(0.03) : Colors.grey[50],
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide.none,
      ),
    );
  }
}
