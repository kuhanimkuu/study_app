import Header from './components/Header'
import Hero from './components/Hero'
import ModelStrip from './components/ModelStrip'
import Features from './components/Features'
import HowItWorks from './components/HowItWorks'
import Privacy from './components/Privacy'
import GetStarted from './components/GetStarted'
import Faq from './components/Faq'
import Footer from './components/Footer'

export default function App() {
  return (
    <>
      <a className="skip-link" href="#main">
        Skip to content
      </a>
      <Header />
      <main id="main">
        <Hero />
        <ModelStrip />
        <Features />
        <HowItWorks />
        <Privacy />
        <GetStarted />
        <Faq />
      </main>
      <Footer />
    </>
  )
}
