import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

import 'idempotent_client.dart';

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
  /// [httpClient] is for tests (package:http/testing's MockClient).
  ///
  /// Every request goes through [IdempotentClient] (2026-10-27): repeats of
  /// a request that changes something are done once on the server.
  ApiClient({required this.baseUrl, this.token, http.Client? httpClient})
      : _http = IdempotentClient(httpClient ?? http.Client());

  /// Applied to every request below. Without this, a dropped connection
  /// (a killed adb reverse tunnel, a server restart mid-request, a dead
  /// Wi-Fi hop) leaves the awaiting Future — and everything downstream of
  /// it, including AuthGate's startup spinner — hanging forever with no
  /// way to recover short of force-closing the app. Generous on purpose:
  /// the local LLM's CPU-bound generation for a conversational reply can
  /// genuinely take tens of seconds, and this needs to outlast that, not
  /// just a fast JSON round-trip.
  static const _requestTimeout = Duration(seconds: 60);

  /// Longer than [_requestTimeout], used only for signup/login/Google
  /// sign-in. Found via direct measurement (2026-09-19): this app's
  /// default hosted backend (a Render free-tier deploy, see
  /// `default_base_url.dart`) fully spins its container down after ~15
  /// minutes idle, and a genuinely cold request can take well over 60
  /// seconds to respond (measured 120s+ with zero response after a ~2-day
  /// idle period) before becoming sub-second once warm. Auth is the call
  /// most likely to be the very first request of a session — a shorter
  /// timeout there would turn a legitimately-slow-but-working cold start
  /// into an outright, avoidable login failure. This doesn't fully solve
  /// an unusually long cold start, just avoids the most common case of
  /// it; see `login_screen.dart`/`signup_screen.dart` for the matching
  /// "waking up the server" UX.
  static const _authRequestTimeout = Duration(seconds: 100);

  /// Used for every AI call (`/api/ask/*` and the multipart uploads that
  /// feed them). Found 2026-10-06: a "make me a PDF study guide" request
  /// against the free local model measured 159s-272s end-to-end, and
  /// generating any long-form document with a BYOK model plus a Render
  /// cold start can also run past a minute — so the old shared 60s
  /// [_requestTimeout] made the app report "Request timed out" while the
  /// server was still successfully writing the PDF, which read to the
  /// user as "PDF generation doesn't work". Plain data calls keep the
  /// shorter timeout, where a long hang really does mean something's wrong.
  static const _aiRequestTimeout = Duration(minutes: 5);

  /// One client for the app's whole life, so requests reuse an open
  /// connection. The top-level `http.get`/`http.post` helpers open (and
  /// close) a fresh client per call — a new TCP + TLS handshake to Render
  /// every time, which on a phone means extra latency, data and battery
  /// for each of the many small JSON calls a screen makes (2026-10-19).
  final IdempotentClient _http;

  Never _timeoutError() {
    // What timed out may still finish on the server; a repeat must reuse its key.
    _http.pinInFlight();
    throw ApiException(0, 'Request timed out — check the server is reachable.');
  }

  /// Mutable (not final) — the settings screen edits this in place on the
  /// one shared instance every screen holds, so a URL change takes effect
  /// everywhere without re-plumbing a new instance through the app.
  String baseUrl;

  /// The current user's JWT (see server/security.py) — null before
  /// login/signup. Every /api/ask/* and /api/account call requires this;
  /// /api/auth/* and /api/health don't.
  String? token;

  /// Supplies the signed-in user's model config (BYOK/hosted) for AI calls
  /// whose caller doesn't pass one explicitly — set by AuthService. Null
  /// before login, or for the free local backend.
  Future<Map<String, dynamic>?> Function()? modelConfigProvider;

  Future<Map<String, dynamic>?> _resolveModelConfig(Map<String, dynamic>? explicit) async =>
      explicit ?? await modelConfigProvider?.call();

  /// A real, browser-like `User-Agent` on every request — without this,
  /// Dart's `http` package sends its own default (`Dart/<version> (dart:io)`),
  /// which Render's Cloudflare edge (confirmed via the `Server: cloudflare`/
  /// `CF-RAY` response headers every `.onrender.com` request already
  /// carries) can flag as bot traffic under its default "Bot Fight Mode"
  /// heuristics — serving an HTML JS-challenge page ("Just a moment...")
  /// instead of proxying to the real app. A real device can never solve
  /// that challenge (no JavaScript execution), so every request silently
  /// fails from the app's point of view. Found 2026-09-19 from a real
  /// device report; reproducible only on whatever network/IP Cloudflare's
  /// heuristics flagged, not from every network, which is why it wasn't
  /// caught by earlier `curl` testing from this environment's own IP.
  static const userAgent = 'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/120.0.0.0 Mobile Safari/537.36 StudyOS/1.0';

  Map<String, String> get _baseHeaders => {'User-Agent': userAgent};

  Map<String, String> get _authHeaders => {
        ..._baseHeaders,
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Map<String, String> get _jsonHeaders => {
        'Content-Type': 'application/json',
        ..._authHeaders,
      };

  Future<Map<String, dynamic>> health() async {
    final res = await _http
        .get(Uri.parse('$baseUrl/api/health'), headers: _baseHeaders)
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  // --- auth ---

  /// Waits before each retry of a "server busy" (503) answer from login or
  /// signup — see [_retryWhenBusy]. Tests set it to zero delays.
  static List<Duration> busyRetryDelays = const [Duration(seconds: 1), Duration(seconds: 2), Duration(seconds: 3)];

  /// Login/signup answer 503 when the server's password-checking queue is
  /// full or this account's previous sign-in is still being checked (e.g.
  /// bots guessing its password — server/core/security.py). Retrying a few
  /// seconds later usually gets in, so do that quietly instead of showing an
  /// error straight away. Any other error (wrong password, the per-address
  /// 429 limit) is returned at once.
  ///
  /// Each wait gets up to 50% random extra (jitter), so phones that were
  /// all turned away at the same moment don't all come back at the same
  /// moment too.
  Future<Map<String, dynamic>> _retryWhenBusy(Future<Map<String, dynamic>> Function() call) async {
    for (final delay in busyRetryDelays) {
      try {
        return await call();
      } on ApiException catch (e) {
        if (e.statusCode != 503) rethrow;
        await Future<void>.delayed(delay + delay * (_random.nextDouble() * 0.5));
      }
    }
    return call();
  }

  static final _random = Random();

  Future<Map<String, dynamic>> signup({
    required String email,
    required String password,
    String? displayName,
  }) => _retryWhenBusy(() => _signupOnce(email: email, password: password, displayName: displayName));

  Future<Map<String, dynamic>> _signupOnce({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final res = await _http
        .post(
          Uri.parse('$baseUrl/api/auth/signup'),
          headers: {'Content-Type': 'application/json', ..._baseHeaders},
          body: jsonEncode({
            'email': email,
            'password': password,
            if (displayName != null) 'display_name': displayName,
          }),
        )
        .timeout(_authRequestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  Future<Map<String, dynamic>> login({required String email, required String password}) =>
      _retryWhenBusy(() => _loginOnce(email: email, password: password));

  Future<Map<String, dynamic>> _loginOnce({required String email, required String password}) async {
    final res = await _http
        .post(
          Uri.parse('$baseUrl/api/auth/login'),
          headers: {'Content-Type': 'application/json', ..._baseHeaders},
          body: jsonEncode({'email': email, 'password': password}),
        )
        .timeout(_authRequestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  /// "Forgot password?": emails a 6-digit code if the email has an account.
  /// Returns the server's message, which is the same either way.
  Future<String> requestPasswordReset(String email) async {
    final res = await _http
        .post(
          Uri.parse('$baseUrl/api/auth/password-reset/request'),
          headers: {'Content-Type': 'application/json', ..._baseHeaders},
          body: jsonEncode({'email': email}),
        )
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res)['message'] as String;
  }

  /// Sets a new password with the emailed code; answers like login.
  Future<Map<String, dynamic>> confirmPasswordReset({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    final res = await _http
        .post(
          Uri.parse('$baseUrl/api/auth/password-reset/confirm'),
          headers: {'Content-Type': 'application/json', ..._baseHeaders},
          body: jsonEncode({'email': email, 'code': code, 'new_password': newPassword}),
        )
        .timeout(_authRequestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  /// Blueprint Section 4's required Google Sign-In — same response shape
  /// as signup/login (token + auth_response including encryption_key),
  /// so AuthService applies it through the exact same path.
  Future<Map<String, dynamic>> googleSignIn({required String idToken}) async {
    final res = await _http
        .post(
          Uri.parse('$baseUrl/api/auth/google'),
          headers: {'Content-Type': 'application/json', ..._baseHeaders},
          body: jsonEncode({'id_token': idToken}),
        )
        .timeout(_authRequestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  Future<Map<String, dynamic>> me() async {
    final res = await _http
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
    final res = await _http
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
    final res = await _http
        .patch(Uri.parse('$baseUrl/api/account'), headers: _jsonHeaders, body: jsonEncode(body))
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  /// Irreversible. Requires re-entering the password server-side (see
  /// server/domains/identity/router.py's delete_account) so a merely-held
  /// token isn't enough on its own — the confirmation dialog in the UI is
  /// a second, separate layer on top of that, not a substitute for it.
  Future<void> deleteAccount({required String password}) async {
    final res = await _http
        .delete(
          Uri.parse('$baseUrl/api/account'),
          headers: _jsonHeaders,
          body: jsonEncode({'password': password}),
        )
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    _decode(res);
  }

  /// Changes the password (or sets a first one on a Google-only account,
  /// where [currentPassword] is null). Every other device is signed out;
  /// the returned token keeps this one signed in.
  Future<String> changePassword({String? currentPassword, required String newPassword}) async {
    final res = await _http
        .post(
          Uri.parse('$baseUrl/api/account/password'),
          headers: _jsonHeaders,
          body: jsonEncode({
            if (currentPassword != null) 'current_password': currentPassword,
            'new_password': newPassword,
          }),
        )
        .timeout(_authRequestTimeout, onTimeout: _timeoutError);
    return _decode(res)['token'] as String;
  }

  /// Signs out every device (a lost phone, a shared computer); the returned
  /// token keeps this one signed in.
  Future<String> signOutEverywhere() async {
    final res = await _http
        .post(Uri.parse('$baseUrl/api/account/sign-out-everywhere'), headers: _authHeaders)
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res)['token'] as String;
  }

  /// "Download my data": everything the account has stored, as the JSON
  /// file's bytes — see server/domains/identity/export.py.
  Future<Uint8List> exportAccountData() async {
    final res = await _http
        .get(Uri.parse('$baseUrl/api/account/export'), headers: _authHeaders)
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    _decodeError(res);
    return res.bodyBytes;
  }

  // --- projects ---
  //
  // Unlike everything else in this client, project material genuinely is
  // server state — see server/db.py's module docstring for why (the
  // embedding compute has to happen somewhere).

  Future<Map<String, dynamic>> createProject({required String displayName}) async {
    final res = await _http
        .post(
          Uri.parse('$baseUrl/api/projects'),
          headers: _jsonHeaders,
          body: jsonEncode({'display_name': displayName}),
        )
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  Future<Map<String, dynamic>> listProjects() async {
    final res = await _http
        .get(Uri.parse('$baseUrl/api/projects'), headers: _authHeaders)
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  Future<Map<String, dynamic>> deleteProject(String slug) async {
    final res = await _http
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
    String? url,
  }) async {
    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/api/projects/$slug/material'));
    request.headers.addAll(_authHeaders);
    if (text != null) request.fields['text'] = text;
    if (url != null) request.fields['url'] = url;
    if (fileBytes != null && filename != null) {
      request.files.add(http.MultipartFile.fromBytes('file', fileBytes, filename: filename));
    }
    final streamed = await _http.send(request).timeout(_aiRequestTimeout, onTimeout: _timeoutError);
    final res = await http.Response.fromStream(streamed);
    return _decode(res);
  }

  /// Per-upload metadata (filename/mime_type/status/created_at) — read
  /// only, no delete: a material's chunks live merged into this space's
  /// shared search index, not tagged by which upload they came from, so
  /// there's no honest per-file delete yet (see server/domains/knowledge/
  /// router.py's list_materials docstring).
  Future<Map<String, dynamic>> listMaterials(String slug) async {
    final res = await _http
        .get(Uri.parse('$baseUrl/api/projects/$slug/materials'), headers: _authHeaders)
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  /// Removes an upload and exactly the search content it added (see the
  /// server's delete_material for the one case it refuses, with a reason).
  Future<Map<String, dynamic>> deleteMaterial({required String slug, required int materialId}) async {
    final res = await _http
        .delete(Uri.parse('$baseUrl/api/projects/$slug/materials/$materialId'), headers: _authHeaders)
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  // --- stored files (uploaded originals, Studio PDFs; 2026-10-07) ---

  /// A short-lived absolute link the phone's browser / PDF viewer can open
  /// without the app's auth header — see server files_router.py.
  Future<Uri> fileLink(int fileId) async {
    final res = await _http
        .post(Uri.parse('$baseUrl/api/files/$fileId/link'), headers: _authHeaders)
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    return Uri.parse('$baseUrl${_decode(res)['url']}');
  }

  // --- studio (generated documents over a project's material) ---

  Future<Map<String, dynamic>> generateStudioDoc({
    required String slug,
    required String docType,
    String? title,
    String? focus,
    Map<String, dynamic>? modelConfig,
  }) async {
    // The AI writes the document from the material (2026-10-28), so this
    // now carries the student's AI choice like every other AI call.
    modelConfig = await _resolveModelConfig(modelConfig);
    final res = await _http
        .post(
          Uri.parse('$baseUrl/api/projects/$slug/studio'),
          headers: _jsonHeaders,
          body: jsonEncode({
            'doc_type': docType,
            if (title != null) 'title': title,
            if (focus != null && focus.trim().isNotEmpty) 'focus': focus.trim(),
            if (modelConfig != null) 'model_config': modelConfig,
          }),
        )
        .timeout(_aiRequestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  Future<Map<String, dynamic>> listStudioDocs(String slug) async {
    final res = await _http
        .get(Uri.parse('$baseUrl/api/projects/$slug/studio'), headers: _authHeaders)
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  Future<Map<String, dynamic>> deleteStudioDoc({required String slug, required int artifactId}) async {
    final res = await _http
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
    List<Map<String, dynamic>>? history,
    String? regenerate,
    bool tutorMode = true,
    String depth = 'full',
  }) async {
    final res = await _http
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
            // The chat so far and "edited"/"retry" (2026-10-21) — see
            // ChatMessage.historyFor and the server's TextAsk.
            if (history != null && history.isNotEmpty) 'history': history,
            if (regenerate != null) 'regenerate': regenerate,
            // Sage ends explanations with a check question (2026-10-21);
            // false is the "Just answer" switch.
            'tutor_mode': tutorMode,
            'depth': depth,
          }),
        )
        .timeout(_aiRequestTimeout, onTimeout: _timeoutError);
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
    final modelConfig = await _resolveModelConfig(null);
    final res = await _http
        .post(
          Uri.parse('$baseUrl/api/ask/pdf'),
          headers: _authHeaders,
          body: {...fields, if (modelConfig != null) 'model_config': jsonEncode(modelConfig)},
        )
        .timeout(_aiRequestTimeout, onTimeout: _timeoutError);
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
    final res = await _http
        .post(
          Uri.parse('$baseUrl/api/ask/web'),
          headers: _jsonHeaders,
          body: jsonEncode({'url': url, 'kind': kind, 'session_id': sessionId}),
        )
        .timeout(_aiRequestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  Future<Map<String, dynamic>> askProject({
    String content = '',
    String? project,
    String? query,
    required String sessionId,
    List<Map<String, dynamic>>? history,
    String? regenerate,
    bool tutorMode = true,
    String depth = 'full',
  }) async {
    final modelConfig = await _resolveModelConfig(null);
    final res = await _http
        .post(
          Uri.parse('$baseUrl/api/ask/project'),
          headers: _jsonHeaders,
          body: jsonEncode({
            'content': content,
            if (project != null) 'project': project,
            if (query != null) 'query': query,
            'session_id': sessionId,
            if (modelConfig != null) 'model_config': modelConfig,
            if (history != null && history.isNotEmpty) 'history': history,
            if (regenerate != null) 'regenerate': regenerate,
            'tutor_mode': tutorMode,
            'depth': depth,
          }),
        )
        .timeout(_aiRequestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  /// AI setup's key test — one tiny call; see server/routers/ai_check.py.
  Future<Map<String, dynamic>> checkAi(Map<String, dynamic> modelConfig) async {
    final res = await _http
        .post(
          Uri.parse('$baseUrl/api/v1/ai/check'),
          headers: _jsonHeaders,
          body: jsonEncode({'model_config': modelConfig}),
        )
        .timeout(_aiRequestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  // --- lessons (2026-10-21) — server/domains/tutor/router.py ---

  /// Writes a lesson on [topic] (in [subjectSlug], or "My lessons"), or on
  /// a subject's concept. Takes a while: one AI call writes the whole lesson.
  Future<Map<String, dynamic>> startLesson({String? topic, String? subjectSlug, int? conceptId}) async {
    final modelConfig = await _resolveModelConfig(null);
    final res = await _http
        .post(
          Uri.parse('$baseUrl/api/v1/lessons'),
          headers: _jsonHeaders,
          body: jsonEncode({
            if (topic != null) 'topic': topic,
            if (subjectSlug != null) 'knowledge_space_slug': subjectSlug,
            if (conceptId != null) 'concept_id': conceptId,
            if (modelConfig != null) 'model_config': modelConfig,
          }),
        )
        .timeout(_aiRequestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  Future<Map<String, dynamic>> getLesson(int lessonId) async {
    final res = await _http
        .get(Uri.parse('$baseUrl/api/v1/lessons/$lessonId'), headers: _authHeaders)
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  /// [status]: "in_progress" or "completed"; null for all.
  Future<List<Map<String, dynamic>>> listLessons({String? status, int limit = 10}) async {
    final query = {'limit': '$limit', if (status != null) 'status': status};
    final res = await _http
        .get(Uri.parse('$baseUrl/api/v1/lessons').replace(queryParameters: query), headers: _authHeaders)
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    return (_decode(res)['lessons'] as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> answerLessonStep(int lessonId, int stepIndex, Object answer) async {
    final modelConfig = await _resolveModelConfig(null);
    final res = await _http
        .post(
          Uri.parse('$baseUrl/api/v1/lessons/$lessonId/steps/$stepIndex/answer'),
          headers: _jsonHeaders,
          body: jsonEncode({'answer': answer, if (modelConfig != null) 'model_config': modelConfig}),
        )
        .timeout(_aiRequestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  /// Finishes a lesson; its recap becomes flashcards. Returns
  /// {"lesson", "flashcards_added"}.
  Future<Map<String, dynamic>> completeLesson(int lessonId) async {
    final res = await _http
        .post(Uri.parse('$baseUrl/api/v1/lessons/$lessonId/complete'), headers: _authHeaders)
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  Future<void> deleteLesson(int lessonId) async {
    final res = await _http
        .delete(Uri.parse('$baseUrl/api/v1/lessons/$lessonId'), headers: _authHeaders)
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    _decode(res);
  }

  // --- Go deeper and videos (2026-10-27) — server/domains/research ---

  /// 2-3 real resources on [topic]: {"level", "items": [...], "picked_by"}.
  Future<Map<String, dynamic>> goDeeper({required String topic, String? context, String? depth}) async {
    final modelConfig = await _resolveModelConfig(null);
    final res = await _http
        .post(
          Uri.parse('$baseUrl/api/v1/go-deeper'),
          headers: _jsonHeaders,
          body: jsonEncode({
            'topic': topic.length > 200 ? topic.substring(0, 200) : topic,
            if (context != null) 'context': context.length > 2000 ? context.substring(0, 2000) : context,
            if (depth != null) 'depth': depth,
            if (modelConfig != null) 'model_config': modelConfig,
          }),
        )
        .timeout(_aiRequestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  Future<Map<String, dynamic>> reportSource({required String url, required String reason}) async {
    final res = await _http
        .post(
          Uri.parse('$baseUrl/api/v1/sources/report'),
          headers: _jsonHeaders,
          body: jsonEncode({'url': url, 'reason': reason}),
        )
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  /// "Save as flashcards" under a chat answer: its key facts become cards
  /// in [subjectSlug]'s review queue.
  Future<Map<String, dynamic>> flashcardsFromText({required String subjectSlug, required String text, int count = 5}) async {
    final modelConfig = await _resolveModelConfig(null);
    final res = await _http
        .post(
          Uri.parse('$baseUrl/api/v1/knowledge-spaces/$subjectSlug/flashcards/from-text'),
          headers: _jsonHeaders,
          body: jsonEncode({'text': text, 'count': count, if (modelConfig != null) 'model_config': modelConfig}),
        )
        .timeout(_aiRequestTimeout, onTimeout: _timeoutError);
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
    // A JSON-string form field (see routers/ask.py's
    // _resolve_form_model_config) — these routes used to ignore the
    // user's BYOK/hosted choice entirely (2026-10-07).
    final modelConfig = await _resolveModelConfig(null);
    if (modelConfig != null) request.fields['model_config'] = jsonEncode(modelConfig);
    request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final streamed = await _http.send(request).timeout(_aiRequestTimeout, onTimeout: _timeoutError);
    final res = await http.Response.fromStream(streamed);
    return _decode(res);
  }

  // --- AI generation from a project's material (2026-10-07) ---
  //
  // Each saves what it generates server-side and returns only the newly
  // created rows plus `skipped_existing` (duplicates of what's already
  // there). A 503 means the free model isn't available on this server; a
  // 502 means the model answered but nothing usable could be parsed.

  Future<Map<String, dynamic>> _postGenerate(String path, Map<String, dynamic> body) async {
    final modelConfig = await _resolveModelConfig(null);
    final res = await _http
        .post(
          Uri.parse('$baseUrl$path'),
          headers: _jsonHeaders,
          body: jsonEncode({...body, if (modelConfig != null) 'model_config': modelConfig}),
        )
        .timeout(_aiRequestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  Future<Map<String, dynamic>> generateConcepts(String slug) =>
      _postGenerate('/api/v1/knowledge-spaces/$slug/concepts/generate', {});

  Future<Map<String, dynamic>> generateFlashcards(String slug, {int count = 8, int? conceptId}) =>
      _postGenerate('/api/v1/knowledge-spaces/$slug/flashcards/generate', {
        'count': count,
        if (conceptId != null) 'concept_id': conceptId,
      });

  Future<Map<String, dynamic>> generateQuestions(int conceptId, {int count = 6}) =>
      _postGenerate('/api/v1/concepts/$conceptId/questions/generate', {'count': count});

  // --- concepts, mastery, assessment (blueprint Sections 15-18) ---
  //
  // All under /api/v1 — see server/domains/learning/router.py and
  // server/domains/assessment/router.py. Same raw-JSON convention as
  // everything above; no typed models introduced here to match.

  Future<Map<String, dynamic>> listConcepts(String slug) async {
    final res = await _http
        .get(Uri.parse('$baseUrl/api/v1/knowledge-spaces/$slug/concepts'), headers: _authHeaders)
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  Future<Map<String, dynamic>> createConcept({
    required String slug,
    required String name,
    String? description,
  }) async {
    final res = await _http
        .post(
          Uri.parse('$baseUrl/api/v1/knowledge-spaces/$slug/concepts'),
          headers: _jsonHeaders,
          body: jsonEncode({'name': name, if (description != null) 'description': description}),
        )
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  Future<Map<String, dynamic>> getConceptMastery(int conceptId) async {
    final res = await _http
        .get(Uri.parse('$baseUrl/api/v1/concepts/$conceptId/mastery'), headers: _authHeaders)
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  // --- concept relationships (Knowledge Graph, blueprint Section 15,
  // scoped to concept-to-concept edges) — a real backend capability
  // (server/domains/learning/models.py's ConceptRelationship) that had no
  // frontend caller at all until this pass, found via an audit prompted
  // by a user report that some backend features weren't exposed.

  Future<Map<String, dynamic>> listConceptRelationships(int conceptId) async {
    final res = await _http
        .get(Uri.parse('$baseUrl/api/v1/concepts/$conceptId/relationships'), headers: _authHeaders)
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  Future<Map<String, dynamic>> createConceptRelationship({
    required int conceptId,
    required int toConceptId,
    required String relationshipType,
  }) async {
    final res = await _http
        .post(
          Uri.parse('$baseUrl/api/v1/concepts/$conceptId/relationships'),
          headers: _jsonHeaders,
          body: jsonEncode({'to_concept_id': toConceptId, 'relationship_type': relationshipType}),
        )
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  Future<void> deleteConceptRelationship({required int conceptId, required int relationshipId}) async {
    final res = await _http
        .delete(
          Uri.parse('$baseUrl/api/v1/concepts/$conceptId/relationships/$relationshipId'),
          headers: _authHeaders,
        )
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    _decode(res);
  }

  // --- search ---

  Future<Map<String, dynamic>> searchKnowledgeSpace({required String slug, required String query, int limit = 5}) async {
    final uri = Uri.parse('$baseUrl/api/v1/knowledge-spaces/$slug/search').replace(
      queryParameters: {'q': query, 'limit': limit.toString()},
    );
    final res = await _http.get(uri, headers: _authHeaders).timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  // --- notes ---

  Future<Map<String, dynamic>> listNotes(String slug) async {
    final res = await _http
        .get(Uri.parse('$baseUrl/api/v1/knowledge-spaces/$slug/notes'), headers: _authHeaders)
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  Future<Map<String, dynamic>> createNote({required String slug, required String title, String body = ''}) async {
    final res = await _http
        .post(
          Uri.parse('$baseUrl/api/v1/knowledge-spaces/$slug/notes'),
          headers: _jsonHeaders,
          body: jsonEncode({'title': title, 'body': body}),
        )
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  Future<Map<String, dynamic>> updateNote({required int noteId, String? title, String? body}) async {
    final res = await _http
        .patch(
          Uri.parse('$baseUrl/api/v1/notes/$noteId'),
          headers: _jsonHeaders,
          body: jsonEncode({if (title != null) 'title': title, if (body != null) 'body': body}),
        )
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  Future<void> deleteNote(int noteId) async {
    final res = await _http
        .delete(Uri.parse('$baseUrl/api/v1/notes/$noteId'), headers: _authHeaders)
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    _decode(res);
  }

  // --- flashcards ---

  Future<Map<String, dynamic>> listFlashcards(String slug) async {
    final res = await _http
        .get(Uri.parse('$baseUrl/api/v1/knowledge-spaces/$slug/flashcards'), headers: _authHeaders)
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  /// Account-wide, every card regardless of due status — unlike
  /// getDueFlashcards (filtered to already-due). Used by the Planner
  /// calendar to plot every card's upcoming review date.
  Future<Map<String, dynamic>> listAllFlashcards() async {
    final res = await _http
        .get(Uri.parse('$baseUrl/api/v1/flashcards'), headers: _authHeaders)
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  Future<Map<String, dynamic>> createFlashcard({
    required String slug,
    required String front,
    required String back,
    int? conceptId,
  }) async {
    final res = await _http
        .post(
          Uri.parse('$baseUrl/api/v1/knowledge-spaces/$slug/flashcards'),
          headers: _jsonHeaders,
          body: jsonEncode({'front': front, 'back': back, if (conceptId != null) 'concept_id': conceptId}),
        )
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  Future<void> deleteFlashcard(int flashcardId) async {
    final res = await _http
        .delete(Uri.parse('$baseUrl/api/v1/flashcards/$flashcardId'), headers: _authHeaders)
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    _decode(res);
  }

  /// Account-wide by default (a review session usually spans every
  /// Knowledge Space) — pass `knowledgeSpaceSlug` to scope it to one, same
  /// convention as getPlan's optional scoping.
  Future<Map<String, dynamic>> getDueFlashcards({String? knowledgeSpaceSlug, int limit = 20}) async {
    final uri = Uri.parse('$baseUrl/api/v1/flashcards/due').replace(
      queryParameters: {
        'limit': limit.toString(),
        if (knowledgeSpaceSlug != null) 'knowledge_space_slug': knowledgeSpaceSlug,
      },
    );
    final res = await _http.get(uri, headers: _authHeaders).timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  /// `rating` must be one of "again"/"hard"/"good"/"easy" (the full FSRS
  /// scale — flashcards are self-graded, unlike quiz questions, so there's
  /// no separate correctness signal to collapse it down to two values).
  ///
  /// [reviewedAt] is for a review made offline and sent later — see
  /// core/storage/offline_flashcards.dart.
  Future<Map<String, dynamic>> reviewFlashcard({required int flashcardId, required String rating, DateTime? reviewedAt}) async {
    final res = await _http
        .post(
          Uri.parse('$baseUrl/api/v1/flashcards/$flashcardId/review'),
          headers: _jsonHeaders,
          body: jsonEncode({'rating': rating, if (reviewedAt != null) 'reviewed_at': reviewedAt.toUtc().toIso8601String()}),
        )
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  /// See server/ai/moderator/router.py — depth/style adapt to the
  /// student's real mastery, memory, and personality server-side; this
  /// call itself takes no parameters beyond an optional BYOK modelConfig.
  Future<Map<String, dynamic>> explainConcept(int conceptId, {Map<String, dynamic>? modelConfig}) async {
    modelConfig = await _resolveModelConfig(modelConfig);
    final res = await _http
        .post(
          Uri.parse('$baseUrl/api/v1/concepts/$conceptId/explain'),
          headers: _jsonHeaders,
          body: jsonEncode({if (modelConfig != null) 'model_config': modelConfig}),
        )
        .timeout(_aiRequestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  Future<Map<String, dynamic>> listQuestions(int conceptId) async {
    final res = await _http
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
    final res = await _http
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
    modelConfig = await _resolveModelConfig(modelConfig);
    final res = await _http
        .post(
          Uri.parse('$baseUrl/api/v1/questions/$questionId/attempt'),
          headers: _jsonHeaders,
          body: jsonEncode({'answer': answer, if (modelConfig != null) 'model_config': modelConfig}),
        )
        .timeout(_aiRequestTimeout, onTimeout: _timeoutError);
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
    final res = await _http
        .get(Uri.parse('$baseUrl/api/v1/goals'), headers: _authHeaders)
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  Future<Map<String, dynamic>> createGoal({
    required String title,
    DateTime? targetDate,
    String? knowledgeSpaceSlug,
  }) async {
    final res = await _http
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
    final res = await _http
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
    final res = await _http.get(uri, headers: _authHeaders).timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  Future<Map<String, dynamic>> createStudySession({int durationMinutes = 60, String? knowledgeSpaceSlug}) async {
    final res = await _http
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
    final res = await _http
        .get(Uri.parse('$baseUrl/api/v1/study-sessions'), headers: _authHeaders)
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  Future<Map<String, dynamic>> getStudySession(int sessionId) async {
    final res = await _http
        .get(Uri.parse('$baseUrl/api/v1/study-sessions/$sessionId'), headers: _authHeaders)
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  Future<Map<String, dynamic>> completeStudySession(int sessionId) async {
    final res = await _http
        .post(Uri.parse('$baseUrl/api/v1/study-sessions/$sessionId/complete'), headers: _authHeaders)
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  // --- progress: mastery, misconceptions, attempts (all account-wide,
  // each item already carries a resolved concept_name — see
  // server/domains/learning/router.py and assessment/router.py) ---

  Future<Map<String, dynamic>> getMastery() async {
    final res = await _http
        .get(Uri.parse('$baseUrl/api/v1/mastery'), headers: _authHeaders)
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  Future<Map<String, dynamic>> getMisconceptions() async {
    final res = await _http
        .get(Uri.parse('$baseUrl/api/v1/misconceptions'), headers: _authHeaders)
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  Future<Map<String, dynamic>> getAttempts({int limit = 50}) async {
    final uri = Uri.parse('$baseUrl/api/v1/attempts').replace(queryParameters: {'limit': limit.toString()});
    final res = await _http.get(uri, headers: _authHeaders).timeout(_requestTimeout, onTimeout: _timeoutError);
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
    final res = await _http.get(uri, headers: _authHeaders).timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  Future<Map<String, dynamic>> createMemory({required String key, required dynamic value}) async {
    final res = await _http
        .post(
          Uri.parse('$baseUrl/api/v1/memories'),
          headers: _jsonHeaders,
          body: jsonEncode({'key': key, 'value': value}),
        )
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  Future<Map<String, dynamic>> deleteMemory(int memoryId) async {
    final res = await _http
        .delete(Uri.parse('$baseUrl/api/v1/memories/$memoryId'), headers: _authHeaders)
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  // --- personality (blueprint Section 7) — 8 dimensions, get-or-create
  // server-side so there's always a profile to read. ---

  Future<Map<String, dynamic>> getPersonality() async {
    final res = await _http
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
    final res = await _http
        .patch(Uri.parse('$baseUrl/api/v1/personality'), headers: _jsonHeaders, body: jsonEncode(body))
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  // --- billing: the hosted AI tier, paid in app credits (2026-10-27). See
  // server/domains/billing/ — Study OS's own pooled provider key, never a
  // per-user provisioned one. The balance comes with the price of each
  // feature and the packs on offer. ---

  Future<Map<String, dynamic>> getBillingBalance() async {
    final res = await _http
        .get(Uri.parse('$baseUrl/api/v1/billing/balance'), headers: _authHeaders)
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  /// The only payment provider wired up server-side right now is a mock
  /// that confirms instantly — see payment_provider.py. No real money
  /// changes hands yet.
  Future<Map<String, dynamic>> createTopup(String pack) async {
    final res = await _http
        .post(
          Uri.parse('$baseUrl/api/v1/billing/topups'),
          headers: _jsonHeaders,
          body: jsonEncode({'pack': pack}),
        )
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  Future<Map<String, dynamic>> listBillingUsage() async {
    final res = await _http
        .get(Uri.parse('$baseUrl/api/v1/billing/usage'), headers: _authHeaders)
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  /// The token meter: this student's own AI usage (today / last 30 days /
  /// all time, plus per model) — see billing/router.py's ai_usage_summary.
  /// Costs are integer micro-USD (millionths of a dollar).
  /// "Today" is the phone's own day: the server is told its UTC offset.
  Future<Map<String, dynamic>> getAiUsage() async {
    final offset = DateTime.now().timeZoneOffset.inMinutes;
    final res = await _http
        .get(Uri.parse('$baseUrl/api/v1/billing/ai-usage?tz_offset_minutes=$offset'), headers: _authHeaders)
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  /// The student's own monthly AI spending cap, in cents; null removes it.
  Future<Map<String, dynamic>> setAiSpendLimit(int? monthlyLimitCents) async {
    final res = await _http
        .put(
          Uri.parse('$baseUrl/api/v1/billing/ai-usage/limit'),
          headers: _jsonHeaders,
          body: jsonEncode({'monthly_limit_cents': monthlyLimitCents}),
        )
        .timeout(_requestTimeout, onTimeout: _timeoutError);
    return _decode(res);
  }

  /// A crash report — see core/errors/error_reporter.dart. Sent signed in
  /// when there's a token, but works without one.
  Future<void> reportClientError({
    required String message,
    required String stack,
    required String appVersion,
    required String platform,
  }) async {
    await _http
        .post(
          Uri.parse('$baseUrl/api/v1/client-errors'),
          headers: _jsonHeaders,
          body: jsonEncode({'message': message, 'stack': stack, 'app_version': appVersion, 'platform': platform}),
        )
        .timeout(_requestTimeout, onTimeout: _timeoutError);
  }

  /// Called when the server says this device's sign-in is no longer valid
  /// (the password was changed or "sign out everywhere" was used on another
  /// device, or the token expired). AuthService signs out, which takes the
  /// student back to the login screen instead of leaving every screen
  /// failing with "you were signed out".
  void Function()? onSignedOut;

  static bool _isSignedOutDetail(String detail) =>
      detail.startsWith('you were signed out') ||
      detail.startsWith('invalid or expired token') ||
      detail == 'user no longer exists';

  Map<String, dynamic> _decode(http.Response res) {
    _decodeError(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Throws [ApiException] for a non-2xx answer; returns quietly otherwise.
  void _decodeError(http.Response res) {
    if (res.statusCode < 200 || res.statusCode >= 300) {
      String detail = res.body;
      try {
        final decoded = jsonDecode(res.body);
        if (decoded is Map && decoded['detail'] != null) detail = decoded['detail'].toString();
      } catch (_) {
        // Body wasn't JSON — most likely an intermediary (a proxy, a CDN's
        // bot/JS challenge page, a misconfigured base URL hitting a plain
        // web server) returned HTML instead of the server's own error
        // shape. Never surface raw markup to the UI — every caller renders
        // `ApiException.message` directly as user-facing text (found
        // 2026-09-19: a Cloudflare "Just a moment..." challenge page,
        // triggered on some networks by Dart's default User-Agent — see
        // `userAgent` above — showed up verbatim on several screens).
        // 2026-10-07: the challenge came back even with the browser
        // User-Agent, as an HTTP 429 for every request from one Wi-Fi
        // network's IP — so name it, and give the one thing a student
        // can actually do about it (another network).
        final isCloudflareChallenge = res.body.contains('Just a moment') || res.body.contains('challenges.cloudflare.com');
        if (isCloudflareChallenge) {
          detail = 'The hosting provider\'s bot protection is blocking requests from this network right now. '
              'Try switching between Wi-Fi and mobile data, or wait a few minutes and try again.';
        } else if (res.body.trim().startsWith('<')) {
          detail = 'The server returned an unexpected response (not the app\'s API) — try again in a moment.';
        }
      }
      if (res.statusCode == 401 && token != null && _isSignedOutDetail(detail)) onSignedOut?.call();
      throw ApiException(res.statusCode, detail);
    }
  }
}

class ApiException implements Exception {
  ApiException(this.statusCode, this.message);
  final int statusCode;
  final String message;

  @override
  String toString() => 'ApiException($statusCode): $message';
}
