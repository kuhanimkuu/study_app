// Real file storage on native targets (Android, Windows); a no-op on web,
// which has no filesystem here — same conditional-export pattern as
// local_db.dart.
export 'chat_media_store_stub.dart' if (dart.library.io) 'chat_media_store_io.dart';
