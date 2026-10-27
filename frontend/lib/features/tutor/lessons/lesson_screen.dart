import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/api/api_client.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/sage_mascot.dart';
import '../../chat/presentation/widgets/blocks/text_block.dart';
import '../../practice/questions/presentation/widgets/question_answer_input.dart';
import '../../account/ai_setup/ai_setup.dart';
import '../../research/go_deeper_screen.dart';

/// "Learn a topic" (2026-10-21): Sage teaches one topic in small steps, each
/// ending in a question that checks it landed, then a worked example and a
/// recap that becomes flashcards — see server/domains/tutor/router.py.
///
/// Opened with a topic or a concept, it starts writing the lesson at once;
/// with [lessonId] it resumes one; with neither it asks what to learn.
class LessonScreen extends StatefulWidget {
  const LessonScreen({
    super.key,
    required this.apiClient,
    this.topic,
    this.subjectSlug,
    this.conceptId,
    this.lessonId,
  });

  final ApiClient apiClient;
  final String? topic;
  final String? subjectSlug;
  final int? conceptId;
  final int? lessonId;

  @override
  State<LessonScreen> createState() => _LessonScreenState();
}

enum _Phase { choose, writing, step, example, recap, done }

class _LessonScreenState extends State<LessonScreen> {
  _Phase _phase = _Phase.choose;
  Map<String, dynamic>? _lesson;
  int _index = 0;
  String? _error;
  bool _busy = false;
  bool _solutionShown = false;
  int _flashcardsAdded = 0;

  final _topicController = TextEditingController();
  List<Map<String, dynamic>> _subjects = [];
  String? _subjectSlug;
  final Map<int, GlobalKey<QuestionAnswerInputState>> _answerKeys = {};

  static const _examples = ['Photosynthesis', 'Quadratic equations', 'Supply and demand', 'The water cycle', "Newton's laws"];

  List<Map<String, dynamic>> get _steps => (_lesson?['lesson_steps'] as List? ?? const []).cast<Map<String, dynamic>>();

  @override
  void initState() {
    super.initState();
    _subjectSlug = widget.subjectSlug;
    _topicController.text = widget.topic ?? '';
    if (widget.lessonId != null) {
      _resume(widget.lessonId!);
    } else if (widget.conceptId != null || (widget.topic ?? '').trim().isNotEmpty) {
      // After the first frame: _start may need to open the AI setup.
      WidgetsBinding.instance.addPostFrameCallback((_) => _start());
    } else {
      _loadSubjects();
    }
  }

  @override
  void dispose() {
    _topicController.dispose();
    super.dispose();
  }

  Future<void> _loadSubjects() async {
    try {
      final result = await widget.apiClient.listProjects();
      if (mounted) setState(() => _subjects = (result['projects'] as List).cast<Map<String, dynamic>>());
    } catch (_) {
      // Optional: without the list the lesson goes in "My lessons".
    }
  }

  Future<void> _start() async {
    final topic = _topicController.text.trim();
    if (topic.isEmpty && widget.conceptId == null) {
      setState(() => _error = 'Type what you want to learn.');
      return;
    }
    // A lesson is written by the student's AI: set it up first rather
    // than fail after "preparing your lesson…".
    if (!await AiSetup.ensure(context)) {
      if (mounted) {
        setState(() {
          _phase = _Phase.choose;
          _error = 'Lessons need an AI key — set one up, then start again.';
        });
        if (_subjects.isEmpty) _loadSubjects();
      }
      return;
    }
    setState(() {
      _phase = _Phase.writing;
      _error = null;
    });
    try {
      final lesson = await widget.apiClient.startLesson(
        topic: topic.isEmpty ? null : topic,
        subjectSlug: _subjectSlug,
        conceptId: widget.conceptId,
      );
      _show(lesson);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _phase = _Phase.choose;
          _error = e.message;
        });
        if (_subjects.isEmpty) _loadSubjects();
      }
    }
  }

  Future<void> _resume(int lessonId) async {
    setState(() => _phase = _Phase.writing);
    try {
      _show(await widget.apiClient.getLesson(lessonId));
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _phase = _Phase.choose;
          _error = e.message;
        });
      }
    }
  }

  /// Opens a lesson where the student left off: the first step whose
  /// question isn't answered yet.
  void _show(Map<String, dynamic> lesson) {
    if (!mounted) return;
    final steps = (lesson['lesson_steps'] as List).cast<Map<String, dynamic>>();
    final next = steps.indexWhere((s) => s['question'] != null && s['result'] == null);
    setState(() {
      _lesson = lesson;
      if (lesson['status'] == 'completed') {
        _phase = _Phase.done;
      } else if (next >= 0) {
        _index = next;
        _phase = _Phase.step;
      } else {
        _index = steps.length - 1;
        _phase = lesson['worked_example'] != null ? _Phase.example : _Phase.recap;
      }
    });
  }

  Future<void> _check() async {
    final answer = _answerKeys[_index]?.currentState?.currentAnswer;
    if (answer == null || (answer is String && answer.trim().isEmpty)) {
      setState(() => _error = 'Answer the question first.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.apiClient.answerLessonStep(_lesson!['id'] as int, _index, answer);
      setState(() {
        final step = _steps[_index];
        step['result'] = {'correct': result['correct'], 'answer': result['answer'], 'feedback': result['feedback']};
        step['why'] = result['why'];
        (step['question'] as Map<String, dynamic>)['correct_answer'] = result['correct_answer'];
        _lesson!.addAll((result['lesson'] as Map<String, dynamic>));
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _next() {
    setState(() {
      _error = null;
      if (_phase == _Phase.step && _index < _steps.length - 1) {
        _index++;
      } else if (_phase == _Phase.step && _lesson!['worked_example'] != null) {
        _phase = _Phase.example;
      } else {
        _phase = _Phase.recap;
      }
    });
  }

  Future<void> _finish() async {
    setState(() => _busy = true);
    try {
      final result = await widget.apiClient.completeLesson(_lesson!['id'] as int);
      setState(() {
        _flashcardsAdded = result['flashcards_added'] as int? ?? 0;
        _lesson!.addAll(result['lesson'] as Map<String, dynamic>);
        _phase = _Phase.done;
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _learnAnother() {
    setState(() {
      _lesson = null;
      _index = 0;
      _answerKeys.clear();
      _solutionShown = false;
      _topicController.clear();
      _phase = _Phase.choose;
    });
    if (_subjects.isEmpty) _loadSubjects();
  }

  @override
  Widget build(BuildContext context) {
    final title = _lesson?['title'] as String? ?? 'Learn a topic';
    return Scaffold(
      appBar: AppBar(title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: SafeArea(
        child: switch (_phase) {
          _Phase.choose => _buildChoose(context),
          _Phase.writing => _buildWriting(context),
          _Phase.step => _buildStep(context),
          _Phase.example => _buildExample(context),
          _Phase.recap => _buildRecap(context),
          _Phase.done => _buildDone(context),
        },
      ),
    );
  }

  Widget _buildChoose(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const AiSetupBanner(margin: EdgeInsets.only(bottom: 16)),
        const Center(child: SageMascot(size: 96, mood: SageMood.happy)),
        const SizedBox(height: 12),
        Text('What do you want to learn?', style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
        const SizedBox(height: 6),
        Text(
          "I'll teach it in a few short steps and check you've got each one. What you learn goes into your flashcards.",
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _topicController,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'A topic', hintText: 'e.g. how vaccines work', prefixIcon: Icon(Icons.school_outlined)),
          onSubmitted: (_) => _start(),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final example in _examples)
              ActionChip(label: Text(example), onPressed: () => setState(() => _topicController.text = example)),
          ],
        ),
        if (_subjects.isNotEmpty) ...[
          const SizedBox(height: 16),
          DropdownButtonFormField<String?>(
            initialValue: _subjectSlug,
            decoration: const InputDecoration(labelText: 'Subject', helperText: 'Uses that subject’s notes, and saves the flashcards there'),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('My lessons')),
              for (final subject in _subjects)
                DropdownMenuItem<String?>(value: subject['slug'] as String, child: Text(subject['display_name'] as String)),
            ],
            onChanged: (value) => setState(() => _subjectSlug = value),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
        const SizedBox(height: 20),
        GradientButton(label: 'Start the lesson', onPressed: _start),
      ],
    );
  }

  Widget _buildWriting(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SageMascot(size: 110, mood: SageMood.thinking),
            const SizedBox(height: 16),
            Text('Sage is preparing your lesson…', style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text('This takes about half a minute.', style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            const LinearProgressIndicator(),
          ],
        ),
      ),
    );
  }

  Widget _progress(BuildContext context, {required double value, required String label}) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(value: value, minHeight: 8, backgroundColor: theme.colorScheme.surfaceContainerHighest),
        ),
      ],
    );
  }

  Widget _buildStep(BuildContext context) {
    final theme = Theme.of(context);
    final step = _steps[_index];
    final question = step['question'] as Map<String, dynamic>?;
    final result = step['result'] as Map<String, dynamic>?;
    final key = _answerKeys.putIfAbsent(_index, () => GlobalKey<QuestionAnswerInputState>());
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _progress(context, value: (_index + 1) / (_steps.length + 1), label: 'Step ${_index + 1} of ${_steps.length}'),
        const SizedBox(height: 20),
        Text(step['heading'] as String, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 10),
        MarkdownLite(step['explanation'] as String),
        if (question != null) ...[
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.quiz_rounded, size: 20, color: StudyOsColors.primary),
                    const SizedBox(width: 8),
                    Text('Check yourself', style: theme.textTheme.titleSmall?.copyWith(color: StudyOsColors.primary)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(question['prompt'] as String, style: theme.textTheme.titleMedium),
                const SizedBox(height: 10),
                if (result == null) QuestionAnswerInput(key: key, question: question) else _buildResult(context, step),
              ],
            ),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
        const SizedBox(height: 20),
        if (question != null && result == null)
          GradientButton(label: 'Check my answer', isLoading: _busy, onPressed: _busy ? null : _check)
        else
          GradientButton(label: 'Continue', onPressed: _next),
      ],
    );
  }

  Widget _buildResult(BuildContext context, Map<String, dynamic> step) {
    final theme = Theme.of(context);
    final result = step['result'] as Map<String, dynamic>;
    final correct = result['correct'] == true;
    final color = correct ? StudyOsColors.success : theme.colorScheme.error;
    final correctAnswer = (step['question'] as Map)['correct_answer'];
    final feedback = result['feedback'] as String?;
    final why = step['why'] as String?;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Your answer: ${result['answer']}', style: theme.textTheme.bodyMedium),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(correct ? Icons.check_circle_rounded : Icons.cancel_rounded, color: color),
            const SizedBox(width: 8),
            Text(correct ? 'Got it!' : 'Not quite', style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 16)),
          ],
        ),
        if (!correct && correctAnswer != null) ...[
          const SizedBox(height: 6),
          Text('Answer: $correctAnswer', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
        ],
        if (why != null && why.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(why, style: theme.textTheme.bodyMedium),
        ] else if (feedback != null && feedback.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(feedback, style: theme.textTheme.bodyMedium),
        ],
      ],
    );
  }

  Widget _buildExample(BuildContext context) {
    final theme = Theme.of(context);
    final example = _lesson!['worked_example'] as Map<String, dynamic>;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _progress(context, value: _steps.length / (_steps.length + 1), label: 'Worked example'),
        const SizedBox(height: 20),
        Text('Try this one', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 10),
        MarkdownLite(example['problem'] as String),
        const SizedBox(height: 16),
        if (_solutionShown)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(16)),
            child: MarkdownLite(example['solution'] as String),
          )
        else
          OutlinedButton.icon(
            icon: const Icon(Icons.visibility_rounded),
            label: const Text('Think it through, then show the solution'),
            onPressed: () => setState(() => _solutionShown = true),
          ),
        const SizedBox(height: 20),
        GradientButton(label: 'Continue', onPressed: _next),
      ],
    );
  }

  Widget _buildRecap(BuildContext context) {
    final theme = Theme.of(context);
    final recap = (_lesson!['recap'] as List? ?? const []).cast<Map<String, dynamic>>();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _progress(context, value: 1, label: 'Recap'),
        const SizedBox(height: 20),
        Text('What to remember', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 12),
        for (final card in recap)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              title: Text(card['front'] as String, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(card['back'] as String),
            ),
          ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
        const SizedBox(height: 16),
        GradientButton(
          label: recap.isEmpty ? 'Finish' : 'Finish and save ${recap.length} flashcard${recap.length == 1 ? '' : 's'}',
          isLoading: _busy,
          onPressed: _busy ? null : _finish,
        ),
      ],
    );
  }

  Widget _buildDone(BuildContext context) {
    final theme = Theme.of(context);
    final checks = _lesson!['checks'] as int? ?? 0;
    final correct = _lesson!['correct'] as int? ?? 0;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Center(child: SageMascot(size: 120, mood: SageMood.cheer)),
        const SizedBox(height: 16),
        Text('Lesson complete!', style: theme.textTheme.headlineMedium, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(
          checks > 0 ? 'You got $correct of $checks checks right.' : 'Nice work.',
          style: theme.textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        if (_flashcardsAdded > 0) ...[
          const SizedBox(height: 6),
          Text(
            '$_flashcardsAdded flashcards added — they’ll come up in your reviews so you keep remembering this.',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 28),
        // After a lesson: real videos, books and papers to go further.
        OutlinedButton.icon(
          icon: const Icon(Icons.travel_explore_rounded),
          label: const Text('Go deeper: videos, books and papers'),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => GoDeeperScreen(
              apiClient: widget.apiClient,
              topic: _lesson!['topic'] as String? ?? _lesson!['title'] as String,
              context: _lesson!['title'] as String?,
            ),
          )),
        ),
        const SizedBox(height: 10),
        GradientButton(label: 'Learn another topic', onPressed: _learnAnother),
        const SizedBox(height: 10),
        OutlinedButton(onPressed: () => Navigator.of(context).maybePop(), child: const Text('Done')),
      ],
    );
  }
}
