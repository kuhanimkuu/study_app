// Runs in the browser: attaches React to the pre-rendered HTML of whichever
// page this is (theme toggle, mobile menu). Unknown paths get the 404 page —
// the same thing nginx's 404.html contains, so hydration matches.
import { StrictMode } from 'react'
import { hydrateRoot } from 'react-dom/client'
import Layout from './components/Layout'
import { findRoute } from './routes'
import './styles.css'

const route = findRoute(window.location.pathname)

hydrateRoot(
  document.getElementById('root')!,
  <StrictMode>
    <Layout path={route.path}>
      <route.Page />
    </Layout>
  </StrictMode>,
)
