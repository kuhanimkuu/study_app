import type { ReactNode } from 'react'

interface Feature {
  icon: ReactNode
  iconClass: string
  title: string
  body: string
  large?: boolean
}

const FEATURES: Feature[] = [
  {
    large: true,
    iconClass: 'icon-blue',
    title: 'An AI moderator that actually teaches',
    body: "Ask a question in plain language, upload a PDF or a photo of a textbook page, or start a guided session — get back rendered equations, interactive graphs, diagrams, and tables, not just a wall of text.",
    icon: (
      <svg viewBox="0 0 24 24" width={22} height={22} fill="none" stroke="currentColor" strokeWidth={1.8}>
        <path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20" />
        <path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2Z" />
      </svg>
    ),
  },
  {
    iconClass: 'icon-green',
    title: 'Real spaced repetition',
    body: 'Concepts and flashcards are scheduled with FSRS, the same algorithm behind modern SRS apps — reviews land right before you\'d forget.',
    icon: (
      <svg viewBox="0 0 24 24" width={22} height={22} fill="none" stroke="currentColor" strokeWidth={1.8}>
        <circle cx={12} cy={12} r={9} />
        <path d="M12 7v5l3 3" />
      </svg>
    ),
  },
  {
    iconClass: 'icon-amber',
    title: '10 question types',
    body: 'Multiple choice, numerical, equation, matching, ordering, essay, and more — practice one at a time or run a full quiz in exam mode.',
    icon: (
      <svg viewBox="0 0 24 24" width={22} height={22} fill="none" stroke="currentColor" strokeWidth={1.8}>
        <path d="M9 3H5a2 2 0 0 0-2 2v4" />
        <path d="M15 3h4a2 2 0 0 1 2 2v4" />
        <path d="M9 21H5a2 2 0 0 1-2-2v-4" />
        <path d="M15 21h4a2 2 0 0 0 2-2v-4" />
      </svg>
    ),
  },
  {
    iconClass: 'icon-purple',
    title: 'A real knowledge graph',
    body: 'Link concepts as "requires", "related to", or "tested by" — Study OS uses those links to prioritize what you should review first.',
    icon: (
      <svg viewBox="0 0 24 24" width={22} height={22} fill="none" stroke="currentColor" strokeWidth={1.8}>
        <circle cx={6} cy={6} r={2.5} />
        <circle cx={18} cy={6} r={2.5} />
        <circle cx={12} cy={18} r={2.5} />
        <path d="M8.2 7.3 10.5 16M15.8 7.3 13.5 16M8.5 6h7" />
      </svg>
    ),
  },
  {
    iconClass: 'icon-blue',
    title: 'Planner that adapts',
    body: 'Set goals, generate a prioritized study plan for the time you have, and track it on a real calendar alongside review dates and deadlines.',
    icon: (
      <svg viewBox="0 0 24 24" width={22} height={22} fill="none" stroke="currentColor" strokeWidth={1.8}>
        <rect x={3} y={4} width={18} height={18} rx={2} />
        <path d="M3 10h18M8 2v4M16 2v4" />
      </svg>
    ),
  },
  {
    iconClass: 'icon-green',
    title: 'Progress you can see',
    body: 'Streaks, weekly study time, mastery trends by subject, and your strongest and weakest concepts — all from real activity, never a fabricated number.',
    icon: (
      <svg viewBox="0 0 24 24" width={22} height={22} fill="none" stroke="currentColor" strokeWidth={1.8}>
        <path d="M3 3v18h18" />
        <path d="M7 15l4-5 3 3 5-7" />
      </svg>
    ),
  },
]

export default function Features() {
  return (
    <section className="section" id="features">
      <div className="container">
        <div className="section-head">
          <span className="eyebrow">Features</span>
          <h2>Everything a real study session needs</h2>
          <p>Not a chatbot bolted onto flashcards — every piece feeds the others.</p>
        </div>

        <div className="feature-grid">
          {FEATURES.map((feature) => (
            <article className={`feature-card${feature.large ? ' feature-card-lg' : ''}`} key={feature.title}>
              <div className={`feature-icon ${feature.iconClass}`}>{feature.icon}</div>
              <h3>{feature.title}</h3>
              <p>{feature.body}</p>
            </article>
          ))}
        </div>
      </div>
    </section>
  )
}
