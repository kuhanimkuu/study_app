import Icon from '../components/Icon'
import { CtaBand, PageHero } from '../components/ui'

// Key pages are the same ones the app links to (model_unavailable_block.dart).
// No prices on purpose — providers change them; link to their pricing pages.
const PROVIDERS = [
  {
    name: 'DeepSeek',
    color: 'var(--teal)',
    blurb: 'A good place to start — the app suggests it if you’re not sure.',
    keyUrl: 'https://platform.deepseek.com/api_keys',
    pricingUrl: 'https://api-docs.deepseek.com/quick_start/pricing',
    steps: ['Sign up at platform.deepseek.com', 'Add a little credit under Top up', 'Open API keys → Create new API key, and copy it'],
  },
  {
    name: 'OpenAI (GPT)',
    color: 'var(--success)',
    blurb: 'The company behind ChatGPT. A ChatGPT subscription doesn’t include API use — it’s billed separately.',
    keyUrl: 'https://platform.openai.com/api-keys',
    pricingUrl: 'https://openai.com/api/pricing/',
    steps: ['Sign up at platform.openai.com', 'Add credit under Settings → Billing', 'Open API keys → Create new secret key, and copy it'],
  },
  {
    name: 'Anthropic (Claude)',
    color: 'var(--streak)',
    blurb: 'The makers of Claude. Like OpenAI, API use is billed separately from any Claude subscription.',
    keyUrl: 'https://console.anthropic.com/settings/keys',
    pricingUrl: 'https://www.anthropic.com/pricing#api',
    steps: ['Sign up at console.anthropic.com', 'Add credit under Billing', 'Open API keys → Create key, and copy it'],
  },
]

export default function Ai() {
  return (
    <>
      <PageHero
        eyebrow="AI & keys"
        icon="key"
        title={
          <>
            Sage runs on <span className="accent">the AI you choose</span>
          </>
        }
        lead="Study OS doesn’t charge for AI. Instead, you add your own API key from an AI provider, and pay them directly for what you use."
        mood="thinking"
      />

      <section className="section section-tight">
        <div className="container">
          <div className="explain-grid">
            <div className="mini-card">
              <Icon name="key" size={26} />
              <h3>What’s an API key?</h3>
              <p>A password-like code from an AI company that lets an app use their AI on your account. You create it on their website and paste it into Study OS.</p>
            </div>
            <div className="mini-card">
              <Icon name="wallet" size={26} />
              <h3>What does it cost?</h3>
              <p>Providers charge per use, from credit you add to your account with them. There’s no subscription to Study OS, and we don’t add anything on top.</p>
            </div>
            <div className="mini-card">
              <Icon name="lock" size={26} />
              <h3>Is my key safe?</h3>
              <p>It’s stored encrypted on your phone, sent only with your own questions, used for that one request, and never saved on our server.</p>
            </div>
          </div>
        </div>
      </section>

      <section className="section section-tight">
        <div className="container">
          <div className="section-head">
            <span className="eyebrow">Step 1</span>
            <h2>Get a key from one provider</h2>
            <p>You only need one. Each takes a few minutes.</p>
          </div>
          <div className="provider-cards">
            {PROVIDERS.map((p) => (
              <article className="provider-card" key={p.name}>
                <div className="provider-card-head">
                  <span className="dot" style={{ background: p.color }} />
                  <h3>{p.name}</h3>
                </div>
                <p className="muted">{p.blurb}</p>
                <ol>
                  {p.steps.map((s) => (
                    <li key={s}>{s}</li>
                  ))}
                </ol>
                <div className="provider-links">
                  <a className="btn btn-small" href={p.keyUrl} target="_blank" rel="noreferrer">
                    Get a key
                  </a>
                  <a href={p.pricingUrl} target="_blank" rel="noreferrer">
                    Their prices →
                  </a>
                </div>
              </article>
            ))}
          </div>
        </div>
      </section>

      <section className="section section-tight">
        <div className="container narrow">
          <div className="section-head">
            <span className="eyebrow">Step 2</span>
            <h2>Add it to Study OS</h2>
          </div>
          <ol className="number-steps">
            <li>
              <strong>Open Profile</strong>
              <span>Tap your initial in the top-right corner of the Home screen.</span>
            </li>
            <li>
              <strong>Choose your provider under AI model</strong>
              <span>DeepSeek, OpenAI GPT or Anthropic Claude.</span>
            </li>
            <li>
              <strong>Paste your key and tap Save</strong>
              <span>That’s it — ask Sage anything. You can change provider or key any time.</span>
            </li>
          </ol>
          <p className="note-box">
            <Icon name="shield" size={20} />
            <span>Treat your key like a password: don’t share it, and if you think it leaked, delete it on the provider’s website and create a new one.</span>
          </p>
        </div>
      </section>

      <section className="section section-tight">
        <div className="container narrow">
          <div className="soon-card">
            <span className="badge badge-soon">In development</span>
            <h3>A free built-in AI</h3>
            <p>
              We’re working on a free AI that runs on our own server, so you can start without a key. It isn’t ready yet. In the meantime, your own flashcards, notes, study plans and progress tracking all work without a key.
            </p>
          </div>
        </div>
      </section>

      <CtaBand title="Got your key?" text="Download Study OS, sign up, and add it under Profile → AI model." />
    </>
  )
}
