const FAQ_ITEMS = [
  {
    question: 'Do I need to pay for anything?',
    answer:
      "No. The built-in local model is free with no account or API key. Bringing your own key (Anthropic, OpenAI, or DeepSeek) is optional, for a stronger model — you pay that provider directly, Study OS doesn't take a cut.",
  },
  {
    question: 'What platforms does it run on?',
    answer:
      'Android today, built with Flutter. The backend is a standard REST API, so other platforms are possible later — nothing about the architecture is Android-specific.',
  },
  {
    question: 'Is my study material private?',
    answer:
      'Your account and study data live in a Postgres database you (or whoever hosts your instance) control. BYOK API keys are encrypted on-device and never stored on the server. See the in-app Terms of Service and Privacy Policy for the full detail.',
  },
  {
    question: 'Can I delete my account?',
    answer:
      "Yes, any time, from Profile. It permanently removes your study spaces, materials, mastery history, and memories — there's no soft-delete or recovery window.",
  },
]

export default function Faq() {
  return (
    <section className="section" id="faq">
      <div className="container">
        <div className="section-head">
          <span className="eyebrow">FAQ</span>
          <h2>Good to know</h2>
        </div>

        <div className="faq-list">
          {FAQ_ITEMS.map((item) => (
            <details className="faq-item" key={item.question}>
              <summary>{item.question}</summary>
              <p>{item.answer}</p>
            </details>
          ))}
        </div>
      </div>
    </section>
  )
}
