import Icon, { type IconName } from '../components/Icon'
import Sage from '../components/Sage'
import { CtaBand, FlashcardDemo, Phone, Tag } from '../components/ui'
import { site } from '../site'

const STRIP: { icon: IconName; color: string; title: string; text: string }[] = [
  { icon: 'bolt', color: 'var(--xp)', title: '10 question types', text: 'From multiple choice to essays' },
  { icon: 'target', color: 'var(--success)', title: 'Spaced repetition', text: 'FSRS schedules every flashcard' },
  { icon: 'camera', color: 'var(--teal)', title: 'Photo, PDF, voice, links', text: 'Sage reads them all' },
  { icon: 'flame', color: 'var(--streak)', title: 'Streaks & daily goals', text: 'Small wins, every day' },
]

const TEASERS: { icon: IconName; color: string; tag: string; title: string; text: string; href: string; visual: 'phone' | 'deck'; src?: string; alt?: string; dark?: boolean }[] = [
  {
    icon: 'book',
    color: 'var(--success)',
    tag: 'Subjects',
    title: 'Your notes, turned into a course',
    text: 'Add PDFs, notes or links to a subject. Study OS breaks them into concepts and builds flashcards and quizzes from them.',
    href: '/features/#subjects',
    visual: 'phone',
    src: '/screens/welcome.webp',
    alt: 'Sage welcoming a new student with three steps: create a subject, add your notes, practise and grow',
  },
  {
    icon: 'chat',
    color: 'var(--primary)',
    tag: 'Chat with Sage',
    title: 'Ask anything — any way you like',
    text: 'Snap a photo, send a PDF or a voice note, or just type. Sage explains step by step and quizzes you on the spot.',
    href: '/features/#sage',
    visual: 'phone',
    src: '/screens/chat.webp',
    alt: 'A chat where Sage explains mitosis in four phases and then starts a quiz',
  },
  {
    icon: 'bolt',
    color: 'var(--xp)',
    tag: 'Practice',
    title: 'Practice that actually sticks',
    text: 'Flashcards come back right before you’d forget them, and quizzes cover ten kinds of questions.',
    href: '/features/#practice',
    visual: 'deck',
  },
]

const STEPS: { icon: IconName; color: string; title: string; text: string }[] = [
  { icon: 'book', color: 'var(--primary)', title: 'Create a subject', text: 'One for each course or topic you’re studying.' },
  { icon: 'pdf', color: 'var(--xp)', title: 'Add your notes', text: 'PDFs, pasted text or web links — Study OS reads them for you.' },
  { icon: 'bolt', color: 'var(--success)', title: 'Practise and grow', text: 'Flashcards, quizzes and a plan built from your own material.' },
]

export default function Home() {
  return (
    <>
      <section className="hero">
        <div className="container hero-grid">
          <div>
            <span className="eyebrow">
              <Icon name="flame" size={16} /> Your study buddy for Android
            </span>
            <h1>
              Study smarter <span className="accent">with Sage</span>
            </h1>
            <p className="hero-lead">
              Turn your notes into flashcards, quizzes and a study plan — and ask Sage, your AI study buddy, about anything. Snap a photo, drop in a PDF, or just talk.
            </p>
            <div className="hero-ctas">
              <a className="btn btn-success" href={site.apkUrl} download>
                <Icon name="download" /> Download for Android
              </a>
              <a className="btn btn-ghost" href="/features/">
                See what it does
              </a>
            </div>
            <p className="hero-note">
              Free app · {site.minAndroid} · AI answers use your own key (<a href="/ai/">why?</a>)
            </p>
          </div>
          <div className="hero-visual">
            <div className="hero-blob" />
            <Phone src="/screens/home.webp" alt="The Study OS home screen: daily goal, a Continue learning card and colourful subject tiles" eager />
            <Sage size={120} mood="cheer" className="hero-sage" />
          </div>
        </div>
      </section>

      <section className="container" aria-label="Highlights">
        <div className="strip">
          {STRIP.map((item) => (
            <div className="strip-item" key={item.title}>
              <div className="strip-icon" style={{ background: item.color }}>
                <Icon name={item.icon} />
              </div>
              <div>
                <strong>{item.title}</strong>
                <span>{item.text}</span>
              </div>
            </div>
          ))}
        </div>
      </section>

      <section className="section">
        <div className="container">
          <div className="section-head">
            <span className="eyebrow">What it does</span>
            <h2>Everything you need to actually learn it</h2>
            <p>Not just answers — a system that remembers what you know, what you don’t, and what to do next.</p>
          </div>
          {TEASERS.map((t, i) => (
            <div className={`feature${i % 2 ? ' flip' : ''}`} key={t.tag}>
              <div className="feature-text">
                <Tag icon={t.icon} color={t.color}>
                  {t.tag}
                </Tag>
                <h3>{t.title}</h3>
                <p>{t.text}</p>
                <a className="more-link" href={t.href}>
                  Learn more →
                </a>
              </div>
              <div className="feature-visual">{t.visual === 'deck' ? <FlashcardDemo /> : <Phone src={t.src!} alt={t.alt!} dark={t.dark} />}</div>
            </div>
          ))}
          <div style={{ textAlign: 'center', marginTop: 24 }}>
            <a className="btn btn-ghost" href="/features/">
              See every feature
            </a>
          </div>
        </div>
      </section>

      <section className="section section-tight">
        <div className="container">
          <div className="section-head">
            <span className="eyebrow">How it works</span>
            <h2>From notes to mastery in three steps</h2>
            <p>New here? Sage gives you a quick tour of the app the first time you open it.</p>
          </div>
          <div className="steps">
            {STEPS.map((step) => (
              <div className="step" key={step.title}>
                <div className="step-icon" style={{ background: step.color }}>
                  <Icon name={step.icon} size={28} />
                </div>
                <h3>{step.title}</h3>
                <p>{step.text}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      <section className="section section-tight">
        <div className="container">
          <div className="ai-teaser">
            <div className="ai-teaser-icon">
              <Icon name="key" size={30} />
            </div>
            <div>
              <h3>Sage runs on the AI you choose</h3>
              <p>
                Add your own key from DeepSeek, OpenAI or Anthropic — it stays encrypted on your phone, and you pay the provider directly for what you use. A free built-in AI is in development.
              </p>
            </div>
            <a className="btn btn-ghost btn-small" href="/ai/">
              How keys work
            </a>
          </div>
        </div>
      </section>

      <CtaBand />
    </>
  )
}
