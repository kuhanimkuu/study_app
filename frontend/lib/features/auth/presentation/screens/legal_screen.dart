import 'package:flutter/material.dart';

/// Terms of Service / Privacy Policy — real, plain-language content
/// describing what this app actually does (accounts, BYOK keys stored
/// on-device, Postgres-stored study data, account deletion), not
/// placeholder lorem ipsum. Written for a small student project, not
/// legally reviewed — honest about that in-app rather than implying
/// otherwise. Reached from Signup's consent checkbox.
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
            'Last updated 2026-09-19. This is a student project, not a substitute for professional legal advice — '
            'it describes in plain language what the app actually does with your data.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: 20),
          for (final section in sections) ...[
            Text(section.$1, style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(section.$2, style: theme.textTheme.bodyMedium?.copyWith(height: 1.6)),
            const SizedBox(height: 20),
          ],
        ],
      ),
    );
  }
}

enum LegalDocumentKind { terms, privacy }

const _termsSections = <(String, String)>[
  (
    'What Study OS is',
    'Study OS is a study companion: it tracks concepts you\'re learning, schedules review with spaced '
        'repetition, generates practice questions and flashcards, and lets you chat with an AI moderator '
        'about your material. It\'s free to use with a built-in local model, or you can bring your own '
        'API key (Anthropic, OpenAI, or DeepSeek) for a different model.',
  ),
  (
    'Your account',
    'You\'re responsible for keeping your password secure. You can delete your account at any time from '
        'Profile — this permanently removes your Knowledge Spaces, materials, mastery data, memories, and '
        'history, and cannot be undone.',
  ),
  (
    'Acceptable use',
    'Don\'t use Study OS to upload material you don\'t have the right to use, to abuse the AI moderator to '
        'generate harmful content, or to attempt to disrupt or gain unauthorized access to the service.',
  ),
  (
    'No warranty',
    'Study OS is provided as-is. AI-generated explanations, grading, and practice questions can be wrong — '
        'always verify anything that matters for your actual coursework or exams.',
  ),
];

const _privacySections = <(String, String)>[
  (
    'What we store',
    'Your email, display name, and any student-profile fields you choose to fill in (education level, '
        'course, institution) are stored in our database. So is your study data: Knowledge Spaces, '
        'materials, concepts, mastery/practice history, flashcards, notes, and anything you\'ve explicitly '
        'asked the AI moderator to remember about you.',
  ),
  (
    'Your AI provider key stays on your device',
    'If you bring your own API key (Anthropic/OpenAI/DeepSeek), it\'s stored encrypted on your device only — '
        'never on our servers — and is sent, encrypted, only on the request that actually needs it.',
  ),
  (
    'Uploaded material',
    'PDFs and other material you upload are processed to extract text and generate embeddings for search — '
        'this content is stored so the AI moderator can answer questions about it later.',
  ),
  (
    'Third parties',
    'If you sign in with Google, we verify your identity through Google\'s sign-in service. If you use a '
        'bring-your-own-key model, your questions are sent to that provider (Anthropic/OpenAI/DeepSeek) using '
        'your key. Neither receives anything beyond what a normal request needs.',
  ),
  (
    'Deleting your data',
    'Deleting your account (Profile → Delete account) permanently removes everything listed above from our '
        'database. This is immediate and cannot be undone.',
  ),
];
