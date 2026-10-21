import { useState, type ReactNode } from 'react'
import { site } from '../site'
import { useTheme } from '../hooks/useTheme'
import Icon from './Icon'
import Sage from './Sage'

export const NAV = [
  { href: '/features/', label: 'Features' },
  { href: '/ai/', label: 'AI & keys' },
  { href: '/download/', label: 'Download' },
  { href: '/faq/', label: 'FAQ' },
] as const

function Header({ path }: { path: string }) {
  const [theme, toggle] = useTheme()
  const [menuOpen, setMenuOpen] = useState(false)
  return (
    <header className="header">
      <div className="container header-inner">
        <a className="brand" href="/" aria-label="Study OS home">
          <Sage size={38} />
          {site.name}
        </a>
        <nav className="nav" aria-label="Main">
          {NAV.map((item) => (
            <a key={item.href} href={item.href} aria-current={path === item.href ? 'page' : undefined}>
              {item.label}
            </a>
          ))}
        </nav>
        <div className="header-actions">
          <button className="icon-btn" onClick={toggle} aria-label={theme === 'dark' ? 'Switch to light theme' : 'Switch to dark theme'}>
            <Icon name={theme === 'dark' ? 'sun' : 'moon'} />
          </button>
          <a className="btn btn-small btn-download" href="/download/">
            <Icon name="download" size={20} /> Get the app
          </a>
          <button
            className="icon-btn menu-btn"
            onClick={() => setMenuOpen((open) => !open)}
            aria-expanded={menuOpen}
            aria-controls="mobile-menu"
            aria-label={menuOpen ? 'Close menu' : 'Open menu'}
          >
            <Icon name={menuOpen ? 'close' : 'menu'} />
          </button>
        </div>
      </div>
      <nav id="mobile-menu" className={`mobile-menu${menuOpen ? ' open' : ''}`} aria-label="Main">
        <div className="container">
          {NAV.map((item) => (
            <a key={item.href} href={item.href} aria-current={path === item.href ? 'page' : undefined}>
              {item.label}
            </a>
          ))}
          <a className="btn btn-success" href={site.apkUrl}>
            <Icon name="download" /> Download for Android
          </a>
        </div>
      </nav>
    </header>
  )
}

function Footer() {
  return (
    <footer className="footer">
      <div className="container">
        <div className="footer-grid">
          <div className="footer-brand">
            <a className="brand" href="/">
              <Sage size={34} /> {site.name}
            </a>
            <p>Your notes, turned into flashcards, quizzes and a study plan — with Sage to explain anything.</p>
          </div>
          <div>
            <h4>Product</h4>
            <a href="/features/">Features</a>
            <a href="/ai/">AI & keys</a>
            <a href="/download/">Download</a>
          </div>
          <div>
            <h4>Help</h4>
            <a href="/faq/">FAQ</a>
            <a href={`mailto:${site.contactEmail}`}>Contact us</a>
            <a href={site.issuesUrl} target="_blank" rel="noreferrer">
              Report a problem
            </a>
          </div>
          <div>
            <h4>Legal</h4>
            <a href="/privacy/">Privacy Policy</a>
            <a href="/terms/">Terms of Service</a>
            <a href={site.sourceUrl} target="_blank" rel="noreferrer">
              Source code
            </a>
          </div>
        </div>
        <div className="footer-bottom">
          <span>© 2026 {site.name}</span>
          <span>
            Version {site.appVersion} · {site.minAndroid}
          </span>
        </div>
      </div>
    </footer>
  )
}

export default function Layout({ path, children }: { path: string; children: ReactNode }) {
  return (
    <>
      <a className="skip-link" href="#main">
        Skip to content
      </a>
      <Header path={path} />
      <main id="main">{children}</main>
      <Footer />
    </>
  )
}
