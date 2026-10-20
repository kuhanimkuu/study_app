// Terms of Service and Privacy Policy. The SAME text is shown in the app
// (frontend/lib/features/auth/presentation/screens/legal_screen.dart) —
// change both together, and bump the date in both.
//
// Every statement here describes what the code actually does (checked
// 2026-10-20): BYOK keys never reach the server, chat history lives on the
// phone, chat uploads go after a day, chat-made files after ~14 days
// (server/workers/cleanup.py), nightly backups kept 14 days and server logs
// 30 days (setup_server.sh).

import { site } from '../site'

export const legalUpdated = '20 October 2026'

export const legalNote =
  'Study OS is a student project. These pages describe, in plain language, what the app actually does — they haven’t been reviewed by a lawyer.'

export type LegalSection = { title: string; body: string[] }

export const terms: LegalSection[] = [
  {
    title: 'What Study OS is',
    body: [
      'Study OS is a study app for Android. It organises your study material into subjects, builds concepts, flashcards and practice questions from it, schedules review with spaced repetition, and lets you chat with Sage, an AI study buddy.',
      'The app is free. Its AI features use an API key you provide from Anthropic, OpenAI or DeepSeek. A free built-in AI model is in development.',
    ],
  },
  {
    title: 'Your account',
    body: [
      'Keep your password safe — you’re responsible for what happens under your account.',
      'You can delete your account at any time from Profile → Delete account. This permanently removes your subjects, material, practice and mastery history and everything else listed in the Privacy Policy, and can’t be undone.',
    ],
  },
  {
    title: 'Your AI provider',
    body: [
      'When you add an API key, your use of that provider is between you and them: their terms and prices apply and they bill you directly. Study OS doesn’t charge for these requests or add anything on top.',
    ],
  },
  {
    title: 'Your material',
    body: [
      'You keep ownership of everything you add. You allow Study OS to store and process it only to run the app for you — for example to read the text, search it, and build practice from it.',
      'Only add material you have the right to use.',
    ],
  },
  {
    title: 'Acceptable use',
    body: [
      'Don’t use Study OS to generate harmful content, to harass anyone, or to try to disrupt the service or get into accounts or systems that aren’t yours.',
    ],
  },
  {
    title: 'No warranty',
    body: [
      'Study OS is provided as it is. AI explanations, grading and practice questions can be wrong — check anything that matters for your actual coursework or exams.',
      'The service may change, be unavailable at times, or stop.',
    ],
  },
  {
    title: 'Changes to these terms',
    body: ['If these terms change, the date at the top changes too. Using Study OS after a change means you accept the new terms.'],
  },
  {
    title: 'Contact',
    body: [`Questions about these terms: ${site.contactEmail}.`],
  },
]

export const privacy: LegalSection[] = [
  {
    title: 'What we store on our server',
    body: [
      'Your account: email address, display name, a securely hashed password (never the password itself), and any student-profile details you choose to add, like your course or institution.',
      'Your study data: your subjects and the material you add to them, concepts, practice and mastery history, flashcards, notes, goals and study sessions, your Sage personality settings, and things you’ve asked Sage to remember along with notable study events.',
    ],
  },
  {
    title: 'What stays on your phone',
    body: [
      'Your chat history with Sage is stored on your phone, not on our server.',
      'Your AI provider key is stored encrypted on your phone. It is never saved on our servers: it travels with a request only when that request needs it, and is used for that request only.',
      'If you choose to save chat pictures and PDFs, they are kept on your phone. The app asks first, and you can turn this off or delete them in Profile.',
    ],
  },
  {
    title: 'How your material and questions are used',
    body: [
      'Material you add is processed so it can be searched and turned into practice. When you ask Sage something, your question — and, when it helps, passages from your own material — is sent to the AI provider whose key you added, so it can answer.',
    ],
  },
  {
    title: 'How long we keep things',
    body: [
      'Your account and study data: until you delete them or your account.',
      'Files you send in a chat: our temporary copy is deleted within a day.',
      'Pictures and PDFs Sage makes in a chat: deleted from our server after about two weeks.',
      'Backups: made nightly and kept for 14 days.',
      'Server logs (IP address, time, and the address requested): kept for up to 30 days, for security and troubleshooting.',
    ],
  },
  {
    title: 'Who else is involved',
    body: [
      'Google, if you sign in with Google, to confirm who you are.',
      'Your AI provider (Anthropic, OpenAI or DeepSeek), for the questions you send with your key.',
      'Contabo, the company we rent our server from.',
      'We don’t sell your data, show ads, or use analytics or tracking in the app or on this website.',
    ],
  },
  {
    title: 'This website',
    body: ['This website uses no cookies. If you switch between light and dark mode, that choice is saved in your own browser only.'],
  },
  {
    title: 'Deleting your data',
    body: [
      'Profile → Delete account removes your account and study data from our database straight away, and it disappears from backups within 14 days as they expire. Uninstalling the app removes what it kept on your phone.',
      `You can also ask us to delete your data, or ask what we hold about you, by emailing ${site.contactEmail}.`,
    ],
  },
  {
    title: 'Changes to this policy',
    body: ['If this policy changes, the date at the top changes too.'],
  },
]
