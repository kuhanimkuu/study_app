// Build-time renderer (scripts/prerender.mjs): turns each route into real
// HTML, so every page has its own content, title and preview tags before
// any JavaScript runs.
import { StrictMode } from 'react'
import { renderToString } from 'react-dom/server'
import Layout from './components/Layout'
import { notFoundRoute, routes, type Route } from './routes'
import { site } from './site'

export { notFoundRoute, routes, site }

const escape = (s: string) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;')

function head(route: Route): string {
  const url = site.url + route.path
  const tags = [
    `<title>${escape(route.title)}</title>`,
    `<meta name="description" content="${escape(route.description)}" />`,
    route === notFoundRoute ? '<meta name="robots" content="noindex" />' : `<link rel="canonical" href="${url}" />`,
    `<meta property="og:site_name" content="${site.name}" />`,
    `<meta property="og:type" content="website" />`,
    `<meta property="og:title" content="${escape(route.title)}" />`,
    `<meta property="og:description" content="${escape(route.description)}" />`,
    `<meta property="og:url" content="${url}" />`,
    `<meta property="og:image" content="${site.url}/og.png" />`,
    `<meta name="twitter:card" content="summary_large_image" />`,
  ]
  if (route.path === '/') {
    // Search engines' description of the app itself.
    const app = {
      '@context': 'https://schema.org',
      '@type': 'MobileApplication',
      name: site.name,
      operatingSystem: 'Android 7.0+',
      applicationCategory: 'EducationalApplication',
      description: route.description,
      url: site.url,
      downloadUrl: site.url + site.apkUrl,
      softwareVersion: site.appVersion,
      offers: { '@type': 'Offer', price: '0', priceCurrency: 'USD' },
    }
    tags.push(`<script type="application/ld+json">${JSON.stringify(app).replace(/</g, '\\u003c')}</script>`)
  }
  return tags.join('\n    ')
}

export function render(route: Route): { html: string; head: string } {
  const html = renderToString(
    <StrictMode>
      <Layout path={route.path}>
        <route.Page />
      </Layout>
    </StrictMode>,
  )
  return { html, head: head(route) }
}
