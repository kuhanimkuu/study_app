import 'dart:math';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/api/api_client.dart';
import '../../../../core/auth/auth_service.dart';
import '../../../../core/crypto/user_crypto.dart';
import '../../../../core/storage/local_db.dart';
import '../../../projects/presentation/screens/project_workspace_screen.dart';
import '../../models/chat_message.dart';
import '../widgets/attachment_menu_sheet.dart';
import '../widgets/chat_input_bar.dart';
import '../widgets/chat_sessions_drawer.dart';
import '../widgets/message_bubble.dart';
import '../widgets/pending_pdf_chip.dart';
import '../widgets/server_settings_dialog.dart';
import '../widgets/web_url_dialog.dart';

/// The main chat screen — a single thread that accepts text plus four
/// attachment types (image/PDF/audio/web), all funneled through server/'s
/// /api/ask/* endpoints. Owns state and orchestration only; every piece of
/// UI below the AppBar is its own widget under presentation/widgets/
/// (message bubbles, the attachment sheet, both dialogs, the pending-PDF
/// chip, the input bar) — this file should stay about "what happens", not
/// "what it looks like".
///
/// Takes the app's one shared [AuthService] (for the ApiClient, the
/// per-user encryption key, and BYOK settings) rather than creating its
/// own — it must be the same ApiClient instance AuthService attached the
/// login token to, or every request here would come back 401.
///
/// Local-first pivot (see server/main.py's architecture note): every
/// message and every response's suggested "activity" is written to
/// LocalDb, not the server. Every text ask also sends the device's own
/// activity log as `local_events` (cheap — LocalDb caps it at 500 rows)
/// so the moderator's memory_query route can answer "what did I struggle
/// with" without the server ever storing it, and a BYOK API key (if set)
/// is encrypted with this user's own key right before the one request
/// that needs it, never persisted anywhere but the OS keystore.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.authService});

  final AuthService authService;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<ChatMessage> _messages = [];
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String _sessionId = _randomSessionId();
  ApiClient get _api => widget.authService.apiClient;
  bool _isLoading = false;

  /// Past general-chat sessions for the sidebar (see ChatSessionsDrawer) —
  /// refreshed whenever the drawer opens, not kept continuously in sync,
  /// since it only needs to be current at the moment it's shown.
  List<Map<String, dynamic>> _sessions = [];

  /// Set right after a PDF upload gets back a clarification — while set,
  /// the next typed message is routed as a query against that PDF
  /// (/api/ask/pdf) instead of a fresh text question (/api/ask/text).
  /// See server/README.md's "/api/ask/pdf's two-call flow" note; this is
  /// the client-side half of that same real, tested flow.
  String? _pendingPdfName;
  bool _pendingPdfUploadJustHappened = false;

  @override
  void initState() {
    super.initState();
    _resumeMostRecentSession();
  }

  static String _randomSessionId() {
    final rand = Random();
    return List.generate(12, (_) => rand.nextInt(36).toRadixString(36)).join();
  }

  /// Reopening the Chat tab should land back where you left off, not lose
  /// the current conversation — so unlike ProjectWorkspaceScreen (which
  /// always resumes one fixed session per project), this picks up the
  /// most recently active general-chat session, if any, on first build.
  /// "New chat" (in the sidebar) is the explicit way to start fresh.
  Future<void> _resumeMostRecentSession() async {
    final sessions = await LocalDb.instance.loadSessions();
    if (sessions.isNotEmpty) {
      await _switchSession(sessions.first['session_id'] as String);
    }
    if (mounted) setState(() => _sessions = sessions);
  }

  Future<void> _refreshSessions() async {
    final sessions = await LocalDb.instance.loadSessions();
    if (mounted) setState(() => _sessions = sessions);
  }

  Future<void> _switchSession(String sessionId) async {
    final rows = await LocalDb.instance.loadMessages(sessionId: sessionId);
    final restored = ChatMessage.fromStoredRows(rows);
    setState(() {
      _sessionId = sessionId;
      _messages
        ..clear()
        ..addAll(restored);
      _pendingPdfName = null;
    });
    _scrollToBottom();
  }

  void _startNewChat() {
    setState(() {
      _sessionId = _randomSessionId();
      _messages.clear();
      _pendingPdfName = null;
    });
  }

  Future<void> _deleteSession(String sessionId) async {
    await LocalDb.instance.deleteSession(sessionId);
    if (sessionId == _sessionId) _startNewChat();
    await _refreshSessions();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// Builds the per-request BYOK config, encrypting the stored API key
  /// with this user's own encryption_key right before sending — see
  /// UserCrypto and routers/ask.py's ModelConfig. Returns null for the
  /// local backend (the server's default, no config needed).
  Future<Map<String, dynamic>?> _modelConfigForRequest() async {
    final settings = widget.authService.modelSettings;
    if (settings.backend == 'local' || !settings.hasApiKey) return null;
    final key = widget.authService.encryptionKey;
    if (key == null) return null;
    final encryptedKey = await UserCrypto.encryptForUser(key, settings.apiKey!);
    return {
      'backend': settings.backend,
      if (settings.modelName != null) 'model_name': settings.modelName,
      'encrypted_api_key': encryptedKey,
    };
  }

  Future<void> _persistActivity(Map<String, dynamic>? activity) async {
    if (activity == null) return;
    await LocalDb.instance.saveActivity(
      topic: activity['topic'] as String?,
      event: activity['event'] as String?,
      engine: activity['engine'] as String?,
      labels: (activity['labels'] as List<dynamic>? ?? []).map((e) => e.toString()).toList(),
      timestamp: DateTime.now().toUtc().toIso8601String(),
    );
  }

  /// TEMPORARY substitute for real struggle detection. There's no
  /// auto-grading/quiz engine in this project that could derive a genuine
  /// "the user is struggling with X" signal from an answer, and nothing
  /// in the moderator infers it from conversation shape either — so
  /// without this, History's "struggling with" section would just always
  /// be empty. The real version of this is the moderator recognizing
  /// struggle from an actual back-and-forth (repeated clarifications,
  /// rephrased questions, follow-ups circling the same topic) across a
  /// session — not implemented yet. Until then, the only honest signal is
  /// the user saying so directly.
  ///
  /// Writes an ADDITIONAL activity event rather than mutating the one
  /// already saved for this response — activity_events is an append-only
  /// log everywhere else in this app, and this keeps that invariant.
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

  Future<void> _handleResult(Future<Map<String, dynamic>> Function() call) async {
    setState(() => _isLoading = true);
    try {
      final result = await call();
      final blocks = result['blocks'] as List<dynamic>? ?? [];
      // If the moderator just asked a PDF-scope clarification, arm the
      // "next message is a PDF query" state. Any other clarification
      // (e.g. the ambiguous-math case) is left alone — the moderator's own
      // clarification-reply resume logic already handles that via task
      // inference on the next /api/ask/text call.
      if (_pendingPdfUploadJustHappened && blocks.any((b) => b['type'] == 'clarification')) {
        // _pendingPdfName was already set by the caller before this ran.
      } else if (blocks.isNotEmpty && !blocks.any((b) => b['type'] == 'clarification')) {
        _pendingPdfName = null;
      }
      final activity = result['activity'] as Map<String, dynamic>?;
      setState(() => _messages.add(ChatMessage.response(blocks, activity: activity)));
      await LocalDb.instance.saveMessage(sessionId: _sessionId, role: 'response', blocks: blocks);
      await _persistActivity(activity);
    } on ApiException catch (e) {
      setState(() => _messages.add(ChatMessage.error(e.message)));
      await LocalDb.instance.saveMessage(sessionId: _sessionId, role: 'error', errorText: e.message);
    } catch (e) {
      setState(() => _messages.add(ChatMessage.error(e.toString())));
      await LocalDb.instance.saveMessage(sessionId: _sessionId, role: 'error', errorText: e.toString());
    } finally {
      setState(() => _isLoading = false);
      _scrollToBottom();
    }
  }

  Future<void> _addUserMessage(String text) async {
    setState(() => _messages.add(ChatMessage.user(text)));
    _scrollToBottom();
    await LocalDb.instance.saveMessage(sessionId: _sessionId, role: 'user', userText: text);
  }

  Future<void> _sendText() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    _textController.clear();
    await _addUserMessage(text);

    if (_pendingPdfName != null) {
      await _handleResult(() => _api.askPdf(query: text, sessionId: _sessionId));
      // clear only if the moderator didn't ask another PDF-scope question
      if (_messages.isNotEmpty) {
        final last = _messages.last;
        final stillAsking = last.blocks?.any((b) => b['type'] == 'clarification') ?? false;
        if (!stillAsking) _pendingPdfName = null;
      }
      setState(() {}); // refresh the "asking about <pdf>" chip state
      return;
    }

    final modelConfig = await _modelConfigForRequest();
    final localEvents = await LocalDb.instance.loadActivityForQuery();
    await _handleResult(() => _api.askText(
          content: text,
          sessionId: _sessionId,
          modelConfig: modelConfig,
          localEvents: localEvents,
        ));
  }

  Future<void> _pickAndSendImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    await _addUserMessage('[image: ${picked.name}]');
    await _handleResult(() => _api.askImage(bytes: bytes, filename: picked.name, sessionId: _sessionId));
  }

  Future<void> _pickAndSendPdf() async {
    final result = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['pdf'], withData: true);
    final file = result?.files.single;
    if (file == null || file.bytes == null) return;
    await _addUserMessage('[pdf: ${file.name}]');
    _pendingPdfUploadJustHappened = true;
    _pendingPdfName = file.name;
    await _handleResult(() => _api.askPdf(bytes: file.bytes, filename: file.name, sessionId: _sessionId));
    _pendingPdfUploadJustHappened = false;
    setState(() {});
  }

  Future<void> _pickAndSendAudio() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['wav', 'mp3', 'm4a', 'ogg'],
      withData: true,
    );
    final file = result?.files.single;
    if (file == null || file.bytes == null) return;
    await _addUserMessage('[audio: ${file.name}]');
    await _handleResult(() => _api.askAudio(bytes: file.bytes!, filename: file.name, sessionId: _sessionId));
  }

  Future<void> _promptForUrl() async {
    final url = await showWebUrlDialog(context);
    if (url == null || url.isEmpty) return;
    await _addUserMessage('[web: $url]');
    await _handleResult(() => _api.askWeb(url: url, sessionId: _sessionId));
  }

  void _openAttachmentMenu() {
    showAttachmentMenu(
      context,
      onImage: _pickAndSendImage,
      onPdf: _pickAndSendPdf,
      onAudio: _pickAndSendAudio,
      onWeb: _promptForUrl,
    );
  }

  String _suggestedProjectName() {
    final firstUser = _messages.where((m) => m.isUser).firstOrNull;
    final text = firstUser?.userText?.trim() ?? '';
    if (text.isEmpty) return 'New project';
    return text.length > 40 ? '${text.substring(0, 40)}...' : text;
  }

  /// Compiles this session's Q&A into one text blob for rag/projects —
  /// server-side chunking (rag/indexing's sliding window, see that
  /// engine's module docstring) splits it back into searchable pieces, so
  /// there's no need to pre-chunk per-message here. Only `text`/`source`
  /// block content is included; block types like `equation`/`graph`/
  /// `static_image` don't carry meaningful standalone text to index.
  String _compileChatMaterial() {
    final buffer = StringBuffer();
    for (final message in _messages) {
      if (message.isUser) {
        if ((message.userText ?? '').isNotEmpty) buffer.writeln('Q: ${message.userText}');
        continue;
      }
      final blocks = message.blocks;
      if (blocks == null) continue;
      final texts = <String>[];
      for (final block in blocks) {
        final b = block as Map<String, dynamic>;
        if (b['type'] == 'text' || b['type'] == 'source') {
          final content = b['content']?.toString();
          if (content != null && content.isNotEmpty) texts.add(content);
        }
      }
      if (texts.isNotEmpty) buffer.writeln('A: ${texts.join(' ')}');
    }
    return buffer.toString();
  }

  /// Spins off a new project seeded with this chat's content — reuses the
  /// same create-project/add-material calls the Projects screen uses, so
  /// no new backend endpoint was needed for this. Non-destructive: the
  /// original chat session is left exactly as-is, this just creates a
  /// separate project alongside it.
  Future<void> _convertToProject() async {
    if (_messages.isEmpty) return;

    final controller = TextEditingController(text: _suggestedProjectName());
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Convert to project'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Project name'),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(controller.text), child: const Text('Create')),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;

    final material = _compileChatMaterial();
    if (material.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Nothing in this chat to convert yet.')));
      }
      return;
    }

    try {
      final project = await _api.createProject(displayName: name.trim());
      final slug = project['slug'] as String;
      await _api.addProjectMaterial(slug: slug, text: material);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Converted to project "${project['display_name']}".')));
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => ProjectWorkspaceScreen(
            apiClient: _api,
            slug: slug,
            displayName: project['display_name'] as String,
          ),
        ),
      );
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _openSettings() async {
    final newUrl = await showServerSettingsDialog(context, _api.baseUrl);
    if (newUrl == null || newUrl.isEmpty) return;
    // Mutates the shared instance in place — every screen holding a
    // reference to the same ApiClient (History, Account) picks this up
    // too, no re-plumbing needed. See ApiClient.baseUrl's doc comment.
    setState(() => _api.baseUrl = newUrl);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Study OS'),
        actions: [
          IconButton(
            icon: const Icon(Icons.create_new_folder_outlined),
            tooltip: 'Convert to project',
            onPressed: _messages.isEmpty ? null : _convertToProject,
          ),
          IconButton(icon: const Icon(Icons.settings_outlined), onPressed: _openSettings, tooltip: _api.baseUrl),
        ],
      ),
      drawer: ChatSessionsDrawer(
        sessions: _sessions,
        currentSessionId: _sessionId,
        onSelectSession: _switchSession,
        onNewChat: _startNewChat,
        onDeleteSession: _deleteSession,
      ),
      onDrawerChanged: (isOpen) {
        if (isOpen) _refreshSessions();
      },
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length,
              itemBuilder: (context, index) => MessageBubble(
                message: _messages[index],
                baseUrl: _api.baseUrl,
                onStillStuck: () => _markStillStuck(_messages[index]),
              ),
            ),
          ),
          if (_isLoading) const LinearProgressIndicator(minHeight: 2),
          if (_pendingPdfName != null)
            PendingPdfChip(
              filename: _pendingPdfName!,
              onDismiss: () => setState(() => _pendingPdfName = null),
            ),
          ChatInputBar(controller: _textController, onSend: _sendText, onAttachmentTap: _openAttachmentMenu),
        ],
      ),
    );
  }
}
