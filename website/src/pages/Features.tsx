import Icon from '../components/Icon'
import { Checks, CtaBand, FlashcardDemo, PageHero, Phone, Tag } from '../components/ui'

// Every bullet here maps to something that exists in the app (checked
// against the code 2026-10-20). AI-powered items need the student's own key
// — the page says so once, near the top.

const QUESTION_TYPES = [
  'Multiple choice',
  'True / false',
  'Fill in the blank',
  'Multi-select',
  'Numerical',
  'Equation',
  'Matching',
  'Ordering',
  'Short answer',
  'Essay',
]

export default function Features() {
  return (
    <>
      <PageHero
        eyebrow="Features"
        icon="bolt"
        title={
          <>
            Everything Study OS <span className="accent">can do</span>
          </>
        }
        lead="From the moment you add your notes to the day of the exam: organise, understand, practise and keep track — with Sage at your side."
        mood="cheer"
      >
        <nav className="pill-nav" aria-label="On this page">
          <a href="#subjects">Subjects</a>
          <a href="#sage">Chat with Sage</a>
          <a href="#practice">Practice</a>
          <a href="#plan">Plan & progress</a>
          <a href="#personal">Made for you</a>
        </nav>
      </PageHero>

      <div className="container">
        <p className="note-box">
          <Icon name="key" size={20} />
          <span>
            Features marked <strong>AI</strong> use the API key you add in the app — see <a href="/ai/">AI & keys</a>. Everything else works without one.
          </span>
        </p>

        <section className="feature anchor" id="subjects">
          <div className="feature-text">
            <Tag icon="book" color="var(--success)">
              Subjects
            </Tag>
            <h2>Your notes, turned into a course</h2>
            <p>Make a subject for each course or topic, then add your material. Each subject keeps its own colour, concepts, flashcards, notes and chat.</p>
            <Checks
              color="var(--success)"
              items={[
                'Add PDFs, pasted text or web links — and open your originals any time',
                <>Concepts, flashcards and practice questions generated from your material <em className="ai-pill">AI</em></>,
                <>Ask questions about a subject and get answers that cite your own notes <em className="ai-pill">AI</em></>,
                'Search everything in a subject by meaning, not just keywords',
                'Make PDFs from a subject: study guides, revision notes, summaries, formula sheets, worksheets, flashcards and practice exams',
                'Your own notes, right next to your material',
              ]}
            />
          </div>
          <div className="feature-visual">
            <Phone src="/screens/welcome.webp" alt="Sage welcoming a new student with three steps: create a subject, add your notes, practise and grow" />
          </div>
        </section>

        <section className="feature flip anchor" id="sage">
          <div className="feature-text">
            <Tag icon="chat" color="var(--primary)">
              Chat with Sage
            </Tag>
            <h2>Ask anything — any way you like</h2>
            <p>Sage is your study buddy: he explains, works through problems with you, and checks you’ve understood.</p>
            <Checks
              color="var(--primary)"
              items={[
                <>
                  <strong>Photos:</strong> printed text, handwriting, maths, tables, graphs and diagrams
                </>,
                <>
                  <strong>PDFs, voice notes and web links</strong> — Sage reads, listens and fetches
                </>,
                <>
                  <strong>Maths:</strong> solve, simplify, differentiate, integrate and graph — including interactive graphs and unit conversion
                </>,
                <>Explanations, diagrams of processes and quick quizzes <em className="ai-pill">AI</em></>,
                <>Study guides, practice exams and flashcards as downloadable PDFs <em className="ai-pill">AI</em></>,
                'Looks things up on the web when you ask about something current',
                'Every chat saved on your phone — or turned into a new subject',
              ]}
            />
          </div>
          <div className="feature-visual">
            <Phone src="/screens/chat.webp" alt="A chat where Sage explains mitosis in four phases and then starts a quiz" />
          </div>
        </section>

        <section className="feature anchor" id="practice">
          <div className="feature-text">
            <Tag icon="bolt" color="var(--xp)">
              Practice
            </Tag>
            <h2>Practice that actually sticks</h2>
            <p>Study OS tracks your mastery of every concept and brings things back right before you’d forget them.</p>
            <Checks
              color="var(--xp)"
              items={[
                'Flashcards scheduled with FSRS spaced repetition — rate each one Again, Hard, Good or Easy',
                'Quizzes with ten kinds of questions, plus an exam mode that gives feedback only at the end',
                <>Written answers and essays graded with feedback <em className="ai-pill">AI</em></>,
                'A mastery score for every concept, and a heads-up when you keep making the same mistake',
              ]}
            />
            <div className="type-chips" aria-label="Question types">
              {QUESTION_TYPES.map((t) => (
                <span key={t}>{t}</span>
              ))}
            </div>
          </div>
          <div className="feature-visual">
            <FlashcardDemo />
          </div>
        </section>

        <section className="feature flip anchor" id="plan">
          <div className="feature-text">
            <Tag icon="calendar" color="var(--streak)">
              Plan & progress
            </Tag>
            <h2>Know exactly what to study next</h2>
            <p>Open the app and your home screen already knows: today’s goal, your streak, cards due, and the topics that need you most.</p>
            <Checks
              color="var(--streak)"
              items={[
                'A daily goal and a study streak to keep you going',
                'A study plan built around your weakest concepts, with one tap to start',
                'Goals with target dates, and study sessions on a calendar',
                'A progress screen with your strongest and weakest topics',
              ]}
            />
          </div>
          <div className="feature-visual">
            <Phone src="/screens/home_dark.webp" alt="The home screen in dark mode with the daily goal, streak and subjects" dark />
          </div>
        </section>

        <section className="section anchor" id="personal">
          <div className="section-head">
            <Tag icon="person" color="var(--pink)">
              Made for you
            </Tag>
            <h2>Sage adapts to how you learn</h2>
          </div>
          <div className="mini-grid">
            <div className="mini-card">
              <Icon name="gear" size={26} />
              <h3>Your kind of tutor</h3>
              <p>Set Sage’s tone, how much detail he gives, how much he challenges you, how he teaches — even how funny he is.</p>
            </div>
            <div className="mini-card">
              <Icon name="person" size={26} />
              <h3>He remembers</h3>
              <p>Tell Sage things to remember about you, and he keeps them in mind in every chat. You can see and remove them any time.</p>
            </div>
            <div className="mini-card">
              <Icon name="flame" size={26} />
              <h3>A guided start</h3>
              <p>The first time you open the app, Sage walks you through every part of it. Replay the tour from Profile whenever you like.</p>
            </div>
            <div className="mini-card">
              <Icon name="moon" size={26} />
              <h3>Light and dark</h3>
              <p>Follows your phone’s setting, so late-night revision is easy on the eyes.</p>
            </div>
            <div className="mini-card">
              <Icon name="phone" size={26} />
              <h3>Your storage, your call</h3>
              <p>Chat pictures and PDFs can be saved on your phone — only if you say yes, with the space used shown in Profile.</p>
            </div>
            <div className="mini-card">
              <Icon name="shield" size={26} />
              <h3>Leave any time</h3>
              <p>Delete your account from Profile and everything goes with it. Read the <a href="/privacy/">Privacy Policy</a>.</p>
            </div>
          </div>
        </section>
      </div>

      <CtaBand />
    </>
  )
}
