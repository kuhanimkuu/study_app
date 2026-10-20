// Production build: a static, pre-rendered multi-page site.
//   1. client build  -> dist/ (JS, CSS, assets, the HTML template)
//   2. server build  -> dist-ssr/ (renders a page to HTML in Node)
//   3. every route   -> dist/<path>/index.html, plus 404.html, sitemap.xml, robots.txt
import fs from 'node:fs'
import path from 'node:path'
import { pathToFileURL } from 'node:url'
import { build } from 'vite'

const root = path.resolve(import.meta.dirname, '..')
const dist = path.join(root, 'dist')
const ssrDir = path.join(root, 'dist-ssr')

await build({ root, logLevel: 'warn', build: { outDir: dist, emptyOutDir: true } })
await build({ root, logLevel: 'warn', build: { ssr: 'src/entry-server.tsx', outDir: ssrDir, emptyOutDir: true } })

const entry = fs.readdirSync(ssrDir).find((f) => /^entry-server\.(m?js)$/.test(f))
const { render, routes, notFoundRoute, site } = await import(pathToFileURL(path.join(ssrDir, entry)).href)

const template = fs.readFileSync(path.join(dist, 'index.html'), 'utf8')
const page = (route) => {
  const { html, head } = render(route)
  return template.replace('<!--app-head-->', head).replace('<!--app-html-->', html)
}

for (const route of routes) {
  const out = path.join(dist, route.path, 'index.html')
  fs.mkdirSync(path.dirname(out), { recursive: true })
  fs.writeFileSync(out, page(route))
  console.log('  page', route.path)
}
fs.writeFileSync(path.join(dist, '404.html'), page(notFoundRoute))
console.log('  page 404.html')

const today = new Date().toISOString().slice(0, 10)
const urls = routes
  .map((r) => `  <url><loc>${site.url}${r.path}</loc><lastmod>${today}</lastmod><priority>${r.priority.toFixed(1)}</priority></url>`)
  .join('\n')
fs.writeFileSync(path.join(dist, 'sitemap.xml'), `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${urls}\n</urlset>\n`)
fs.writeFileSync(path.join(dist, 'robots.txt'), `User-agent: *\nAllow: /\nDisallow: /api/\n\nSitemap: ${site.url}/sitemap.xml\n`)
console.log('  sitemap.xml, robots.txt')

fs.rmSync(ssrDir, { recursive: true, force: true })
