// Message actions, emoji and the keyboard (2026-10-21): long-press menu,
// reactions, edit and retry buttons, inserting emoji at the cursor, and
// the input field staying right on top of the keyboard in both chats.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:study_os_frontend/features/chat/models/chat_message.dart';
import 'package:study_os_frontend/features/chat/presentation/widgets/chat_input_bar.dart';
import 'package:study_os_frontend/features/chat/presentation/widgets/emoji_picker_sheet.dart';
import 'package:study_os_frontend/features/chat/presentation/widgets/message_bubble.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

void main() {
  testWidgets('long-pressing your message offers reactions, copy and edit', (tester) async {
    String? reacted;
    var edited = false;
    await tester.pumpWidget(_wrap(MessageBubble(
      message: ChatMessage.user('what is osmosis'),
      baseUrl: 'http://test',
      onReact: (emoji) => reacted = emoji,
      onEdit: () => edited = true,
    )));
    await tester.longPress(find.text('what is osmosis'));
    await tester.pumpAndSettle();
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Select text'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);

    await tester.tap(find.text('🙏'));
    await tester.pumpAndSettle();
    expect(reacted, '🙏');

    await tester.longPress(find.text('what is osmosis'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(edited, isTrue);
  });

  testWidgets('an edited message with a reaction says so', (tester) async {
    await tester.pumpWidget(_wrap(MessageBubble(
      message: ChatMessage.user('hi', reaction: '😂', edited: true),
      baseUrl: 'http://test',
      onReact: (_) {},
    )));
    expect(find.text('edited'), findsOneWidget);
    expect(find.text('😂'), findsOneWidget);
  });

  testWidgets("a thumbs-down on Sage's reply offers a different explanation", (tester) async {
    var retried = false;
    final reply = ChatMessage.response([
      {'type': 'text', 'content': 'Osmosis is water moving.', 'source': 'moderator'},
    ]);
    Widget bubble() => _wrap(MessageBubble(
          message: reply,
          baseUrl: 'http://test',
          onReact: (emoji) => reply.reaction = emoji,
          onRetry: () => retried = true,
        ));
    await tester.pumpWidget(bubble());
    expect(find.text('Try a different explanation'), findsNothing);

    await tester.tap(find.byTooltip('Not helpful'));
    await tester.pumpWidget(bubble());
    await tester.tap(find.text('Try a different explanation'));
    expect(retried, isTrue);
  });

  testWidgets("Sage's replies offer Learn more", (tester) async {
    var opened = false;
    await tester.pumpWidget(_wrap(MessageBubble(
      message: ChatMessage.response([
        {'type': 'text', 'content': 'Osmosis is water moving.', 'source': 'moderator'},
      ]),
      baseUrl: 'http://test',
      onReact: (_) {},
      onLearnMore: () => opened = true,
    )));
    await tester.tap(find.text('Learn more'));
    expect(opened, isTrue);
  });

  test('emoji go in at the cursor', () {
    final controller = TextEditingController(text: 'great job');
    controller.selection = const TextSelection.collapsed(offset: 5);
    insertAtCursor(controller, '👏');
    expect(controller.text, 'great👏 job');
    expect(controller.selection.baseOffset, 5 + '👏'.length);
  });

  testWidgets('editing shows a banner with cancel', (tester) async {
    var cancelled = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ChatInputBar(
          controller: TextEditingController(text: 'new text'),
          onSend: () {},
          onAttachmentTap: () {},
          editingText: 'old text',
          onCancelEdit: () => cancelled = true,
        ),
      ),
    ));
    expect(find.text('Editing message'), findsOneWidget);
    expect(find.text('old text'), findsOneWidget);
    await tester.tap(find.byTooltip('Cancel edit'));
    expect(cancelled, isTrue);
  });

  // The two real layouts: the main chat is a Scaffold inside the app shell's
  // Scaffold (with the bottom bar); a subject's chat is a tab of its own
  // Scaffold. With the keyboard open, the field must sit right above it.
  for (final inShell in [true, false]) {
    testWidgets('the field stays above the keyboard (${inShell ? 'main chat' : 'subject chat'})', (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final chat = Column(
        children: [
          Expanded(child: ListView(children: [for (var i = 0; i < 60; i++) Text('message $i')])),
          ChatInputBar(controller: TextEditingController(), onSend: () {}, onAttachmentTap: () {}),
        ],
      );
      final screen = inShell
          ? Scaffold(
              body: Scaffold(appBar: AppBar(title: const Text('Sage')), body: chat),
              bottomNavigationBar: const SizedBox(height: 96, child: ColoredBox(color: Colors.blue)),
            )
          : DefaultTabController(
              length: 2,
              child: Scaffold(
                appBar: AppBar(bottom: const TabBar(tabs: [Tab(text: 'Sources'), Tab(text: 'Chat')])),
                body: TabBarView(children: [const SizedBox(), chat]),
              ),
            );
      await tester.pumpWidget(MaterialApp(home: screen));
      if (!inShell) {
        await tester.tap(find.text('Chat'));
        await tester.pumpAndSettle();
      }

      const keyboard = 300.0; // logical pixels
      tester.view.viewInsets = const FakeViewPadding(bottom: keyboard * 3);
      await tester.pumpAndSettle();

      final field = tester.getRect(find.byType(TextField));
      final screenHeight = tester.view.physicalSize.height / tester.view.devicePixelRatio;
      expect(field.bottom, lessThanOrEqualTo(screenHeight - keyboard), reason: 'hidden behind the keyboard');
      expect(field.bottom, greaterThan(screenHeight - keyboard - 80), reason: 'floating far above the keyboard');
      expect(field.top, greaterThan(0));
    });
  }
}
