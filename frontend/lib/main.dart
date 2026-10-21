import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/auth_gate.dart';
import 'app/theme.dart';
import 'core/api/api_client.dart';
import 'core/api/default_base_url.dart';
import 'core/auth/auth_service.dart';
import 'core/errors/error_reporter.dart';
import 'core/notifications/study_reminders.dart';
import 'core/settings/model_settings_service.dart';
import 'core/storage/chat_media_store.dart';
import 'features/chat/tutor_mode.dart';
import 'features/account/ai_setup/ai_setup.dart';

Future<void> main() async {
  // The student's saved answer to "keep chat files on this phone?" — read
  // before the first frame so the chat never flashes the question to
  // someone who already answered. SharedPreferences needs the binding.
  WidgetsFlutterBinding.ensureInitialized();
  // The bundled fonts' licences, for Profile → Open-source licences (the
  // OFL asks for it to ship with the fonts).
  LicenseRegistry.addLicense(() async* {
    for (final family in const ['Inter', 'Nunito']) {
      yield LicenseEntryWithLineBreaks([family], await rootBundle.loadString('assets/fonts/$family-OFL.txt'));
    }
  });
  await ChatMediaStore.instance.load();
  // Whether study reminders are on, so Home's first load can reschedule them.
  await StudyReminders.instance.load();
  // Whether Sage checks understanding in chat (features/chat/tutor_mode.dart).
  await TutorMode.instance.load();
  // One shared ApiClient for the whole app — AuthService attaches the
  // login token to this exact instance, so every screen (chat, history,
  // account) that holds a reference to it is authenticated automatically.
  // Creating a second instance anywhere would silently lose the token.
  final apiClient = ApiClient(baseUrl: defaultBaseUrl());
  // Crash reports to our own server (release builds only).
  ErrorReporter(apiClient: apiClient).install();
  runApp(StudyOsApp(apiClient: apiClient));
}

class StudyOsApp extends StatelessWidget {
  StudyOsApp({super.key, required this.apiClient})
      : authService = AuthService(apiClient: apiClient, modelSettings: ModelSettingsService()) {
    // Lets any screen ask "is AI set up?" (features/account/ai_setup).
    AiSetup.attach(authService);
  }

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
