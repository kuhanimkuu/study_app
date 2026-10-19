import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api_client.dart';
import 'chat_media_consent.dart';

export 'chat_media_consent.dart';

/// Keeps chat pictures, animations, PDFs and 3D models on this device
/// (2026-10-19). The server deletes them after about two weeks
/// (server/workers/cleanup.py), and chat history — stored on the phone —
/// only holds their links, so without this an old chat's pictures stop
/// loading.
///
/// Only with the student's say-so: until [consent] is
/// [ChatMediaConsent.save] nothing is downloaded, and the chat shows a
/// one-time question explaining the storage trade-off (ChatMediaConsentPrompt).
/// The setting, the space used and a "delete saved files" button live on
/// the Profile screen. Files go in the app's private folder: no storage
/// permission, and Android removes them with the app.
class ChatMediaStore {
  ChatMediaStore._();
  static final ChatMediaStore instance = ChatMediaStore._();

  static const bool supported = true;
  static const _prefsKey = 'chat_media_consent';

  /// Only `/generated/<name>.<ext>` with a plain file name — a block's
  /// content comes from the server, and must never steer a write outside
  /// the media folder.
  static final _safeName = RegExp(r'^[A-Za-z0-9_-]+\.[A-Za-z0-9]{1,5}$');

  final ValueNotifier<ChatMediaConsent> consent = ValueNotifier(ChatMediaConsent.undecided);
  final http.Client _http = http.Client();
  final Map<String, Future<String?>> _inFlight = {};
  Directory? _dir;
  bool _loaded = false;

  /// Names of the files saved so far, listed once at startup, so that
  /// rendering a chat picture never touches the disk just to find out
  /// whether there's a local copy.
  final Set<String> _saved = {};

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      consent.value = ChatMediaConsent.fromName(prefs.getString(_prefsKey));
    } catch (_) {
      // no stored answer readable — the chat simply asks again
    }
    try {
      await for (final entity in (await _folder()).list()) {
        final name = p.basename(entity.path);
        if (entity is File && _safeName.hasMatch(name)) _saved.add(name);
      }
    } catch (_) {
      // unreadable folder: behaves as if nothing was saved yet
    }
  }

  Future<void> setConsent(ChatMediaConsent value) async {
    consent.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, value.name);
  }

  Future<Directory> _folder() async {
    final existing = _dir;
    if (existing != null) return existing;
    final dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'chat_media'));
    await dir.create(recursive: true);
    return _dir = dir;
  }

  static String? _fileName(String urlPath) {
    if (!urlPath.startsWith('/generated/')) return null;
    final name = urlPath.substring('/generated/'.length);
    return _safeName.hasMatch(name) ? name : null;
  }

  /// The local copy of [urlPath] if one was saved earlier, else null.
  String? savedPath(String urlPath) {
    final name = _fileName(urlPath);
    final dir = _dir;
    if (name == null || dir == null || !_saved.contains(name)) return null;
    return p.join(dir.path, name);
  }

  /// The local copy of [urlPath], downloading it first if the student
  /// agreed to saving. Null when it isn't saved and can't be (no consent,
  /// offline, or already gone from the server) — callers then fall back
  /// to the server URL.
  Future<String?> pathFor(String baseUrl, String urlPath) async {
    final existing = savedPath(urlPath);
    if (existing != null || consent.value != ChatMediaConsent.save) return existing;
    return _inFlight[urlPath] ??= _download(baseUrl, urlPath).whenComplete(() => _inFlight.remove(urlPath));
  }

  Future<String?> _download(String baseUrl, String urlPath) async {
    final name = _fileName(urlPath);
    if (name == null) return null;
    try {
      final res = await _http
          .get(Uri.parse('$baseUrl$urlPath'), headers: {'User-Agent': ApiClient.userAgent})
          .timeout(const Duration(seconds: 60));
      if (res.statusCode != 200) return null;
      final dir = await _folder();
      // write then rename, so a half-finished download is never mistaken
      // for a saved file
      final partial = File(p.join(dir.path, '$name.part'));
      await partial.writeAsBytes(res.bodyBytes, flush: true);
      final saved = await partial.rename(p.join(dir.path, name));
      _saved.add(name);
      return saved.path;
    } catch (_) {
      return null;
    }
  }

  Widget localImage(String path, {required ImageErrorWidgetBuilder errorBuilder}) =>
      Image.file(File(path), gaplessPlayback: true, errorBuilder: errorBuilder);

  /// Opens a saved PDF/3D model in the phone's own viewer. open_filex
  /// shares the file through its FileProvider — a plain file:// link is
  /// blocked between apps on Android.
  Future<bool> openLocal(String path) async {
    if (Platform.isAndroid || Platform.isIOS) {
      return (await OpenFilex.open(path)).type == ResultType.done;
    }
    return launchUrl(Uri.file(path));
  }

  Future<int> usedBytes() async {
    final dir = await _folder();
    var total = 0;
    await for (final entity in dir.list()) {
      if (entity is File) total += await entity.length();
    }
    return total;
  }

  Future<void> clear() async {
    final dir = await _folder();
    await for (final entity in dir.list()) {
      if (entity is File) await entity.delete();
    }
    _saved.clear();
  }
}
