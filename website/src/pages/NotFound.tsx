import Sage from '../components/Sage'

export default function NotFound() {
  return (
    <section className="section">
      <div className="container narrow center">
        <Sage size={150} mood="thinking" />
        <h1 style={{ marginTop: 16 }}>Page not found</h1>
        <p className="page-lead" style={{ marginInline: 'auto' }}>
          Sage looked everywhere, but this page doesn’t exist. It may have moved.
        </p>
        <div className="hero-ctas" style={{ justifyContent: 'center', marginTop: 24 }}>
          <a className="btn" href="/">
            Go home
          </a>
          <a className="btn btn-ghost" href="/faq/">
            Read the FAQ
          </a>
        </div>
      </div>
    </section>
  )
}
