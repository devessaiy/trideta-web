import 'package:trideta_v2/utils/auth_error_handler.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  List<Map<String, dynamic>> _myAssignments = [];

  // RELATIONAL STATE DATA
  List<String> _activeClasses = [];
  List<String> _activeSubjects = [];
  final Map<String, List<String>> _subjectToClassMap = {};

  // 🚨 NEW: Toggle state for the Role/Email badge
  bool _showEmailToggle = false;

  @override
  void initState() {
    super.initState();
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

      // 1. Fetch active classes from relational table
      final classesData = await _supabase
          .from('classes')
          .select('name')
          .eq('school_id', schoolId)
          .order('list_order', ascending: true);

      // 2. Fetch subjects from relational table
      final subjectsData = await _supabase
          .from('class_subjects')
          .select('class_name, subject_name')
          .eq('school_id', schoolId);

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
      constraints: const BoxConstraints(
        maxWidth: 600,
      ), // 🚨 CONSTRAINED FOR WEB/DESKTOP
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
                              ? Colors.white.withOpacity(0.05)
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
                            color: Colors.red.withOpacity(0.1),
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
                              ? Colors.white.withOpacity(0.05)
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
                              ? Colors.white.withOpacity(0.02)
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
                ? primaryColor.withOpacity(0.1)
                : (isDark ? Colors.white.withOpacity(0.02) : Colors.white),
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

  Future<void> _deleteStaffProfile() async {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    bool confirm =
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Row(
              children: [
                Icon(Icons.person_off_rounded, color: Colors.red),
                SizedBox(width: 10),
                Text("Remove Staff?"),
              ],
            ),
            content: Text(
              "Are you sure you want to remove ${widget.staffData['full_name']}? This will revoke their access to the app.",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text(
                  "CANCEL",
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.pop(ctx, true),
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
    Color bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC);
    Color cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    Color primaryColor = Theme.of(context).primaryColor;

    final staff = widget.staffData;
    final String fullName = staff['full_name'] ?? "Staff Member";
    final String rawRole = staff['role']?.toString().toLowerCase() ?? 'staff';
    final String displayRole = staff['designation'] ?? rawRole.toUpperCase();
    final String? passportUrl = staff['passport_url'];
    final String id = staff['id'].toString();
    final String staffEmail = staff['email'] ?? 'No email available';

    final bool isBursar = rawRole == 'bursar' || rawRole == 'finance';
    Color roleBadgeColor = (isBursar) ? Colors.green : primaryColor;

    // 🚨 MAIN CONTENT EXTRACTED FOR LAYOUT BUILDER
    Widget mainContent = SingleChildScrollView(
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.only(bottom: 30, top: 20),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(30),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                ),
              ],
            ),
            child: Center(
              child: Column(
                children: [
                  Hero(
                    tag: 'staff_avatar_$id',
                    child: Container(
                      width: 110,
                      height: 110,
                      decoration: BoxDecoration(
                        color: roleBadgeColor.withOpacity(0.1),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: roleBadgeColor.withOpacity(0.2),
                          width: 3,
                        ),
                        image: passportUrl != null
                            ? DecorationImage(
                                image: NetworkImage(passportUrl),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: passportUrl == null
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
                  const SizedBox(height: 15),
                  Text(
                    fullName,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // 🚨 REPLACED POPUP WITH IN-PLACE TOGGLE 🚨
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _showEmailToggle = !_showEmailToggle;
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: roleBadgeColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: roleBadgeColor.withOpacity(0.3),
                        ),
                      ),
                      child: Text(
                        _showEmailToggle ? staffEmail : displayRole,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: roleBadgeColor,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "Tap badge to reveal login email",
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          if (isBursar) ...[
            Padding(
              padding: const EdgeInsets.all(24),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.green.withOpacity(0.1)
                      : Colors.green[50],
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.green.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.account_balance_wallet_rounded,
                      size: 40,
                      color: Colors.green[600],
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Financial Access",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: isDark
                                  ? Colors.green[300]
                                  : Colors.green[900],
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            "This staff member has full access to the Finance Centre to record payments and manage fee structures.",
                            style: TextStyle(
                              color: isDark
                                  ? Colors.green[100]
                                  : Colors.green[800],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Active Roles",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  ElevatedButton.icon(
                    onPressed: _showAddResponsibilityModal,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor.withOpacity(0.1),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    icon: Icon(
                      Icons.add_rounded,
                      size: 18,
                      color: primaryColor,
                    ),
                    label: Text(
                      "ASSIGN",
                      style: TextStyle(
                        color: primaryColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _isLoading
                ? const Padding(
                    padding: EdgeInsets.all(30),
                    child: CircularProgressIndicator(),
                  )
                : _myAssignments.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(40),
                    child: Column(
                      children: [
                        Icon(
                          Icons.assignment_outlined,
                          size: 60,
                          color: isDark ? Colors.white10 : Colors.grey[300],
                        ),
                        const SizedBox(height: 15),
                        Text(
                          "No classes or subjects assigned.",
                          style: TextStyle(
                            color: isDark ? Colors.white38 : Colors.grey[400],
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 10,
                    ),
                    itemCount: _myAssignments.length,
                    itemBuilder: (context, index) {
                      final item = _myAssignments[index];
                      final isClassTeacher = item['subject_assigned'] == null;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(
                            color: isDark
                                ? Colors.white10
                                : Colors.grey.shade200,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.02),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          leading: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: isClassTeacher
                                  ? Colors.orange.withOpacity(0.1)
                                  : primaryColor.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              isClassTeacher
                                  ? Icons.star_rounded
                                  : Icons.menu_book_rounded,
                              color: isClassTeacher
                                  ? Colors.orange
                                  : primaryColor,
                              size: 20,
                            ),
                          ),
                          title: Text(
                            item['class_assigned'],
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              isClassTeacher
                                  ? "Form Master"
                                  : "${item['subject_assigned']} Teacher",
                              style: TextStyle(
                                color: isClassTeacher
                                    ? Colors.orange[700]
                                    : Colors.grey[500],
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
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
                      );
                    },
                  ),
          ],
        ],
      ),
    );

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: primaryColor,
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text(
          "Staff Profile",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_forever_rounded),
            onPressed: _deleteStaffProfile,
          ),
        ],
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
