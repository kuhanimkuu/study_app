import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../../core/api/api_client.dart';
import '../../../../core/storage/local_db.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/list_item_card.dart';
import '../../../chat/models/chat_message.dart';
import '../../../chat/presentation/widgets/message_bubble.dart';
import '../../../knowledge/notes/presentation/screens/notes_list_screen.dart';
import '../../../knowledge/search/presentation/screens/knowledge_search_screen.dart';
import '../../../learning/concepts/presentation/screens/concepts_list_screen.dart';
import '../../../practice/flashcards/presentation/screens/flashcards_list_screen.dart';

/// A single project ("notebook") — Sources (add material), Chat (query
/// that material), and Studio (generate study guides/flashcards/etc. over
/// it) tabs, mirroring the NotebookLM-style workspace this was modeled on.
///
/// Studio documents are real PDFs from document_generation/generate_docs
/// (reportlab), tracked per-project in db.py's generated_artifacts table
/// and rendered as an honest reference card (no inline PDF viewer — same
/// convention as chat's PdfBlockView) rather than a fake preview.
///
/// Chat here reuses the same ChatMessage/MessageBubble machinery as the
/// main ChatScreen, persisted to the same on-device LocalDb under a
/// project-namespaced session id (`project_<slug>`) — no schema change
/// needed, LocalDb already keys everything by an arbitrary session_id
/// string. Unlike the main chat, there's no BYOK model_config here:
/// `/api/ask/project` doesn't accept one, because this route returns
/// matching source chunks, not an LLM-synthesized answer — see
/// moderator/README.md's Notes for that scope boundary.
class ProjectWorkspaceScreen extends StatefulWidget {
  const ProjectWorkspaceScreen({super.key, required this.apiClient, required this.slug, required this.displayName});

  final ApiClient apiClient;
  final String slug;
  final String displayName;

  @override
  State<ProjectWorkspaceScreen> createState() => _ProjectWorkspaceScreenState();
}

class _ProjectWorkspaceScreenState extends State<ProjectWorkspaceScreen> {
  String get _sessionId => 'project_${widget.slug}';

  // --- Sources tab state ---
  final _materialController = TextEditingController();
  int? _chunkCount;
  bool _isAddingMaterial = false;
  String? _sourcesError;
  List<dynamic>? _materials;

  // --- Chat tab state ---
  final List<ChatMessage> _messages = [];
  final _chatController = TextEditingController();
  final _chatScrollController = ScrollController();
  bool _isAsking = false;

  // --- Studio tab state ---
  static const _docTypeLabels = {
    'study_guide': 'Study guide',
    'revision_notes': 'Revision notes',
    'summary': 'Summary',
    'formula_sheet': 'Formula sheet',
    'worksheet': 'Worksheet',
    'flashcards': 'Flashcards',
    'practice_exam': 'Practice exam',
    'lab_report': 'Lab report',
  };
  String _selectedDocType = 'study_guide';
  List<dynamic>? _artifacts;
  bool _isGenerating = false;
  String? _studioError;

  @override
  void initState() {
    super.initState();
    _loadChunkCount();
    _loadMaterials();
    _loadChatHistory();
    _loadArtifacts();
  }

  Future<void> _loadMaterials() async {
    try {
      final result = await widget.apiClient.listMaterials(widget.slug);
      if (mounted) setState(() => _materials = result['materials'] as List<dynamic>);
    } catch (_) {
      // non-critical — Sources tab just won't show upload history yet
    }
  }

  Future<void> _loadArtifacts() async {
    try {
      final result = await widget.apiClient.listStudioDocs(widget.slug);
      if (mounted) setState(() => _artifacts = result['artifacts'] as List<dynamic>);
    } catch (_) {
      // non-critical — Studio tab just starts with an empty list
    }
  }

  Future<void> _generateStudioDoc() async {
    setState(() {
      _isGenerating = true;
      _studioError = null;
    });
    try {
      await widget.apiClient.generateStudioDoc(slug: widget.slug, docType: _selectedDocType);
      await _loadArtifacts();
    } on ApiException catch (e) {
      setState(() => _studioError = e.message);
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  Future<void> _deleteArtifact(int id) async {
    try {
      await widget.apiClient.deleteStudioDoc(slug: widget.slug, artifactId: id);
      await _loadArtifacts();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _loadChunkCount() async {
    try {
      final result = await widget.apiClient.listProjects();
      final projects = result['projects'] as List<dynamic>;
      final mine = projects.cast<Map<String, dynamic>>().where((p) => p['slug'] == widget.slug);
      if (mine.isNotEmpty && mounted) setState(() => _chunkCount = mine.first['chunk_count'] as int?);
    } catch (_) {
      // non-critical — Sources tab just won't show a count yet
    }
  }

  Future<void> _loadChatHistory() async {
    final rows = await LocalDb.instance.loadMessages(sessionId: _sessionId);
    final restored = ChatMessage.fromStoredRows(rows);
    if (mounted) setState(() => _messages.addAll(restored));
  }

  Future<void> _addText() async {
    final text = _materialController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _isAddingMaterial = true;
      _sourcesError = null;
    });
    try {
      final result = await widget.apiClient.addProjectMaterial(slug: widget.slug, text: text);
      _materialController.clear();
      setState(() => _chunkCount = result['chunks'] as int?);
      await _loadMaterials();
    } on ApiException catch (e) {
      setState(() => _sourcesError = e.message);
    } finally {
      if (mounted) setState(() => _isAddingMaterial = false);
    }
  }

  Future<void> _uploadFile() async {
    final result = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'txt'], withData: true);
    final file = result?.files.single;
    if (file == null || file.bytes == null) return;

    setState(() {
      _isAddingMaterial = true;
      _sourcesError = null;
    });
    try {
      final response = await widget.apiClient.addProjectMaterial(
        slug: widget.slug,
        fileBytes: file.bytes,
        filename: file.name,
      );
      setState(() => _chunkCount = response['chunks'] as int?);
      await _loadMaterials();
    } on ApiException catch (e) {
      setState(() => _sourcesError = e.message);
    } finally {
      if (mounted) setState(() => _isAddingMaterial = false);
    }
  }

  void _scrollChatToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendQuery() async {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;
    _chatController.clear();
    setState(() => _messages.add(ChatMessage.user(text)));
    await LocalDb.instance.saveMessage(sessionId: _sessionId, role: 'user', userText: text);
    _scrollChatToBottom();

    setState(() => _isAsking = true);
    try {
      final result = await widget.apiClient.askProject(project: widget.slug, query: text, sessionId: _sessionId);
      final blocks = result['blocks'] as List<dynamic>? ?? [];
      final activity = result['activity'] as Map<String, dynamic>?;
      setState(() => _messages.add(ChatMessage.response(blocks, activity: activity)));
      await LocalDb.instance.saveMessage(sessionId: _sessionId, role: 'response', blocks: blocks);
      if (activity != null) {
        await LocalDb.instance.saveActivity(
          topic: activity['topic'] as String?,
          event: activity['event'] as String?,
          engine: activity['engine'] as String?,
          labels: (activity['labels'] as List<dynamic>? ?? []).map((e) => e.toString()).toList(),
          timestamp: DateTime.now().toUtc().toIso8601String(),
        );
      }
    } on ApiException catch (e) {
      setState(() => _messages.add(ChatMessage.error(e.message)));
      await LocalDb.instance.saveMessage(sessionId: _sessionId, role: 'error', errorText: e.message);
    } catch (e) {
      setState(() => _messages.add(ChatMessage.error(e.toString())));
      await LocalDb.instance.saveMessage(sessionId: _sessionId, role: 'error', errorText: e.toString());
    } finally {
      setState(() => _isAsking = false);
      _scrollChatToBottom();
    }
  }

  /// Same temporary self-report mechanism as the main ChatScreen — see
  /// that screen's `_markStillStuck` doc comment for why it exists.
  Future<void> _markStillStuck(ChatMessage message) async {
    final activity = message.activity;
    if (activity == null || message.struggleMarked) return;
    final labels = (activity['labels'] as List<dynamic>? ?? []).map((e) => e.toString()).toSet();
    labels.add('struggle');
    await LocalDb.instance.saveActivity(
      topic: activity['topic'] as String?,
      event: activity['event'] as String?,
      engine: activity['engine'] as String?,
      labels: labels.toList(),
      score: 0.3,
      timestamp: DateTime.now().toUtc().toIso8601String(),
    );
    setState(() => message.struggleMarked = true);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 7,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.displayName),
          bottom: TabBar(
            isScrollable: true,
            tabs: const [
              Tab(text: 'Sources'),
              Tab(text: 'Chat'),
              Tab(text: 'Studio'),
              Tab(text: 'Concepts'),
              Tab(text: 'Flashcards'),
              Tab(text: 'Notes'),
              Tab(text: 'Search'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildSourcesTab(context),
            _buildChatTab(context),
            _buildStudioTab(context),
            _buildConceptsTab(context),
            _buildFlashcardsTab(context),
            _buildNotesTab(context),
            _buildSearchTab(context),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchTab(BuildContext context) {
    return KnowledgeSearchScreen(apiClient: widget.apiClient, slug: widget.slug);
  }

  Widget _buildConceptsTab(BuildContext context) {
    return ConceptsListScreen(apiClient: widget.apiClient, slug: widget.slug);
  }

  Widget _buildFlashcardsTab(BuildContext context) {
    return FlashcardsListScreen(apiClient: widget.apiClient, slug: widget.slug);
  }

  Widget _buildNotesTab(BuildContext context) {
    return NotesListScreen(apiClient: widget.apiClient, slug: widget.slug);
  }

  Widget _buildSourcesTab(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          _chunkCount == null
              ? 'Loading...'
              : _chunkCount == 0
                  ? 'No material yet — add some below.'
                  : '$_chunkCount stored chunk(s).',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _materialController,
          maxLines: 6,
          decoration: const InputDecoration(labelText: 'Paste text to add'),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _isAddingMaterial ? null : _addText,
          icon: const Icon(Icons.note_add_outlined, size: 18),
          label: const Text('Add text'),
        ),
        const Divider(height: 32),
        OutlinedButton.icon(
          onPressed: _isAddingMaterial ? null : _uploadFile,
          icon: const Icon(Icons.upload_file_outlined),
          label: const Text('Upload a PDF or .txt file'),
        ),
        if (_isAddingMaterial) ...[
          const SizedBox(height: 16),
          const LinearProgressIndicator(minHeight: 2),
        ],
        if (_sourcesError != null) ...[
          const SizedBox(height: 12),
          Text(_sourcesError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        const Divider(height: 32),
        Text('Uploaded material', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        if (_materials == null)
          const SizedBox.shrink()
        else if (_materials!.isEmpty)
          Row(
            children: [
              Icon(Icons.description_outlined, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
              const SizedBox(width: 8),
              Text(
                'Nothing uploaded yet.',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          )
        else
          ..._materials!.map((raw) {
            final material = raw as Map<String, dynamic>;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ListItemCard(
                icon: Icons.description_outlined,
                title: material['filename'] as String,
                subtitle: '${material['mime_type']} · ${material['created_at']}',
              ),
            );
          }),
      ],
    );
  }

  Widget _buildChatTab(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: _messages.isEmpty
              ? const EmptyState(icon: Icons.chat_outlined, message: 'Ask a question about this project\'s material.')
              : ListView.builder(
                  controller: _chatScrollController,
                  padding: const EdgeInsets.all(12),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) => MessageBubble(
                    message: _messages[index],
                    baseUrl: widget.apiClient.baseUrl,
                    onStillStuck: () => _markStillStuck(_messages[index]),
                  ),
                ),
        ),
        if (_isAsking) const LinearProgressIndicator(minHeight: 2),
        // SafeArea here (unlike the main ChatScreen, which gets this for
        // free from the shared ChatInputBar widget — see that widget's
        // own SafeArea) — without it this bar sits flush against the
        // bottom of the screen and gets obscured by the Android
        // navigation bar. Found via real device testing.
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 44),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Theme.of(context).colorScheme.outline),
                    ),
                    child: TextField(
                      controller: _chatController,
                      decoration: const InputDecoration(
                        hintText: 'Ask about this project...',
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        contentPadding: EdgeInsets.symmetric(vertical: 12),
                      ),
                      onSubmitted: (_) => _sendQuery(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: const BoxDecoration(gradient: StudyOsColors.brandGradient, shape: BoxShape.circle),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_upward_rounded, color: Colors.white),
                    onPressed: _sendQuery,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStudioTab(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _selectedDocType,
                  decoration: const InputDecoration(labelText: 'Document type'),
                  items: [
                    for (final entry in _docTypeLabels.entries)
                      DropdownMenuItem(value: entry.key, child: Text(entry.value)),
                  ],
                  onChanged: (value) => setState(() => _selectedDocType = value ?? _selectedDocType),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _isGenerating ? null : _generateStudioDoc,
                icon: _isGenerating
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.auto_awesome_rounded, size: 18),
                label: const Text('Generate'),
              ),
            ],
          ),
        ),
        if (_studioError != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(_studioError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        const Divider(height: 1),
        Expanded(
          child: (_artifacts == null || _artifacts!.isEmpty)
              ? const EmptyState(icon: Icons.auto_awesome_outlined, message: 'No generated documents yet.')
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _artifacts!.length,
                  itemBuilder: (context, index) {
                    final artifact = _artifacts![index] as Map<String, dynamic>;
                    final docType = artifact['doc_type'] as String;
                    final url = artifact['url'] as String;
                    return ListItemCard(
                      icon: Icons.picture_as_pdf_outlined,
                      iconColor: Theme.of(context).colorScheme.secondary,
                      title: artifact['title'] as String? ?? _docTypeLabels[docType] ?? docType,
                      subtitle: '${widget.apiClient.baseUrl}$url · no inline viewer yet, file is real and downloadable',
                      subtitleMaxLines: 2,
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _deleteArtifact(artifact['id'] as int),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
