import 'dart:convert';
import 'package:http/http.dart' as http;

/// Thin wrapper around Study OS's HTTP server (see ../../server/README.md
/// for the endpoint contracts). Shared across every feature (chat, auth,
/// account) — moved out of features/chat/ once auth/account also needed
/// the same base client with the same token handling. There is
/// deliberately no history endpoint here — chat history lives on the
/// device (see LocalDb), not the server.
///
/// Every method returns the raw decoded JSON body, or throws
/// [ApiException] on a non-2xx response.
///
/// Uses bytes (not file paths) for uploads throughout — file_picker/
/// image_picker return paths that don't exist on web (no real filesystem
/// there), so bytes is the one approach that works on every target
/// platform this project builds for (Android, Windows, web).
class ApiClient {
  ApiClient({required this.baseUrl, this.token});

  /// Applied to every request below. Without this, a dropped connection
  /// (a killed adb reverse tunnel, a server restart mid-request, a dead
  /// Wi-Fi hop) leaves the awaiting Future — and everything downstream of
  /// it, including AuthGate's startup spinner — hanging forever with no
  /// way to recover short of force-closing the app. Generous on purpose:
  /// the local LLM's CPU-bound generation for a conversational reply can
  /// genuinely take tens of seconds, and this needs to outlast that, not
  /// just a fast JSON round-trip.
  static const _requestTimeout = Duration(seconds: 60);

  Never _timeoutError() => throw ApiException(0, 'Request timed out — check the server is reachable.');

  /// Mutable (not final) — the settings screen edits this in place on the
  /// one shared instance every screen holds, so a URL change takes effect
  /// everywhere without re-plumbing a new instance through the app.
  String baseUrl;

  /// The current user's JWT (see server/security.py) — null before
  /// login/signup. Every /api/ask/* and /api/account call requires this;
  /// /api/auth/* and /api/health don't.
  String? token;

  Map<String, String> get _authHeaders => {
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Map<String, String> get _jsonHeaders => {
        'Content-Type': 'application/json',
        ..._authHeaders,
      };

  Future<Map<String, dynamic>> health() async {
    final res = await http.get(Uri.parse('$baseUrl/api/health')).timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  // --- auth ---

  Future<Map<String, dynamic>> signup({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final res = await http
        .post(
          Uri.parse('$baseUrl/api/auth/signup'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': email,
            'password': password,
            if (displayName != null) 'display_name': displayName,
          }),
        )
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  Future<Map<String, dynamic>> login({required String email, required String password}) async {
    final res = await http
        .post(
          Uri.parse('$baseUrl/api/auth/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email, 'password': password}),
        )
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  Future<Map<String, dynamic>> me() async {
    final res = await http
        .get(Uri.parse('$baseUrl/api/auth/me'), headers: _authHeaders)
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  // --- account ---
  //
  // Display name only — BYOK model preference is NOT server state anymore
  // (see ModelSettingsService); it lives on the device and is sent
  // per-request (encrypted, see UserCrypto) only on the /api/ask/text
  // calls that need it.

  Future<Map<String, dynamic>> getAccount() async {
    final res = await http
        .get(Uri.parse('$baseUrl/api/account'), headers: _authHeaders)
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  /// Student-profile fields (blueprint Section 5) — all optional, none
  /// required to use the app.
  Future<Map<String, dynamic>> updateAccount({
    String? displayName,
    String? educationLevel,
    String? course,
    String? institution,
    String? preferredLanguage,
    int? dailyStudyTargetMinutes,
  }) async {
    final body = <String, dynamic>{
      if (displayName != null) 'display_name': displayName,
      if (educationLevel != null) 'education_level': educationLevel,
      if (course != null) 'course': course,
      if (institution != null) 'institution': institution,
      if (preferredLanguage != null) 'preferred_language': preferredLanguage,
      if (dailyStudyTargetMinutes != null) 'daily_study_target_minutes': dailyStudyTargetMinutes,
    };
    final res = await http
        .patch(Uri.parse('$baseUrl/api/account'), headers: _jsonHeaders, body: jsonEncode(body))
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  // --- projects ---
  //
  // Unlike everything else in this client, project material genuinely is
  // server state — see server/db.py's module docstring for why (the
  // embedding compute has to happen somewhere).

  Future<Map<String, dynamic>> createProject({required String displayName}) async {
    final res = await http
        .post(
          Uri.parse('$baseUrl/api/projects'),
          headers: _jsonHeaders,
          body: jsonEncode({'display_name': displayName}),
        )
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  Future<Map<String, dynamic>> listProjects() async {
    final res = await http
        .get(Uri.parse('$baseUrl/api/projects'), headers: _authHeaders)
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  Future<Map<String, dynamic>> deleteProject(String slug) async {
    final res = await http
        .delete(Uri.parse('$baseUrl/api/projects/$slug'), headers: _authHeaders)
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  /// Exactly one of `text` or (`fileBytes` + `filename`) should be given —
  /// see routers/projects.py's `add_material`, which accepts pasted text
  /// or a .pdf/.txt upload.
  Future<Map<String, dynamic>> addProjectMaterial({
    required String slug,
    String? text,
    List<int>? fileBytes,
    String? filename,
  }) async {
    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/api/projects/$slug/material'));
    request.headers.addAll(_authHeaders);
    if (text != null) request.fields['text'] = text;
    if (fileBytes != null && filename != null) {
      request.files.add(http.MultipartFile.fromBytes('file', fileBytes, filename: filename));
    }
    final streamed = await request.send().timeout(_requestTimeout, onTimeout: _timeoutError);
    final res = await http.Response.fromStream(streamed);
    return _decode(res);
  }

  // --- studio (generated documents over a project's material) ---

  Future<Map<String, dynamic>> generateStudioDoc({
    required String slug,
    required String docType,
    String? title,
  }) async {
    final res = await http
        .post(
          Uri.parse('$baseUrl/api/projects/$slug/studio'),
          headers: _jsonHeaders,
          body: jsonEncode({'doc_type': docType, if (title != null) 'title': title}),
        )
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  Future<Map<String, dynamic>> listStudioDocs(String slug) async {
    final res = await http
        .get(Uri.parse('$baseUrl/api/projects/$slug/studio'), headers: _authHeaders)
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  Future<Map<String, dynamic>> deleteStudioDoc({required String slug, required int artifactId}) async {
    final res = await http
        .delete(Uri.parse('$baseUrl/api/projects/$slug/studio/$artifactId'), headers: _authHeaders)
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  // --- ask endpoints ---

  /// `modelConfig` — `{"backend": "anthropic"|"openai"|"local", "model_name"?,
  /// "encrypted_api_key"?}` (see routers/ask.py's ModelConfig); omit or pass
  /// backend "local" to use the server's built-in model.
  ///
  /// `localEvents` — this device's own activity log (see
  /// LocalDb.loadActivityForQuery), forwarded to the moderator's
  /// memory_query route so "what did I struggle with" works without the
  /// server keeping a copy — see routers/ask.py's TextAsk.local_events.
  Future<Map<String, dynamic>> askText({
    required String content,
    String? task,
    String? requestedFormat,
    Map<String, dynamic>? params,
    Map<String, dynamic>? modelConfig,
    List<Map<String, dynamic>>? localEvents,
    required String sessionId,
  }) async {
    final res = await http
        .post(
          Uri.parse('$baseUrl/api/ask/text'),
          headers: _jsonHeaders,
          body: jsonEncode({
            'content': content,
            if (task != null) 'task': task,
            if (requestedFormat != null) 'requested_format': requestedFormat,
            if (params != null) 'params': params,
            if (modelConfig != null) 'model_config': modelConfig,
            if (localEvents != null) 'local_events': localEvents,
            'session_id': sessionId,
          }),
        )
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  Future<Map<String, dynamic>> askImage({
    required List<int> bytes,
    required String filename,
    required String sessionId,
  }) async {
    return _postMultipart(
      '/api/ask/image',
      bytes: bytes,
      filename: filename,
      fields: {'session_id': sessionId},
    );
  }

  /// `bytes`/`filename` are required on the first call in a session (the
  /// upload); a follow-up call (answering the moderator's "what would you
  /// like me to do with it?" clarification) passes only `query` — see
  /// server/README.md's "/api/ask/pdf's two-call flow" note.
  Future<Map<String, dynamic>> askPdf({
    List<int>? bytes,
    String? filename,
    String? query,
    required String sessionId,
  }) async {
    final fields = {
      'session_id': sessionId,
      if (query != null) 'query': query,
    };
    if (bytes != null && filename != null) {
      return _postMultipart('/api/ask/pdf', bytes: bytes, filename: filename, fields: fields);
    }
    final res = await http
        .post(Uri.parse('$baseUrl/api/ask/pdf'), headers: _authHeaders, body: fields)
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  Future<Map<String, dynamic>> askAudio({
    required List<int> bytes,
    required String filename,
    required String sessionId,
  }) async {
    return _postMultipart(
      '/api/ask/audio',
      bytes: bytes,
      filename: filename,
      fields: {'session_id': sessionId},
    );
  }

  Future<Map<String, dynamic>> askWeb({
    required String url,
    String kind = 'url',
    required String sessionId,
  }) async {
    final res = await http
        .post(
          Uri.parse('$baseUrl/api/ask/web'),
          headers: _jsonHeaders,
          body: jsonEncode({'url': url, 'kind': kind, 'session_id': sessionId}),
        )
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  Future<Map<String, dynamic>> askProject({
    String content = '',
    String? project,
    String? query,
    required String sessionId,
  }) async {
    final res = await http
        .post(
          Uri.parse('$baseUrl/api/ask/project'),
          headers: _jsonHeaders,
          body: jsonEncode({
            'content': content,
            if (project != null) 'project': project,
            if (query != null) 'query': query,
            'session_id': sessionId,
          }),
        )
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  Future<Map<String, dynamic>> _postMultipart(
    String path, {
    required List<int> bytes,
    required String filename,
    required Map<String, String> fields,
  }) async {
    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl$path'));
    request.headers.addAll(_authHeaders);
    request.fields.addAll(fields);
    request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final streamed = await request.send().timeout(_requestTimeout, onTimeout: _timeoutError);
    final res = await http.Response.fromStream(streamed);
    return _decode(res);
  }

  // --- concepts, mastery, assessment (blueprint Sections 15-18) ---
  //
  // All under /api/v1 — see server/domains/learning/router.py and
  // server/domains/assessment/router.py. Same raw-JSON convention as
  // everything above; no typed models introduced here to match.

  Future<Map<String, dynamic>> listConcepts(String slug) async {
    final res = await http
        .get(Uri.parse('$baseUrl/api/v1/knowledge-spaces/$slug/concepts'), headers: _authHeaders)
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  Future<Map<String, dynamic>> createConcept({
    required String slug,
    required String name,
    String? description,
  }) async {
    final res = await http
        .post(
          Uri.parse('$baseUrl/api/v1/knowledge-spaces/$slug/concepts'),
          headers: _jsonHeaders,
          body: jsonEncode({'name': name, if (description != null) 'description': description}),
        )
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  Future<Map<String, dynamic>> getConceptMastery(int conceptId) async {
    final res = await http
        .get(Uri.parse('$baseUrl/api/v1/concepts/$conceptId/mastery'), headers: _authHeaders)
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  /// See server/ai/moderator/router.py — depth/style adapt to the
  /// student's real mastery, memory, and personality server-side; this
  /// call itself takes no parameters beyond an optional BYOK modelConfig.
  Future<Map<String, dynamic>> explainConcept(int conceptId, {Map<String, dynamic>? modelConfig}) async {
    final res = await http
        .post(
          Uri.parse('$baseUrl/api/v1/concepts/$conceptId/explain'),
          headers: _jsonHeaders,
          body: jsonEncode({if (modelConfig != null) 'model_config': modelConfig}),
        )
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  Future<Map<String, dynamic>> listQuestions(int conceptId) async {
    final res = await http
        .get(Uri.parse('$baseUrl/api/v1/concepts/$conceptId/questions'), headers: _authHeaders)
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  /// `correctAnswer` shape depends on `type` — see
  /// server/domains/assessment/grading.py's module docstring (a string
  /// for mcq/true_false, a number for numerical, etc.). `options` is only
  /// used by mcq. `tolerance` is only used by numerical.
  Future<Map<String, dynamic>> createQuestion({
    required int conceptId,
    required String type,
    required String prompt,
    required dynamic correctAnswer,
    List<String>? options,
    double? tolerance,
  }) async {
    final res = await http
        .post(
          Uri.parse('$baseUrl/api/v1/concepts/$conceptId/questions'),
          headers: _jsonHeaders,
          body: jsonEncode({
            'type': type,
            'prompt': prompt,
            'correct_answer': correctAnswer,
            if (options != null) 'options': options,
            if (tolerance != null) 'tolerance': tolerance,
          }),
        )
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  Future<Map<String, dynamic>> submitAttempt({
    required int questionId,
    required dynamic answer,
    Map<String, dynamic>? modelConfig,
  }) async {
    final res = await http
        .post(
          Uri.parse('$baseUrl/api/v1/questions/$questionId/attempt'),
          headers: _jsonHeaders,
          body: jsonEncode({'answer': answer, if (modelConfig != null) 'model_config': modelConfig}),
        )
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  // --- planner: goals, generated plan, study sessions (blueprint Sections
  // 21-22) ---
  //
  // See server/domains/planning/router.py. `knowledgeSpaceSlug` is
  // optional throughout — a Goal/plan/session can be account-wide, not
  // tied to one project, unlike everything in the concepts/questions
  // section above.

  Future<Map<String, dynamic>> listGoals() async {
    final res = await http
        .get(Uri.parse('$baseUrl/api/v1/goals'), headers: _authHeaders)
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  Future<Map<String, dynamic>> createGoal({
    required String title,
    DateTime? targetDate,
    String? knowledgeSpaceSlug,
  }) async {
    final res = await http
        .post(
          Uri.parse('$baseUrl/api/v1/goals'),
          headers: _jsonHeaders,
          body: jsonEncode({
            'title': title,
            if (targetDate != null) 'target_date': targetDate.toUtc().toIso8601String(),
            if (knowledgeSpaceSlug != null) 'knowledge_space_slug': knowledgeSpaceSlug,
          }),
        )
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  Future<Map<String, dynamic>> deleteGoal(int goalId) async {
    final res = await http
        .delete(Uri.parse('$baseUrl/api/v1/goals/$goalId'), headers: _authHeaders)
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  /// Blends review urgency, weakness, deadline urgency, and prerequisite
  /// importance into a prioritized study plan — see planner.py's own
  /// docstring for the exact formula. Each phase's `concepts` field
  /// (id+name) is what lets this render without a separate lookup.
  Future<Map<String, dynamic>> getPlan({int durationMinutes = 60, String? knowledgeSpaceSlug}) async {
    final uri = Uri.parse('$baseUrl/api/v1/plan').replace(
      queryParameters: {
        'duration_minutes': durationMinutes.toString(),
        if (knowledgeSpaceSlug != null) 'knowledge_space_slug': knowledgeSpaceSlug,
      },
    );
    final res = await http.get(uri, headers: _authHeaders).timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  Future<Map<String, dynamic>> createStudySession({int durationMinutes = 60, String? knowledgeSpaceSlug}) async {
    final res = await http
        .post(
          Uri.parse('$baseUrl/api/v1/study-sessions'),
          headers: _jsonHeaders,
          body: jsonEncode({
            'duration_minutes': durationMinutes,
            if (knowledgeSpaceSlug != null) 'knowledge_space_slug': knowledgeSpaceSlug,
          }),
        )
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  Future<Map<String, dynamic>> listStudySessions() async {
    final res = await http
        .get(Uri.parse('$baseUrl/api/v1/study-sessions'), headers: _authHeaders)
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  Future<Map<String, dynamic>> getStudySession(int sessionId) async {
    final res = await http
        .get(Uri.parse('$baseUrl/api/v1/study-sessions/$sessionId'), headers: _authHeaders)
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  Future<Map<String, dynamic>> completeStudySession(int sessionId) async {
    final res = await http
        .post(Uri.parse('$baseUrl/api/v1/study-sessions/$sessionId/complete'), headers: _authHeaders)
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  // --- progress: mastery, misconceptions, attempts (all account-wide,
  // each item already carries a resolved concept_name — see
  // server/domains/learning/router.py and assessment/router.py) ---

  Future<Map<String, dynamic>> getMastery() async {
    final res = await http
        .get(Uri.parse('$baseUrl/api/v1/mastery'), headers: _authHeaders)
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  Future<Map<String, dynamic>> getMisconceptions() async {
    final res = await http
        .get(Uri.parse('$baseUrl/api/v1/misconceptions'), headers: _authHeaders)
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  Future<Map<String, dynamic>> getAttempts({int limit = 50}) async {
    final uri = Uri.parse('$baseUrl/api/v1/attempts').replace(queryParameters: {'limit': limit.toString()});
    final res = await http.get(uri, headers: _authHeaders).timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  // --- memory: explicit facts/preferences (blueprint Sections 8-9) ---
  //
  // Only "explicit" memories can be created by a client — "episodic" ones
  // are system-generated internally (mastery/misconception events) and
  // have no POST route of their own, see server/ai/memory/router.py.

  Future<Map<String, dynamic>> listMemories({String? type}) async {
    final uri = Uri.parse('$baseUrl/api/v1/memories').replace(
      queryParameters: {if (type != null) 'type': type},
    );
    final res = await http.get(uri, headers: _authHeaders).timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  Future<Map<String, dynamic>> createMemory({required String key, required dynamic value}) async {
    final res = await http
        .post(
          Uri.parse('$baseUrl/api/v1/memories'),
          headers: _jsonHeaders,
          body: jsonEncode({'key': key, 'value': value}),
        )
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  Future<Map<String, dynamic>> deleteMemory(int memoryId) async {
    final res = await http
        .delete(Uri.parse('$baseUrl/api/v1/memories/$memoryId'), headers: _authHeaders)
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  // --- personality (blueprint Section 7) — 8 dimensions, get-or-create
  // server-side so there's always a profile to read. ---

  Future<Map<String, dynamic>> getPersonality() async {
    final res = await http
        .get(Uri.parse('$baseUrl/api/v1/personality'), headers: _authHeaders)
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  Future<Map<String, dynamic>> updatePersonality({
    String? tone,
    String? formality,
    double? humor,
    double? encouragement,
    double? directness,
    double? challengeLevel,
    String? verbosity,
    String? teachingStyle,
  }) async {
    final body = <String, dynamic>{
      if (tone != null) 'tone': tone,
      if (formality != null) 'formality': formality,
      if (humor != null) 'humor': humor,
      if (encouragement != null) 'encouragement': encouragement,
      if (directness != null) 'directness': directness,
      if (challengeLevel != null) 'challenge_level': challengeLevel,
      if (verbosity != null) 'verbosity': verbosity,
      if (teachingStyle != null) 'teaching_style': teachingStyle,
    };
    final res = await http
        .patch(Uri.parse('$baseUrl/api/v1/personality'), headers: _jsonHeaders, body: jsonEncode(body))
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  Map<String, dynamic> _decode(http.Response res) {
    if (res.statusCode < 200 || res.statusCode >= 300) {
      String detail = res.body;
      try {
        final decoded = jsonDecode(res.body);
        if (decoded is Map && decoded['detail'] != null) detail = decoded['detail'].toString();
      } catch (_) {
        // body wasn't JSON — fall back to the raw text already assigned above
      }
      throw ApiException(res.statusCode, detail);
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }
}

class ApiException implements Exception {
  ApiException(this.statusCode, this.message);
  final int statusCode;
  final String message;

  @override
  String toString() => 'ApiException($statusCode): $message';
}
