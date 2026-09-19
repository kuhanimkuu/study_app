export default function Footer() {
  return (
    <footer className="site-footer">
      <div className="container footer-inner">
        <div className="footer-brand">
          <span className="brand-mark brand-mark-small" aria-hidden="true">
            <svg viewBox="0 0 22 22" fill="none" width={16} height={16}>
              <path d="M11 2L19 8.5V13.5L11 20L3 13.5V8.5L11 2Z" fill="white" fillOpacity={0.25} stroke="white" strokeWidth={1.1} />
              <path d="M11 5.5L16 9.5V12.5L11 16.5L6 12.5V9.5L11 5.5Z" fill="white" fillOpacity={0.9} />
            </svg>
          </span>
          <span>Study OS</span>
        </div>
        <nav className="footer-links" aria-label="Footer">
          <a href="#features">Features</a>
          <a href="#privacy">Privacy &amp; BYOK</a>
          <a href="#faq">FAQ</a>
          <a href="https://github.com/kuhanimkuu/study_app" target="_blank" rel="noopener">
            GitHub
          </a>
        </nav>
        <p className="footer-copy">&copy; {new Date().getFullYear()} Study OS. Built for students who ask a lot of questions.</p>
      </div>
    </footer>
  )
}
