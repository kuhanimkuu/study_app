import 'package:flutter/material.dart';

import 'app/auth_gate.dart';
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
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo)),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo, brightness: Brightness.dark),
      ),
      home: AuthGate(authService: authService),
    );
  }
}
