import 'package:flutter/widgets.dart';

import 'chat_media_consent.dart';

export 'chat_media_consent.dart';

/// Web build: nothing is ever saved locally, and the "save on this phone?"
/// question is never asked — chat media always loads from the server.
class ChatMediaStore {
  ChatMediaStore._();
  static final ChatMediaStore instance = ChatMediaStore._();

  static const bool supported = false;

  final ValueNotifier<ChatMediaConsent> consent = ValueNotifier(ChatMediaConsent.dontSave);

  Future<void> load() async {}
  Future<void> setConsent(ChatMediaConsent value) async {}
  String? savedPath(String urlPath) => null;
  Future<String?> pathFor(String baseUrl, String urlPath) async => null;
  Widget localImage(String path, {required ImageErrorWidgetBuilder errorBuilder}) => const SizedBox.shrink();
  Future<bool> openLocal(String path) async => false;
  Future<int> usedBytes() async => 0;
  Future<void> clear() async {}
}
