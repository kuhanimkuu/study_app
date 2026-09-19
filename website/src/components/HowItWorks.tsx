const STEPS = [
  {
    title: 'Create a study space',
    body: 'One per subject or course. Drop in PDFs, notes, or paste text — Study OS indexes it for search and for the AI moderator to reference.',
  },
  {
    title: 'Let it build the structure',
    body: 'Add concepts as you go, write flashcards, author questions — or ask the moderator to explain something and turn the conversation into material.',
  },
  {
    title: 'Study what actually needs it',
    body: "Home shows a real plan built from your mastery data: what's due, what's weak, and how long you've got — not a generic checklist.",
  },
]

export default function HowItWorks() {
  return (
    <section className="section section-alt" id="how-it-works">
      <div className="container">
        <div className="section-head">
          <span className="eyebrow">How it works</span>
          <h2>From material to mastery in three steps</h2>
        </div>

        <ol className="steps">
          {STEPS.map((step, index) => (
            <li className="step" key={step.title}>
              <span className="step-num">{index + 1}</span>
              <h3>{step.title}</h3>
              <p>{step.body}</p>
            </li>
          ))}
        </ol>
      </div>
    </section>
  )
}
