import 'package:flutter/material.dart';

import '../../../../../app/theme.dart';
import '../../../../../core/api/api_client.dart';
import '../../../../../core/errors/error_presentation.dart';
import '../../../../../core/utils/relative_time.dart';
import '../../../../../core/widgets/tab_kit.dart';
import 'note_editor_screen.dart';

/// Student-authored notes within a Knowledge Space (blueprint Section 14)
/// — a new 6th tab on ProjectWorkspaceScreen.
class NotesListScreen extends StatefulWidget {
  const NotesListScreen({super.key, required this.apiClient, required this.slug});

  final ApiClient apiClient;
  final String slug;

  @override
  State<NotesListScreen> createState() => _NotesListScreenState();
}

class _NotesListScreenState extends State<NotesListScreen> {
  List<Map<String, dynamic>>? _notes;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final result = await widget.apiClient.listNotes(widget.slug);
      setState(() => _notes = (result['notes'] as List<dynamic>).cast<Map<String, dynamic>>());
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _createNote() async {
    try {
      final created = await widget.apiClient.createNote(slug: widget.slug, title: 'Untitled note');
      await _load();
      if (mounted) await _openNote(created);
    } on ApiException catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _openNote(Map<String, dynamic> note) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => NoteEditorScreen(apiClient: widget.apiClient, note: note)),
    );
    _load();
  }

  Future<void> _deleteNote(int id) async {
    try {
      await widget.apiClient.deleteNote(id);
      await _load();
    } on ApiException catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  // Sticky-note colours, picked by note id so a note keeps its colour.
  static const _paper = [
    (light: Color(0xFFFFF4C2), dark: Color(0xFF3A3315), accent: Color(0xFFE0A800)),
    (light: Color(0xFFFFE1EC), dark: Color(0xFF3B1A28), accent: Color(0xFFE2457A)),
    (light: Color(0xFFDDF4FF), dark: Color(0xFF13303D), accent: Color(0xFF0E8AC7)),
    (light: Color(0xFFE3F8E6), dark: Color(0xFF173320), accent: Color(0xFF16A34A)),
    (light: Color(0xFFEDE7FF), dark: Color(0xFF261F45), accent: Color(0xFF8B5CF6)),
    (light: Color(0xFFFFEAD9), dark: Color(0xFF3A2414), accent: Color(0xFFFF8A00)),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final notes = _notes ?? const <Map<String, dynamic>>[];
    final words = notes.fold<int>(0, (sum, n) => sum + _wordCount(n['body'] as String? ?? ''));
    // Most recently edited first.
    final sorted = [...notes]..sort((a, b) => (b['updated_at'] as String? ?? '').compareTo(a['updated_at'] as String? ?? ''));

    Widget body;
    if (_isLoading && _notes == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = ListView(
        padding: const EdgeInsets.all(16),
        children: [Text(_error!, style: TextStyle(color: theme.colorScheme.error))],
      );
    } else {
      body = CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const TabIntro(title: 'Notes', subtitle: 'Your own words. Writing it down is half of learning it.'),
                  if (notes.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        StatChip(icon: Icons.sticky_note_2_rounded, value: '${notes.length}', label: notes.length == 1 ? 'note' : 'notes', color: const Color(0xFFE0A800)),
                        StatChip(icon: Icons.edit_rounded, value: '$words', label: words == 1 ? 'word' : 'words', color: StudyOsColors.primary),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (notes.isEmpty)
            SliverToBoxAdapter(child: _emptyNotes(context))
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 240,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.82,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) => _noteCard(context, sorted[i]),
                  childCount: sorted.length,
                ),
              ),
            ),
        ],
      );
    }

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createNote,
        icon: const Icon(Icons.edit_note_rounded),
        label: const Text('New note'),
      ),
      body: RefreshIndicator(onRefresh: _load, child: body),
    );
  }

  static int _wordCount(String body) => body.trim().isEmpty ? 0 : body.trim().split(RegExp(r'\s+')).length;

  Widget _emptyNotes(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 96),
      child: Column(
        children: [
          Transform.rotate(
            angle: -0.06,
            child: Container(
              width: 120,
              height: 110,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.brightness == Brightness.dark ? _paper[0].dark : _paper[0].light,
                borderRadius: BorderRadius.circular(6),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 10, offset: const Offset(2, 5))],
              ),
              child: Icon(Icons.edit_rounded, size: 34, color: _paper[0].accent),
            ),
          ),
          const SizedBox(height: 18),
          Text('No notes yet', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
            'Jot down what you learned, a summary in your own words, or questions to ask Sage later.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _noteCard(BuildContext context, Map<String, dynamic> note) {
    final theme = Theme.of(context);
    final paper = _paper[(note['id'] as int) % _paper.length];
    final dark = theme.brightness == Brightness.dark;
    final body = (note['body'] as String? ?? '').trim();
    final words = _wordCount(body);
    final title = (note['title'] as String? ?? '').trim();
    return Material(
      color: dark ? paper.dark : paper.light,
      borderRadius: BorderRadius.circular(16),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openNote(note),
        onLongPress: () => _confirmDelete(note),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      title.isEmpty ? 'Untitled note' : title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  SizedBox(
                    width: 30,
                    height: 30,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      iconSize: 18,
                      icon: Icon(Icons.more_vert_rounded, color: theme.colorScheme.onSurfaceVariant),
                      tooltip: 'Delete note',
                      onPressed: () => _confirmDelete(note),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    body.isEmpty ? 'Empty, tap to write.' : body,
                    overflow: TextOverflow.fade,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: body.isEmpty ? 0.45 : 0.75),
                      fontStyle: body.isEmpty ? FontStyle.italic : null,
                      height: 1.35,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: paper.accent, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '$words ${words == 1 ? 'word' : 'words'} · ${relativeTime(note['updated_at'] as String?)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(Map<String, dynamic> note) async {
    final title = (note['title'] as String? ?? '').trim();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this note?'),
        content: Text('"${title.isEmpty ? 'Untitled note' : title}" will be gone for good.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed == true) await _deleteNote(note['id'] as int);
  }
}
