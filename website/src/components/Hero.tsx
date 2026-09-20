export default function Hero() {
  return (
    <section className="hero">
      <div className="container hero-inner">
        <div className="hero-copy">
          <span className="eyebrow">Free · local model or bring your own key</span>
          <h1>
            Ask anything.
            <br />
            Remember everything.
          </h1>
          <p className="hero-sub">
            Study OS turns whatever you're studying — a PDF, a photo of your notes, a plain question — into
            tracked concepts, spaced-repetition flashcards, real practice questions, and a study plan that
            adapts to what you actually know.
          </p>
          <div className="hero-cta">
            <a className="btn btn-primary btn-large" href="#get-started">
              Get the app
            </a>
            <a className="btn btn-ghost btn-large" href="#features">
              See what it does
            </a>
          </div>
          <ul className="hero-trust">
            <li>Free local AI model, no key required</li>
            <li>Or bring your own Anthropic / OpenAI / DeepSeek key</li>
            <li>Your data, deletable any time</li>
          </ul>
        </div>

        <div className="hero-art" aria-hidden="true">
          <div className="phone-frame">
            <div className="phone-notch"></div>
            <div className="phone-screen">
              <div className="mock-header">
                <div className="mock-avatar"></div>
                <div className="mock-lines">
                  <span className="mock-line short"></span>
                  <span className="mock-line"></span>
                </div>
                <div className="mock-streak">🔥 12</div>
              </div>
              <div className="mock-card mock-card-primary">
                <span className="mock-tag">THERMODYNAMICS</span>
                <span className="mock-line"></span>
                <div className="mock-bar">
                  <span style={{ width: '68%' }}></span>
                </div>
              </div>
              <div className="mock-row">
                <div className="mock-pill mock-pill-good"></div>
                <span className="mock-line short"></span>
              </div>
              <div className="mock-row">
                <div className="mock-pill"></div>
                <span className="mock-line short"></span>
              </div>
              <div className="mock-card mock-card-amber">
                <span className="mock-line short"></span>
                <div className="mock-chip">Review</div>
              </div>
              <div className="mock-navbar">
                <span></span>
                <span></span>
                <div className="mock-fab"></div>
                <span></span>
                <span></span>
              </div>
            </div>
          </div>
          <div className="hero-glow"></div>
        </div>
      </div>
    </section>
  )
}
