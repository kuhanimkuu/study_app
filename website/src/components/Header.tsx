import { useState } from 'react'
import { useTheme } from '../hooks/useTheme'

const NAV_LINKS = [
  { href: '#features', label: 'Features' },
  { href: '#how-it-works', label: 'How it works' },
  { href: '#privacy', label: 'Privacy & BYOK' },
  { href: '#faq', label: 'FAQ' },
]

export default function Header() {
  const [navOpen, setNavOpen] = useState(false)
  const { theme, toggle } = useTheme()
  const isDark = theme === 'dark'

  return (
    <header className="site-header" id="top">
      <div className="container header-inner">
        <a className="brand" href="#top" aria-label="Study OS home">
          <span className="brand-mark" aria-hidden="true">
            <svg viewBox="0 0 22 22" fill="none" width={22} height={22}>
              <path d="M11 2L19 8.5V13.5L11 20L3 13.5V8.5L11 2Z" fill="white" fillOpacity={0.25} stroke="white" strokeWidth={1.1} />
              <path d="M11 5.5L16 9.5V12.5L11 16.5L6 12.5V9.5L11 5.5Z" fill="white" fillOpacity={0.9} />
            </svg>
          </span>
          <span className="brand-name">Study OS</span>
        </a>

        <nav className={`site-nav${navOpen ? ' open' : ''}`} id="site-nav" aria-label="Primary">
          {NAV_LINKS.map((link) => (
            <a key={link.href} href={link.href} onClick={() => setNavOpen(false)}>
              {link.label}
            </a>
          ))}
        </nav>

        <div className="header-actions">
          <button
            className="theme-toggle"
            type="button"
            aria-label="Toggle dark mode"
            title="Toggle dark mode"
            onClick={toggle}
          >
            {isDark ? (
              <svg viewBox="0 0 24 24" width={18} height={18} fill="none" stroke="currentColor" strokeWidth={2}>
                <path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8Z" strokeLinejoin="round" />
              </svg>
            ) : (
              <svg viewBox="0 0 24 24" width={18} height={18} fill="none" stroke="currentColor" strokeWidth={2}>
                <circle cx={12} cy={12} r={4} />
                <path
                  d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"
                  strokeLinecap="round"
                />
              </svg>
            )}
          </button>
          <a className="btn btn-primary btn-small" href="#get-started">
            Get the app
          </a>
          <button
            className="nav-toggle"
            type="button"
            aria-label="Toggle menu"
            aria-expanded={navOpen}
            aria-controls="site-nav"
            onClick={() => setNavOpen((open) => !open)}
          >
            <span></span>
            <span></span>
            <span></span>
          </button>
        </div>
      </div>
    </header>
  )
}
