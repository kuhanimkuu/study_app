const MODELS: Array<{ label: string; free?: boolean }> = [
  { label: 'Local model', free: true },
  { label: 'Anthropic Claude' },
  { label: 'OpenAI GPT' },
  { label: 'DeepSeek' },
]

export default function ModelStrip() {
  return (
    <section className="model-strip" aria-label="Supported AI backends">
      <div className="container model-strip-inner">
        <span className="model-strip-label">Runs on</span>
        {MODELS.map((model) => (
          <div className="model-chip" key={model.label}>
            {model.label}
            {model.free && <em>free</em>}
          </div>
        ))}
      </div>
    </section>
  )
}
