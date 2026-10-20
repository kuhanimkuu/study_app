import 'package:flutter/material.dart';

/// Terms of Service / Privacy Policy — real, plain-language content
/// describing what this app actually does, not placeholder text. Written
/// for a student project, not legally reviewed — honest about that in-app
/// rather than implying otherwise. Reached from Signup's consent checkbox.
///
/// The SAME text is published on the website (website/src/content/legal.ts,
/// https://studytutor.duckdns.org/privacy/ and /terms/) — change both
/// together and bump the date in both. Rewritten 2026-10-20: the old text
/// still promised a free built-in local model and predated the chat-file
/// cleanup, on-device chat history, backups and log retention.
class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key, required this.kind});

  final LegalDocumentKind kind;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sections = kind == LegalDocumentKind.terms ? _termsSections : _privacySections;
    return Scaffold(
      appBar: AppBar(title: Text(kind == LegalDocumentKind.terms ? 'Terms of Service' : 'Privacy Policy')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Last updated 20 October 2026. Study OS is a student project. This describes, in plain language, what '
            'the app actually does — it hasn’t been reviewed by a lawyer.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: 20),
          for (final (i, section) in sections.indexed) ...[
            Text('${i + 1}. ${section.$1}', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            for (final paragraph in section.$2) ...[
              Text(paragraph, style: theme.textTheme.bodyMedium?.copyWith(height: 1.6)),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

enum LegalDocumentKind { terms, privacy }

const _contact = 'davidmurunga27@gmail.com';

const _termsSections = <(String, List<String>)>[
  (
    'What Study OS is',
    [
      'Study OS is a study app for Android. It organises your study material into subjects, builds concepts, '
          'flashcards and practice questions from it, schedules review with spaced repetition, and lets you chat '
          'with Sage, an AI study buddy.',
      'The app is free. Its AI features use an API key you provide from Anthropic, OpenAI or DeepSeek. A free '
          'built-in AI model is in development.',
    ],
  ),
  (
    'Your account',
    [
      'Keep your password safe — you’re responsible for what happens under your account.',
      'You can delete your account at any time from Profile → Delete account. This permanently removes your '
          'subjects, material, practice and mastery history and everything else listed in the Privacy Policy, and '
          'can’t be undone.',
    ],
  ),
  (
    'Your AI provider',
    [
      'When you add an API key, your use of that provider is between you and them: their terms and prices apply '
          'and they bill you directly. Study OS doesn’t charge for these requests or add anything on top.',
    ],
  ),
  (
    'Your material',
    [
      'You keep ownership of everything you add. You allow Study OS to store and process it only to run the app '
          'for you — for example to read the text, search it, and build practice from it.',
      'Only add material you have the right to use.',
    ],
  ),
  (
    'Acceptable use',
    [
      'Don’t use Study OS to generate harmful content, to harass anyone, or to try to disrupt the service or get '
          'into accounts or systems that aren’t yours.',
    ],
  ),
  (
    'No warranty',
    [
      'Study OS is provided as it is. AI explanations, grading and practice questions can be wrong — check anything '
          'that matters for your actual coursework or exams.',
      'The service may change, be unavailable at times, or stop.',
    ],
  ),
  (
    'Changes to these terms',
    ['If these terms change, the date at the top changes too. Using Study OS after a change means you accept the new terms.'],
  ),
  (
    'Contact',
    ['Questions about these terms: $_contact.'],
  ),
];

const _privacySections = <(String, List<String>)>[
  (
    'What we store on our server',
    [
      'Your account: email address, display name, a securely hashed password (never the password itself), and any '
          'student-profile details you choose to add, like your course or institution.',
      'Your study data: your subjects and the material you add to them, concepts, practice and mastery history, '
          'flashcards, notes, goals and study sessions, your Sage personality settings, and things you’ve asked Sage '
          'to remember along with notable study events.',
    ],
  ),
  (
    'What stays on your phone',
    [
      'Your chat history with Sage is stored on your phone, not on our server.',
      'Your AI provider key is stored encrypted on your phone. It is never saved on our servers: it travels with a '
          'request only when that request needs it, and is used for that request only.',
      'If you choose to save chat pictures and PDFs, they are kept on your phone. The app asks first, and you can '
          'turn this off or delete them in Profile.',
    ],
  ),
  (
    'How your material and questions are used',
    [
      'Material you add is processed so it can be searched and turned into practice. When you ask Sage something, '
          'your question — and, when it helps, passages from your own material — is sent to the AI provider whose '
          'key you added, so it can answer.',
    ],
  ),
  (
    'How long we keep things',
    [
      'Your account and study data: until you delete them or your account.',
      'Files you send in a chat: our temporary copy is deleted within a day.',
      'Pictures and PDFs Sage makes in a chat: deleted from our server after about two weeks.',
      'Backups: made nightly and kept for 14 days.',
      'Server logs (IP address, time, and the address requested): kept for up to 30 days, for security and '
          'troubleshooting.',
      'Crash reports, if the app hits an error: the error, where in the app it happened, the app version and '
          'the kind of phone — never your notes, chats or what you typed. Kept for 30 days.',
    ],
  ),
  (
    'Who else is involved',
    [
      'Google, if you sign in with Google, to confirm who you are.',
      'Your AI provider (Anthropic, OpenAI or DeepSeek), for the questions you send with your key.',
      'Contabo, the company we rent our server from.',
      'We don’t sell your data, show ads, or use analytics or tracking in the app or on our website.',
    ],
  ),
  (
    'Our website',
    ['Our website uses no cookies. If you switch between light and dark mode there, that choice is saved in your own browser only.'],
  ),
  (
    'Deleting your data',
    [
      'Profile → Delete account removes your account and study data from our database straight away, and it '
          'disappears from backups within 14 days as they expire. Uninstalling the app removes what it kept on your '
          'phone.',
      'You can also ask us to delete your data, or ask what we hold about you, by emailing $_contact.',
    ],
  ),
  (
    'Changes to this policy',
    ['If this policy changes, the date at the top changes too.'],
  ),
];
