// The "save chat pictures and PDFs on this phone?" question (2026-10-19):
// nothing is saved until the student answers, the question shows once
// (not under every picture), disappears once answered, and the answer is
// remembered and can be changed from Profile.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:study_os_frontend/core/storage/chat_media_store.dart';
import 'package:study_os_frontend/features/account/presentation/widgets/chat_media_settings.dart';
import 'package:study_os_frontend/features/chat/presentation/widgets/blocks/static_image_block.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ChatMediaStore.instance.consent.value = ChatMediaConsent.undecided;
  });

  testWidgets('asks once under chat pictures, and "Don\'t save" is remembered', (tester) async {
    const block = {'type': 'static_image', 'content': '/generated/abc123.png', 'format': 'png'};
    await tester.pumpWidget(_wrap(const Column(children: [
      StaticImageBlockView(block: block, baseUrl: 'http://127.0.0.1:1'),
      StaticImageBlockView(block: block, baseUrl: 'http://127.0.0.1:1'),
    ])));
    await tester.pump();

    expect(find.text('Save chat pictures and PDFs on this phone?'), findsOneWidget);
    expect(find.textContaining("use your phone's storage"), findsOneWidget);

    await tester.tap(find.text("Don't save"));
    await tester.pump();

    expect(find.text('Save chat pictures and PDFs on this phone?'), findsNothing);
    expect(ChatMediaStore.instance.consent.value, ChatMediaConsent.dontSave);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('chat_media_consent'), 'dontSave');
  });

  testWidgets('Profile switch changes the answer and explains what it means', (tester) async {
    ChatMediaStore.instance.consent.value = ChatMediaConsent.dontSave;
    await tester.pumpWidget(_wrap(const ChatMediaSettingsCard()));
    await tester.pump();

    expect(find.text('Chat files on this phone'), findsOneWidget);
    expect(find.textContaining('Nothing is saved on this phone'), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pump();

    expect(ChatMediaStore.instance.consent.value, ChatMediaConsent.save);
    expect(find.textContaining('old chats keep them'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('chat_media_consent'), 'save');
  });
}
