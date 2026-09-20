export default function GetStarted() {
  return (
    <section className="section section-cta" id="get-started">
      <div className="container cta-inner">
        <h2>Study OS is in active development.</h2>
        <p>
          It's a real, working app today — Android, with a Postgres-backed AI moderator behind it — built
          in the open. There's no Play Store listing yet, so the source and the latest builds live on
          GitHub.
        </p>
        <div className="hero-cta">
          <a
            className="btn btn-primary btn-large"
            href="https://github.com/kuhanimkuu/study_app"
            target="_blank"
            rel="noopener"
          >
            View on GitHub
          </a>
          <a className="btn btn-ghost btn-large" href="#features">
            Explore features
          </a>
        </div>
      </div>
    </section>
  )
}
