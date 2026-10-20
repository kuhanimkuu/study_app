import { PageHero } from '../components/ui'
import { legalNote, legalUpdated, privacy, terms, type LegalSection } from '../content/legal'

function LegalDoc({ sections }: { sections: LegalSection[] }) {
  return (
    <section className="section section-tight">
      <div className="container narrow legal">
        <p className="legal-meta">
          Last updated {legalUpdated}. {legalNote}
        </p>
        <nav className="legal-toc" aria-label="Contents">
          <ol>
            {sections.map((s, i) => (
              <li key={s.title}>
                <a href={`#s${i + 1}`}>{s.title}</a>
              </li>
            ))}
          </ol>
        </nav>
        {sections.map((s, i) => (
          <section key={s.title} id={`s${i + 1}`} className="anchor">
            <h2>
              {i + 1}. {s.title}
            </h2>
            {s.body.map((para) => (
              <p key={para}>{para}</p>
            ))}
          </section>
        ))}
      </div>
    </section>
  )
}

export function Privacy() {
  return (
    <>
      <PageHero eyebrow="Legal" icon="shield" title="Privacy Policy" lead="What Study OS stores, where, for how long — and how to delete it." />
      <LegalDoc sections={privacy} />
    </>
  )
}

export function Terms() {
  return (
    <>
      <PageHero eyebrow="Legal" icon="book" title="Terms of Service" lead="The ground rules for using Study OS, in plain language." />
      <LegalDoc sections={terms} />
    </>
  )
}
