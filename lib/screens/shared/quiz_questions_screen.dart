import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trideta_v2/utils/resilient_request.dart';
import 'package:trideta_v2/widgets/docs_widgets.dart';
import 'package:trideta_v2/widgets/trideta_loader.dart';
import 'package:trideta_v2/widgets/trideta_ui_kit.dart';

/// Shows the quiz questions made from one approved lesson note. The teacher
/// (or the admin) approves, removes or restores each question. Students will
/// only ever see approved questions.
class QuizQuestionsScreen extends StatefulWidget {
  final String noteId;
  final String title;
  const QuizQuestionsScreen({super.key, required this.noteId, required this.title});

  @override
  State<QuizQuestionsScreen> createState() => _QuizQuestionsScreenState();
}

class _QuizQuestionsScreenState extends State<QuizQuestionsScreen> {
  final _supabase = Supabase.instance.client;
  bool _loading = true;
  bool _busy = false;
  bool _aiEnabled = false;
  Map<String, dynamic>? _job;
  List<Map<String, dynamic>> _questions = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final note = await retryRead(
        () async => await _supabase
            .from('lesson_notes')
            .select('school_id')
            .eq('id', widget.noteId)
            .single(),
      );
      final school = await retryRead(
        () async => await _supabase
            .from('schools')
            .select('ai_quiz_enabled')
            .eq('id', note['school_id'] as String)
            .single(),
      );
      final job = await retryRead(
        () async => await _supabase
            .from('quiz_jobs')
            .select('status, last_error, attempts, regenerations, question_count')
            .eq('lesson_note_id', widget.noteId)
            .maybeSingle(),
      );
      final qs = await retryRead(
        () async => await _supabase
            .from('quiz_questions')
            .select('id, question, options, correct_index, explanation, status')
            .eq('lesson_note_id', widget.noteId)
            .order('created_at')
            .order('id'),
      );
      if (!mounted) return;
      setState(() {
        _aiEnabled = school['ai_quiz_enabled'] == true;
        _job = job == null ? null : Map<String, dynamic>.from(job);
        _questions = List<Map<String, dynamic>>.from(qs);
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        showDocSnack(context, friendlyDocError(e), error: true);
      }
    }
  }

  String _friendly(Object e) {
    final s = e.toString();
    if (s.contains('AI_QUIZ_OFF')) {
      return 'AI quiz generation is switched off for your school. Ask your admin to switch it on in Lesson Note Approvals.';
    }
    if (s.contains('REGEN_LIMIT')) {
      return 'A new set has already been made 3 times for this note.';
    }
    if (s.contains('NOTE_NOT_APPROVED')) {
      return 'Questions are made only from approved lesson notes.';
    }
    return friendlyDocError(e);
  }

  Future<void> _setStatus(String id, String status) async {
    setState(() => _busy = true);
    try {
      await retryIdempotent(
        () async => await _supabase
            .from('quiz_questions')
            .update({'status': status})
            .eq('id', id),
        maxAttempts: 2,
      );
      await _load();
    } catch (e) {
      if (mounted) showDocSnack(context, _friendly(e), error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _approveAll() async {
    setState(() => _busy = true);
    try {
      await retryIdempotent(
        () async => await _supabase
            .from('quiz_questions')
            .update({'status': 'active'})
            .eq('lesson_note_id', widget.noteId)
            .eq('status', 'pending'),
        maxAttempts: 2,
      );
      await _load();
      if (mounted) showDocSnack(context, 'All waiting questions approved.');
    } catch (e) {
      if (mounted) showDocSnack(context, _friendly(e), error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _regenerate() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Make a new set of questions?'),
        content: const Text(
          'The current questions for this note will be removed and a new set will be made. You can do this up to 3 times for each note.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Back')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Make new set')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await _supabase.rpc('request_quiz_regeneration', params: {'p_note_id': widget.noteId});
      await _load();
      if (mounted) showDocSnack(context, 'A new set is being made. Check back in a minute.');
    } catch (e) {
      if (mounted) showDocSnack(context, _friendly(e), error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  // ===========================================================================
  // 🖼️ UI ONLY — presentation below. Loading, approve/remove/restore,
  // "approve all" and "make a new set" above are unchanged.
  // ===========================================================================
  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color primaryColor = Theme.of(context).primaryColor;
    final pending = _questions.where((q) => q['status'] == 'pending').length;
    final active = _questions.where((q) => q['status'] == 'active').length;
    final jobStatus = _job?['status']?.toString();

    return Scaffold(
      backgroundColor: PUi.bg(isDark),
      body: PBackdrop(
        accent: primaryColor,
        child: SafeArea(
          child: Column(
            children: [
              // ─── TOP BAR ───
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 20, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.maybePop(context),
                      style: IconButton.styleFrom(
                        backgroundColor: PUi.surface(isDark),
                        side: BorderSide(color: PUi.border(isDark)),
                        minimumSize: const Size(44, 44),
                      ),
                      icon: Icon(
                        Icons.arrow_back_rounded,
                        color: PUi.ink(isDark),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Quiz questions',
                        style: PUi.title(isDark, size: 24),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _loading
                    ? Center(child: TridetaLoader(color: primaryColor))
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          // Keeps the list a comfortable reading width on desktop
                          final double side = constraints.maxWidth > 800
                              ? (constraints.maxWidth - 760) / 2
                              : 20.0;
                          return RefreshIndicator(
                            onRefresh: _load,
                            color: primaryColor,
                            child: ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: EdgeInsets.fromLTRB(side, 16, side, 40),
                              children: [
                                Text(
                                  widget.title,
                                  style: TextStyle(
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w800,
                                    height: 1.35,
                                    color: PUi.ink(isDark),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                _statusCard(jobStatus, pending, active, isDark),
                                if (_questions.isNotEmpty && pending > 0) ...[
                                  const SizedBox(height: 14),
                                  FilledButton.icon(
                                    style: PUi.filledPill(
                                      primaryColor,
                                      height: 52,
                                    ),
                                    onPressed: _busy ? null : _approveAll,
                                    icon: const Icon(Icons.done_all_rounded),
                                    label: Text(
                                      'Approve all waiting ($pending)',
                                    ),
                                  ),
                                ],
                                if (_aiEnabled &&
                                    (jobStatus == 'done' ||
                                        jobStatus == 'failed')) ...[
                                  const SizedBox(height: 10),
                                  OutlinedButton.icon(
                                    style: PUi.outlinedPill(
                                      primaryColor,
                                      height: 52,
                                    ),
                                    onPressed: _busy ? null : _regenerate,
                                    icon: const Icon(Icons.autorenew_rounded),
                                    label: const Text('Make a new set'),
                                  ),
                                ],
                                const SizedBox(height: 18),
                                for (var i = 0; i < _questions.length; i++)
                                  _questionCard(i, _questions[i], isDark),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusCard(
    String? jobStatus,
    int pending,
    int active,
    bool isDark,
  ) {
    IconData icon = Icons.info_outline_rounded;
    Color color = PUi.muted(isDark);
    String text;

    if (_questions.isNotEmpty) {
      icon = Icons.quiz_rounded;
      color = Colors.indigo;
      text =
          '${_questions.length} questions. $active approved, $pending waiting for your review. Students will see only approved questions.';
    } else if (jobStatus == 'pending' || jobStatus == 'processing') {
      icon = Icons.hourglass_top_rounded;
      color = Colors.orange.shade800;
      text = 'The questions are being made. Pull down to refresh in a minute.';
    } else if (jobStatus == 'failed') {
      icon = Icons.error_outline_rounded;
      color = Colors.red.shade700;
      text =
          'The questions could not be made${(_job?['last_error'] ?? '').toString().isNotEmpty ? ': ${_job!['last_error']}' : '.'}';
    } else if (!_aiEnabled) {
      text =
          'AI quiz generation is switched off for your school. The admin can switch it on in Lesson Note Approvals.';
    } else {
      text = 'No questions yet for this note.';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PUi.tint(color, isDark, 0.08),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color,
                height: 1.45,
                fontWeight: FontWeight.w600,
                fontSize: 13.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _questionCard(int index, Map<String, dynamic> q, bool isDark) {
    final status = q['status'].toString();
    final options = List<String>.from(
      (q['options'] as List).map((o) => o.toString()),
    );
    final correct = (q['correct_index'] as num).toInt();
    final removed = status == 'removed';
    const letters = ['A', 'B', 'C', 'D'];

    return Opacity(
      opacity: removed ? 0.5 : 1,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: PCard(
          radius: 26,
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'QUESTION ${index + 1}',
                    style: PUi.sectionLabel(isDark),
                  ),
                  const Spacer(),
                  _chip(status),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                q['question'].toString(),
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800,
                  height: 1.4,
                  color: PUi.ink(isDark),
                ),
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < options.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        i == correct
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        size: 19,
                        color: i == correct
                            ? Colors.green.shade600
                            : PUi.muted(isDark),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${letters[i]}. ${options[i]}',
                          style: TextStyle(
                            color: i == correct
                                ? Colors.green.shade600
                                : PUi.ink(isDark),
                            fontWeight: i == correct
                                ? FontWeight.w800
                                : FontWeight.w500,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 10),
              Text(
                q['explanation'].toString(),
                style: TextStyle(
                  color: PUi.muted(isDark),
                  fontSize: 12.5,
                  fontStyle: FontStyle.italic,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 4,
                children: [
                  if (status != 'active' && !removed)
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        shape: const StadiumBorder(),
                      ),
                      onPressed: _busy
                          ? null
                          : () => _setStatus(q['id'] as String, 'active'),
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text('Approve'),
                    ),
                  if (!removed)
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        shape: const StadiumBorder(),
                      ),
                      onPressed: _busy
                          ? null
                          : () => _setStatus(q['id'] as String, 'removed'),
                      icon: Icon(
                        Icons.delete_outline_rounded,
                        size: 18,
                        color: Colors.red.shade700,
                      ),
                      label: Text(
                        'Remove',
                        style: TextStyle(color: Colors.red.shade700),
                      ),
                    )
                  else
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        shape: const StadiumBorder(),
                      ),
                      onPressed: _busy
                          ? null
                          : () => _setStatus(q['id'] as String, 'pending'),
                      icon: const Icon(Icons.undo_rounded, size: 18),
                      label: const Text('Restore'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String status) {
    late final Color color;
    late final String label;
    switch (status) {
      case 'active':
        color = Colors.green.shade700;
        label = 'Approved';
        break;
      case 'removed':
        color = Colors.red.shade700;
        label = 'Removed';
        break;
      default:
        color = Colors.orange.shade800;
        label = 'Waiting for review';
    }
    return PPill(text: label, color: color);
  }
}
