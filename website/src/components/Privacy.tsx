const KEY_ROWS: Array<{ label: string; dot: string; badge: string; muted?: boolean }> = [
  { label: 'Local model', dot: 'dot-green', badge: 'Free' },
  { label: 'Anthropic Claude', dot: 'dot-blue', badge: 'BYOK', muted: true },
  { label: 'OpenAI GPT', dot: 'dot-purple', badge: 'BYOK', muted: true },
  { label: 'DeepSeek', dot: 'dot-amber', badge: 'BYOK', muted: true },
]

export default function Privacy() {
  return (
    <section className="section" id="privacy">
      <div className="container privacy-grid">
        <div className="privacy-copy">
          <span className="eyebrow">Privacy &amp; BYOK</span>
          <h2>Your key. Your data. Your call.</h2>
          <p>
            Study OS runs on a free, built-in local model by default — no account with an AI provider
            needed. Prefer a stronger model? Bring your own Anthropic, OpenAI, or DeepSeek API key.
          </p>
          <ul className="privacy-list">
            <li>
              <strong>Your key never touches our servers.</strong> It's encrypted on your device and sent
              only, per-request, to the provider you chose.
            </li>
            <li>
              <strong>You can delete everything, any time.</strong> Account deletion removes your study
              spaces, materials, mastery history, and memories — permanently.
            </li>
            <li>
              <strong>No number on this site — or in the app — is made up.</strong> Every stat you see is
              computed from your own real activity.
            </li>
          </ul>
        </div>
        <div className="privacy-art" aria-hidden="true">
          <div className="key-card">
            {KEY_ROWS.map((row) => (
              <div className="key-row" key={row.label}>
                <span className={`dot ${row.dot}`}></span>
                {row.label}
                <span className={`key-badge${row.muted ? ' key-badge-muted' : ''}`}>{row.badge}</span>
              </div>
            ))}
            <div className="key-field">
              <svg viewBox="0 0 24 24" width={16} height={16} fill="none" stroke="currentColor" strokeWidth={1.8}>
                <rect x={3} y={11} width={18} height={10} rx={2} />
                <path d="M7 11V7a5 5 0 0 1 10 0v4" />
              </svg>
              <span>sk-••••••••••••9f2a</span>
            </div>
          </div>
        </div>
      </div>
    </section>
  )
}
