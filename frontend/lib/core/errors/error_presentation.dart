import 'package:flutter/material.dart';

import '../api/api_client.dart';

/// Centralized error-to-snackbar presentation (blueprint Section 29) —
/// every screen already caught `ApiException` and showed its `.message`
/// in a SnackBar by hand; this is that one line, named, so new screens
/// don't reinvent it. Deliberately NOT a bigger error-classification
/// system (retry policies, offline banners, etc.) — this app has no
/// offline mode to design around (see server/main.py's architecture
/// note), so there is no more to centralize here yet.
void showApiError(BuildContext context, Object error) {
  final message = error is ApiException ? error.message : error.toString();
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
