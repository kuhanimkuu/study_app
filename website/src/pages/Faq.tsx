import type { ReactNode } from 'react'
import { CtaBand, PageHero } from '../components/ui'
import { site } from '../site'

type QA = { q: string; a: ReactNode }

const GROUPS: { title: string; items: QA[] }[] = [
  {
    title: 'Getting started',
    items: [
      { q: 'Is Study OS free?', a: <>Yes — the app is free. AI answers run on your own API key from DeepSeek, OpenAI or Anthropic, and you pay that provider directly for what you use. A free built-in AI is in development. <a href="/ai/">More about keys</a>.</> },
      { q: 'What phones does it work on?', a: `Android phones running ${site.minAndroid.replace(' or newer', '')} or newer. There’s no iPhone version yet.` },
      { q: 'Why isn’t it on the Play Store?', a: <>It’s distributed directly from this site for now, so Android asks you to allow the install. <a href="/download/">Install help</a>.</> },
      { q: 'Does it work offline?', a: 'No — Study OS needs an internet connection.' },
    ],
  },
  {
    title: 'AI & keys',
    items: [
      { q: 'What is an API key and how do I get one?', a: <>It’s a password-like code from an AI provider that lets an app use their AI on your account. <a href="/ai/">Our step-by-step guide</a> covers DeepSeek, OpenAI and Anthropic.</> },
      { q: 'Which provider should I choose?', a: 'Any of the three works. If you’re not sure, the app suggests DeepSeek. You can switch any time in Profile → AI model.' },
      { q: 'Do I need a key for everything?', a: 'No. Your own flashcards, notes, study plans and progress tracking work without one. Explanations, generated practice and grading of written answers use your key.' },
      { q: 'Is my API key safe?', a: 'It’s stored encrypted on your phone, sent only with your own questions, used for that one request, and never saved on our server.' },
      { q: 'Can Sage get things wrong?', a: 'Yes — AI explanations, grading and generated questions can be wrong. Double-check anything important for your coursework or exams.' },
    ],
  },
  {
    title: 'Privacy & your data',
    items: [
      { q: 'Where is my data stored?', a: <>Your account and study data are on the Study OS server, so they survive a new phone. Your chat history stays on your phone. The <a href="/privacy/">Privacy Policy</a> has the details.</> },
      { q: 'Do you sell my data or show ads?', a: 'No. There are no ads, and no analytics or tracking in the app or on this website.' },
      { q: 'Can I delete my account?', a: 'Yes. Profile → Delete account removes your account and study data straight away, and it disappears from backups within 14 days.' },
      { q: 'Does the app take up space on my phone?', a: 'A little. Pictures and PDFs from chats are only saved on your phone if you say yes — Profile shows the space used and lets you clear it.' },
    ],
  },
  {
    title: 'Using the app',
    items: [
      { q: 'What can I add to a subject?', a: 'PDFs, pasted text and web links. Study OS reads them, splits them into concepts and builds flashcards and quizzes from them.' },
      { q: 'What can I send Sage in a chat?', a: 'Text, photos (including handwriting and maths), PDFs, voice notes and web links.' },
      { q: 'How do flashcards decide when to come back?', a: 'Each review you rate Again, Hard, Good or Easy, and the FSRS spaced-repetition scheduler picks the next date — right before you’d otherwise forget.' },
      { q: 'I skipped the tour — can I see it again?', a: 'Yes: Profile → Take the app tour.' },
    ],
  },
]

export default function Faq() {
  return (
    <>
      <PageHero eyebrow="FAQ" icon="chat" title={<>Questions, <span className="accent">answered</span></>} lead={<>Can’t find what you need? Email <a href={`mailto:${site.contactEmail}`}>{site.contactEmail}</a>.</>} mood="thinking" />
      <section className="section section-tight">
        <div className="container narrow">
          {GROUPS.map((group) => (
            <div className="faq-group" key={group.title}>
              <h2>{group.title}</h2>
              <div className="faq">
                {group.items.map((item) => (
                  <details key={item.q}>
                    <summary>{item.q}</summary>
                    <p>{item.a}</p>
                  </details>
                ))}
              </div>
            </div>
          ))}
        </div>
      </section>
      <CtaBand />
    </>
  )
}
