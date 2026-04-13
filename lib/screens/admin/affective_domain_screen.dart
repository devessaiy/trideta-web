import 'package:trideta_v2/utils/auth_error_handler.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AffectiveDomainScreen extends StatefulWidget {
  const AffectiveDomainScreen({super.key});

  @override
  State<AffectiveDomainScreen> createState() => _AffectiveDomainScreenState();
}

class _AffectiveDomainScreenState extends State<AffectiveDomainScreen>
    with AuthErrorHandler {
  final _supabase = Supabase.instance.client;

  bool _isLoading = true;
  String? _schoolId;
  String _userRole = 'teacher';

  String? _selectedSession;
  String? _selectedTerm;
  String? _selectedClass;

  final List<String> _sessions = ['2024/2025', '2025/2026', '2026/2027'];
  final List<String> _terms = ['1st Term', '2nd Term', '3rd Term'];
  List<String> _activeClasses = [];

  List<Map<String, dynamic>> _students = [];
  Map<String, Map<String, dynamic>> _affectiveData = {};

  @override
  void initState() {
    super.initState();
    _fetchInitialData();
  }

  Future<void> _fetchInitialData() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final profile = await _supabase
          .from('profiles')
          .select('school_id, role')
          .eq('id', user.id)
          .single();
      _schoolId = profile['school_id'];
      _userRole = profile['role']?.toString().toLowerCase() ?? 'teacher';

      final school = await _supabase
          .from('schools')
          .select('current_session, current_term')
          .eq('id', _schoolId!)
          .single();

      List<String> fetchedClasses = [];
      if (_userRole == 'admin') {
        final classesData = await _supabase
            .from('classes')
            .select('name')
            .eq('school_id', _schoolId!)
            .order('list_order', ascending: true);
        fetchedClasses = classesData.map((c) => c['name'].toString()).toList();
      } else {
        final assignments = await _supabase
            .from('staff_assignments')
            .select('class_assigned')
            .eq('staff_id', user.id);
        fetchedClasses = assignments
            .map((a) => a['class_assigned'].toString())
            .toSet()
            .toList();
        fetchedClasses.sort();
      }

      if (mounted) {
        setState(() {
          _selectedSession = school['current_session'] ?? _sessions[1];
          _selectedTerm = school['current_term'] ?? _terms[0];
          _activeClasses = fetchedClasses;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        showAuthErrorDialog("Failed to initialize. Check connection.");
      }
    }
  }

  Future<void> _fetchStudentsAndTraits() async {
    if (_selectedClass == null) return;
    setState(() => _isLoading = true);

    try {
      final studentsData = await _supabase
          .from('students')
          .select('id, first_name, last_name')
          .eq('school_id', _schoolId!)
          .eq('class_level', _selectedClass!)
          .order('first_name', ascending: true);

      // Fetch both traits AND term results (to get the principal's remark)
      final traitsData = await _supabase
          .from('affective_traits')
          .select()
          .eq('school_id', _schoolId!)
          .eq('academic_session', _selectedSession!)
          .eq('term', _selectedTerm!)
          .eq('class_level', _selectedClass!);
      final resultsData = await _supabase
          .from('term_results')
          .select('student_id, principal_remark')
          .eq('school_id', _schoolId!)
          .eq('academic_session', _selectedSession!)
          .eq('term', _selectedTerm!)
          .eq('class_level', _selectedClass!);

      Map<String, dynamic> existingTraits = {
        for (var item in traitsData) item['student_id'].toString(): item,
      };
      Map<String, dynamic> existingResults = {
        for (var item in resultsData) item['student_id'].toString(): item,
      };

      _affectiveData.clear();
      for (var s in studentsData) {
        String sId = s['id'].toString();
        var trait = existingTraits[sId];
        var result = existingResults[sId];

        _affectiveData[sId] = {
          'punctuality': trait?['punctuality'] ?? 3,
          'neatness': trait?['neatness'] ?? 3,
          'honesty': trait?['honesty'] ?? 3,
          'peer_relationship': trait?['peer_relationship'] ?? 3,
          'manual_dexterity': trait?['manual_dexterity'] ?? 3,
          'class_teacher_remark': trait?['class_teacher_remark'] ?? "",
          'principal_remark':
              result?['principal_remark'] ?? "", // 🚨 Added Principal Remark
        };
      }

      if (mounted) {
        setState(() {
          _students = List<Map<String, dynamic>>.from(studentsData);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        showAuthErrorDialog("Failed to load students.");
      }
    }
  }

  Future<void> _saveAllTraits() async {
    setState(() => _isLoading = true);
    bool isAdmin = _userRole == 'admin';

    try {
      List<Map<String, dynamic>> traitsUpsertList = [];

      for (var student in _students) {
        String sId = student['id'].toString();
        var data = _affectiveData[sId]!;

        traitsUpsertList.add({
          'school_id': _schoolId,
          'student_id': sId,
          'academic_session': _selectedSession,
          'term': _selectedTerm,
          'class_level': _selectedClass,
          'punctuality': data['punctuality'],
          'neatness': data['neatness'],
          'honesty': data['honesty'],
          'peer_relationship': data['peer_relationship'],
          'manual_dexterity': data['manual_dexterity'],
          'class_teacher_remark': data['class_teacher_remark'],
        });

        // 🚨 Admin Only: Update the principal's remark in the term_results table
        if (isAdmin &&
            data['principal_remark'] != null &&
            data['principal_remark'].toString().isNotEmpty) {
          await _supabase
              .from('term_results')
              .update({'principal_remark': data['principal_remark']})
              .eq('student_id', sId)
              .eq('academic_session', _selectedSession!)
              .eq('term', _selectedTerm!)
              .eq('class_level', _selectedClass!);
        }
      }

      // Save the normal traits
      for (var data in traitsUpsertList) {
        await _supabase
            .from('affective_traits')
            .upsert(data, onConflict: 'student_id, academic_session, term');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Traits & Remarks Saved!"),
            backgroundColor: Colors.green,
          ),
        );
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        showAuthErrorDialog("Failed to save traits.");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC);
    Color cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    Color primaryColor = Theme.of(context).primaryColor;

    bool isAdmin = _userRole == 'admin';

    // 🚨 SMART TITLE LOGIC
    String clsLower = (_selectedClass ?? "").toLowerCase();
    bool isPrimary =
        clsLower.contains('primary') ||
        clsLower.contains('basic') ||
        clsLower.contains('nursery') ||
        clsLower.contains('pre');
    String headTitle = isPrimary ? "Headmaster" : "Principal";

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text(
          "Affective Domain",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      // 🚨 SHAPE-SHIFTER: LayoutBuilder
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth > 800) {
            // 💻 DESKTOP LAYOUT (Constrained Center Column)
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 20),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(
                      color: isDark ? Colors.white10 : Colors.grey.shade200,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(15),
                    child: _buildMainContent(
                      isDark,
                      primaryColor,
                      cardColor,
                      headTitle,
                      isAdmin,
                    ),
                  ),
                ),
              ),
            );
          } else {
            // 📱 MOBILE LAYOUT (Full Width)
            return _buildMainContent(
              isDark,
              primaryColor,
              cardColor,
              headTitle,
              isAdmin,
            );
          }
        },
      ),
      floatingActionButton: _students.isNotEmpty
          ? FloatingActionButton.extended(
              backgroundColor: primaryColor,
              onPressed: _saveAllTraits,
              icon: const Icon(Icons.save_rounded, color: Colors.white),
              label: const Text(
                "SAVE TRAITS",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          : null,
    );
  }

  // 🚨 EXTRACTED MAIN CONTENT FOR REUSABILITY IN RESPONSIVE LAYOUT
  Widget _buildMainContent(
    bool isDark,
    Color primaryColor,
    Color cardColor,
    String headTitle,
    bool isAdmin,
  ) {
    return Column(
      children: [
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
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _buildFilterDropdown(
                      "Session",
                      _sessions,
                      _selectedSession,
                      isAdmin
                          ? (val) => setState(() => _selectedSession = val)
                          : null,
                      isDark,
                      primaryColor,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildFilterDropdown(
                      "Term",
                      _terms,
                      _selectedTerm,
                      isAdmin
                          ? (val) => setState(() => _selectedTerm = val)
                          : null,
                      isDark,
                      primaryColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildFilterDropdown(
                "Select Class",
                _activeClasses,
                _selectedClass,
                (val) {
                  setState(() => _selectedClass = val);
                  _fetchStudentsAndTraits();
                },
                isDark,
                primaryColor,
              ),

              if (isAdmin && _selectedClass != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    "Note: $headTitle remarks will only save for students whose results have been published in the Broadsheet.",
                    style: TextStyle(
                      color: Colors.orange[700],
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: _isLoading
              ? Center(child: CircularProgressIndicator(color: primaryColor))
              : _students.isEmpty
              ? const Center(
                  child: Text(
                    "Select a Class to begin.",
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _students.length,
                  itemBuilder: (ctx, i) {
                    final s = _students[i];
                    final sId = s['id'].toString();
                    return _buildStudentTraitCard(
                      sId,
                      "${s['last_name']} ${s['first_name']}",
                      headTitle,
                      isAdmin,
                      cardColor,
                      isDark,
                      primaryColor,
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildFilterDropdown(
    String hint,
    List<String> items,
    String? value,
    Function(String?)? onChanged,
    bool isDark,
    Color primaryColor,
  ) {
    bool isLocked = onChanged == null;
    if (items.isEmpty && !isLocked) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: isLocked
            ? (isDark ? Colors.white.withOpacity(0.02) : Colors.grey[200])
            : (isDark ? Colors.white.withOpacity(0.05) : Colors.grey[50]),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade300,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: value,
          hint: Padding(
            padding: const EdgeInsets.only(left: 10),
            child: Text(
              hint,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
          icon: Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Icon(
              isLocked ? Icons.lock_outline : Icons.arrow_drop_down,
              color: isLocked ? Colors.grey : primaryColor,
              size: isLocked ? 16 : 24,
            ),
          ),
          items: items
              .map(
                (e) => DropdownMenuItem(
                  value: e,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: Text(
                      e,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isLocked ? Colors.grey : null,
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

  Widget _buildStudentTraitCard(
    String sId,
    String name,
    String headTitle,
    bool isAdmin,
    Color cardColor,
    bool isDark,
    Color primaryColor,
  ) {
    var data = _affectiveData[sId]!;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: BorderSide(color: isDark ? Colors.white10 : Colors.grey.shade300),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: Text(
            name.toUpperCase(),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          subtitle: const Text(
            "Tap to rate behaviors & add remarks",
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
          childrenPadding: const EdgeInsets.all(15),
          children: [
            _buildRatingRow("Punctuality", sId, 'punctuality', primaryColor),
            _buildRatingRow("Neatness", sId, 'neatness', primaryColor),
            _buildRatingRow("Honesty", sId, 'honesty', primaryColor),
            _buildRatingRow(
              "Peer Relationship",
              sId,
              'peer_relationship',
              primaryColor,
            ),
            _buildRatingRow(
              "Manual Dexterity",
              sId,
              'manual_dexterity',
              primaryColor,
            ),
            const SizedBox(height: 15),

            // Class Teacher Remark (Editable by everyone)
            TextFormField(
              initialValue: data['class_teacher_remark'],
              onChanged: (val) =>
                  _affectiveData[sId]!['class_teacher_remark'] = val,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: "Form Master's Remark",
                labelStyle: const TextStyle(fontSize: 12),
                filled: true,
                fillColor: isDark
                    ? Colors.white.withOpacity(0.05)
                    : Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 10),

            // 🚨 Principal/Headmaster Remark (Editable ONLY by Admin)
            TextFormField(
              initialValue: data['principal_remark'],
              onChanged: isAdmin
                  ? (val) => _affectiveData[sId]!['principal_remark'] = val
                  : null,
              readOnly: !isAdmin,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: "$headTitle's Remark",
                labelStyle: const TextStyle(fontSize: 12),
                filled: true,
                fillColor: isDark
                    ? Colors.white.withOpacity(0.05)
                    : Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                suffixIcon: !isAdmin
                    ? const Icon(
                        Icons.lock_outline,
                        color: Colors.grey,
                        size: 16,
                      )
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRatingRow(
    String title,
    String sId,
    String key,
    Color primaryColor,
  ) {
    int currentValue = _affectiveData[sId]![key];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          Row(
            children: List.generate(5, (index) {
              int val = index + 1;
              bool isSelected = val == currentValue;
              return GestureDetector(
                onTap: () => setState(() => _affectiveData[sId]![key] = val),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: isSelected ? primaryColor : Colors.grey[300],
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    val.toString(),
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.black,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}
