import 'package:flutter/material.dart';

import 'app/auth_gate.dart';
import 'app/theme.dart';
import 'core/api/api_client.dart';
import 'core/api/default_base_url.dart';
import 'core/auth/auth_service.dart';
import 'core/settings/model_settings_service.dart';

void main() {
  runApp(StudyOsApp(
    // One shared ApiClient for the whole app — AuthService attaches the
    // login token to this exact instance, so every screen (chat, history,
    // account) that holds a reference to it is authenticated automatically.
    // Creating a second instance anywhere would silently lose the token.
    apiClient: ApiClient(baseUrl: defaultBaseUrl()),
  ));
}

class StudyOsApp extends StatelessWidget {
  StudyOsApp({super.key, required this.apiClient})
      : authService = AuthService(apiClient: apiClient, modelSettings: ModelSettingsService());

  final ApiClient apiClient;
  final AuthService authService;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Study OS',
      theme: studyOsLightTheme,
      darkTheme: studyOsDarkTheme,
      // Android 15+ (this app's target SDK) forces edge-to-edge: every
      // screen draws behind the system navigation bar, and only the few
      // that wrapped themselves in a SafeArea kept their bottom content
      // (buttons, list ends, input bars) clear of it — reported from the
      // user's phone 2026-10-07. Insetting once here keeps every screen,
      // including ones added later, above the nav bar; screens below see
      // zero bottom padding, so their own SafeAreas don't double it. The
      // strip behind the nav bar takes the scaffold colour.
      builder: (context, child) => ColoredBox(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: SafeArea(top: false, left: false, right: false, child: child!),
      ),
      home: AuthGate(authService: authService),
    );
  }
}
