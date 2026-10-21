import type { ReactNode } from 'react'
import { site } from '../site'
import Icon, { type IconName } from './Icon'
import Sage, { type SageMood } from './Sage'

/** A real app screenshot in a phone frame. The strip above the screenshot
 * stands in for the status bar, so the notch doesn't cover the app. */
export function Phone({ src, alt, dark = false, eager = false }: { src: string; alt: string; dark?: boolean; eager?: boolean }) {
  return (
    <div className="phone">
      <div className="screen" style={{ ['--screen-bg' as string]: dark ? '#0b0f1c' : '#f5f7fc' }}>
        <img src={src} alt={alt} width={390} height={844} loading={eager ? 'eager' : 'lazy'} decoding="async" />
      </div>
    </div>
  )
}

export function Checks({ items, color }: { items: ReactNode[]; color: string }) {
  return (
    <ul className="checks">
      {items.map((item, i) => (
        <li key={i}>
          <span style={{ color }}>
            <Icon name="check" size={20} />
          </span>
          <span>{item}</span>
        </li>
      ))}
    </ul>
  )
}

/** The coloured title band at the top of every inner page. */
export function PageHero({
  eyebrow,
  icon,
  title,
  lead,
  mood = 'happy',
  children,
}: {
  eyebrow: string
  icon: IconName
  title: ReactNode
  lead: ReactNode
  mood?: SageMood
  children?: ReactNode
}) {
  return (
    <section className="page-hero">
      <div className="container page-hero-inner">
        <div>
          <span className="eyebrow">
            <Icon name={icon} size={16} /> {eyebrow}
          </span>
          <h1>{title}</h1>
          <p className="page-lead">{lead}</p>
          {children}
        </div>
        <Sage size={150} mood={mood} className="page-hero-sage" />
      </div>
    </section>
  )
}

export function Tag({ icon, color, children }: { icon: IconName; color: string; children: ReactNode }) {
  return (
    <span className="tag" style={{ background: color }}>
      <Icon name={icon} size={16} /> {children}
    </span>
  )
}

/** The closing "get the app" band most pages end with. */
export function CtaBand({ title = 'Ready to study smarter?', text = 'Download Study OS, sign up, and Sage will show you around.' }: { title?: string; text?: string }) {
  return (
    <section className="section">
      <div className="container">
        <div className="cta-band">
          <div>
            <h2>{title}</h2>
            <p>{text}</p>
          </div>
          <div className="cta-actions">
            <a className="btn" href={site.apkUrl} download>
              <Icon name="download" /> Download APK <small>v{site.appVersion} · {site.apkSizeMb} MB</small>
            </a>
            <a className="cta-link" href="/download/">
              Install help →
            </a>
          </div>
          <Sage size={120} mood="cheer" className="cta-sage" />
        </div>
      </div>
    </section>
  )
}

export function FlashcardDemo() {
  return (
    <div className="deck" role="img" aria-label="A flashcard with the four review buttons: Again, Hard, Good, Easy">
      <div className="card behind" />
      <div className="card behind-2" />
      <div className="card">
        <span className="label">Cell Biology</span>
        <span className="q">What happens during anaphase?</span>
        <span className="a">The sister chromatids are pulled apart to opposite ends of the cell.</span>
      </div>
      <div className="ratings" aria-hidden="true">
        <span className="rate" style={{ background: 'var(--pink)', boxShadow: '0 3px 0 #b8325f' }}>
          Again
        </span>
        <span className="rate" style={{ background: 'var(--streak)', boxShadow: '0 3px 0 var(--streak-ledge)' }}>
          Hard
        </span>
        <span className="rate" style={{ background: 'var(--success)', boxShadow: '0 3px 0 var(--success-ledge)' }}>
          Good
        </span>
        <span className="rate" style={{ background: 'var(--primary)', boxShadow: '0 3px 0 var(--primary-ledge)' }}>
          Easy
        </span>
      </div>
    </div>
  )
}
