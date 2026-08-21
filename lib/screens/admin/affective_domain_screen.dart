import 'package:trideta_v2/utils/auth_error_handler.dart';
import 'package:trideta_v2/widgets/trideta_loader.dart';
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

  late List<String> _sessions;
  final List<String> _terms = ['1st Term', '2nd Term', '3rd Term'];
  String? _selectedSession;
  String? _selectedTerm;

  String? _globalSession;
  String? _globalTerm;

  String? _selectedClass;
  List<String> _activeClasses = [];

  final Map<String, String> _classNameToIdMap = {};

  List<Map<String, dynamic>> _students = [];
  final Map<String, Map<String, dynamic>> _affectiveData = {};

  @override
  void initState() {
    super.initState();
    _sessions = _generateDynamicSessions();
    _fetchInitialData();
  }

  List<String> _generateDynamicSessions() {
    int currentYear = DateTime.now().year;
    List<String> list = [];
    for (int i = 2020; i <= currentYear + 3; i++) {
      list.add("$i/${i + 1}");
    }
    return list;
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

      int currentYr = DateTime.now().year;
      _globalSession =
          school['current_session'] ?? "$currentYr/${currentYr + 1}";
      _globalTerm = school['current_term'] ?? _terms[0];

      if (!_sessions.contains(_globalSession)) {
        _sessions.add(_globalSession!);
      }

      List<String> fetchedClasses = [];
      _classNameToIdMap.clear();

      if (_userRole == 'admin' || _userRole == 'principal') {
        final classesData = await _supabase
            .from('classes')
            .select('id, name') 
            .eq('school_id', _schoolId!)
            .order('list_order', ascending: true);
        for (var c in classesData) {
          String cName = c['name'].toString();
          _classNameToIdMap[cName] = c['id'].toString();
          fetchedClasses.add(cName);
        }
      } else {
        final classesData = await _supabase
            .from('classes')
            .select('id, name') 
            .eq('school_id', _schoolId!)
            .order('list_order', ascending: true);

        final assignments = await _supabase
            .from('staff_assignments')
            .select('class_id, class_assigned')
            .eq('staff_id', user.id);

        final Set<String> assignedKeys = {};
        for (var a in assignments) {
          if (a['class_id'] != null) assignedKeys.add(a['class_id'].toString());
          if (a['class_assigned'] != null) {
            assignedKeys.add(a['class_assigned'].toString());
          }
        }

        for (var c in classesData) {
          String cId = c['id'].toString();
          String cName = c['name'].toString();

          if (assignedKeys.contains(cId) || assignedKeys.contains(cName)) {
            _classNameToIdMap[cName] = cId;
            fetchedClasses.add(cName);
          }
        }
        fetchedClasses.sort();
      }

      if (mounted) {
        setState(() {
          _selectedSession = _globalSession;
          _selectedTerm = _globalTerm;
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
          .eq('class_id', _classNameToIdMap[_selectedClass]!)
          .order('first_name', ascending: true);

      final traitsData = await _supabase
          .from('affective_traits')
          .select()
          .eq('school_id', _schoolId!)
          .eq('academic_session', _selectedSession!)
          .eq('term', _selectedTerm!)
          .eq('class_id', _classNameToIdMap[_selectedClass]!);
      final resultsData = await _supabase
          .from('term_results')
          .select('student_id, principal_remark')
          .eq('school_id', _schoolId!)
          .eq('academic_session', _selectedSession!)
          .eq('term', _selectedTerm!)
          .eq('class_id', _classNameToIdMap[_selectedClass]!);

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
          'principal_remark': result?['principal_remark'] ?? "",
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
    bool isAdmin = _userRole == 'admin' || _userRole == 'principal';

    try {
      for (var student in _students) {
        String sId = student['id'].toString();
        var data = _affectiveData[sId]!;

        final existing = await _supabase
            .from('affective_traits')
            .select('id')
            .eq('student_id', sId)
            .eq('academic_session', _selectedSession!)
            .eq('term', _selectedTerm!)
            .maybeSingle();

        final payload = {
          'school_id': _schoolId,
          'student_id': sId,
          'academic_session': _selectedSession,
          'term': _selectedTerm,
          'class_id': _classNameToIdMap[_selectedClass],
          'class_level': _selectedClass,
          'punctuality': data['punctuality'],
          'neatness': data['neatness'],
          'honesty': data['honesty'],
          'peer_relationship': data['peer_relationship'],
          'manual_dexterity': data['manual_dexterity'],
          'class_teacher_remark': data['class_teacher_remark'],
        };

        if (existing == null) {
          await _supabase.from('affective_traits').insert(payload);
        } else {
          await _supabase
              .from('affective_traits')
              .update(payload)
              .eq('id', existing['id']);
        }

        if (isAdmin &&
            data['principal_remark'] != null &&
            data['principal_remark'].toString().isNotEmpty) {
          await _supabase
              .from('term_results')
              .update({'principal_remark': data['principal_remark']})
              .eq('student_id', sId)
              .eq('academic_session', _selectedSession!)
              .eq('term', _selectedTerm!)
              .eq('class_id', _classNameToIdMap[_selectedClass]!);
        }
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
        showAuthErrorDialog("Failed to save traits. Check connection.");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC);
    Color cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    Color primaryColor = Theme.of(context).primaryColor;
    Color textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);

    bool isAdmin = _userRole == 'admin' || _userRole == 'principal';

    String clsLower = (_selectedClass ?? "").toLowerCase();
    bool isPrimary =
        clsLower.contains('primary') ||
        clsLower.contains('basic') ||
        clsLower.contains('nursery') ||
        clsLower.contains('pre');
    String headTitle = isPrimary ? "Headmaster" : "Principal";

    Widget mainContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 🚨 Dynamic Island / Notch Safe Header
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.only(left: 10, top: 16, bottom: 16, right: 24),
            child: Row(
              children: [
                BackButton(color: textColor),
                const SizedBox(width: 4),
                Text(
                  "Affective Domain",
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: textColor,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
          ),
        ),

        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          decoration: BoxDecoration(
            color: cardColor,
            border: Border(
              bottom: BorderSide(
                color: isDark ? Colors.white10 : Colors.grey.shade200,
                width: 1,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _buildInfoField(
                      "Academic Session",
                      _selectedSession ?? "--",
                      isDark,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildInfoField(
                      "Current Term",
                      _selectedTerm ?? "--",
                      isDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _buildClassDropdown(
                "Select Class",
                _activeClasses,
                _selectedClass,
                (val) {
                  setState(() {
                    _selectedClass = val;
                    if (val != null) {
                      _selectedSession = _globalSession;
                      _selectedTerm = _globalTerm;
                    }
                  });
                  _fetchStudentsAndTraits();
                },
                isDark,
                primaryColor,
              ),
              if (isAdmin && _selectedClass != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
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
              ? Center(child: TridetaLoader(color: primaryColor))
              : _students.isEmpty
              ? const Center(
                  child: Text(
                    "Select a Class to begin.",
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: _students.length,
                  separatorBuilder: (ctx, i) => Divider(
                    height: 1,
                    color: isDark ? Colors.white10 : Colors.grey.shade200,
                  ),
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

    return Scaffold(
      backgroundColor: bgColor,
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth > 800) {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: Container(
                  decoration: BoxDecoration(
                    color: bgColor,
                    border: Border.symmetric(
                      vertical: BorderSide(
                        color: isDark ? Colors.white10 : Colors.grey.shade200,
                      ),
                    ),
                  ),
                  child: mainContent,
                ),
              ),
            );
          } else {
            return mainContent;
          }
        },
      ),
      bottomNavigationBar: _students.isNotEmpty
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: Container(
                    width: MediaQuery.of(context).size.width > 800 
                        ? 800 
                        : MediaQuery.of(context).size.width,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    decoration: BoxDecoration(
                      color: cardColor,
                      border: Border(
                        top: BorderSide(
                          color: isDark ? Colors.white10 : Colors.grey.shade200,
                          width: 1,
                        ),
                      ),
                    ),
                    child: SafeArea(
                      child: SizedBox(
                        width: double.infinity,
                        height: 55,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: primaryColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: _isLoading ? null : _saveAllTraits,
                          icon: const Icon(Icons.save_rounded, color: Colors.white),
                          label: const Text(
                            "SAVE TRAITS",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            )
          : null,
    );
  }

  Widget _buildInfoField(
    String label,
    String value,
    bool isDark,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade500,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _buildClassDropdown(
    String hint,
    List<String> items,
    String? value,
    Function(String?)? onChanged,
    bool isDark,
    Color primaryColor,
  ) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey[50],
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
            child: Icon(Icons.arrow_drop_down, color: primaryColor),
          ),
          items: items
              .map(
                (e) => DropdownMenuItem(
                  value: e,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: Text(
                      e,
                      style: const TextStyle(
                        fontSize: 12,
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

    return Container(
      color: isDark ? const Color(0xFF121212) : Colors.white,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          title: Text(
            name.toUpperCase(),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          subtitle: const Text(
            "Tap to rate behaviors & add remarks",
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
          childrenPadding: const EdgeInsets.only(left: 24, right: 24, bottom: 20),
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
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 10),

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
                    ? Colors.white.withValues(alpha: 0.05)
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