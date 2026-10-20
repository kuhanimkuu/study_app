# Study OS — website

The public site at **https://studyos.helioho.st**. React 19 + Vite 8 +
TypeScript, built as a **pre-rendered multi-page site**: every page is real
HTML at build time (its own title, description, canonical link and social
preview), then React takes over in the browser for the interactive bits
(theme toggle, mobile menu).

| Page | Path | Source |
|---|---|---|
| Home | `/` | `src/pages/Home.tsx` |
| Features | `/features/` | `src/pages/Features.tsx` |
| AI & keys | `/ai/` | `src/pages/Ai.tsx` |
| Download | `/download/` | `src/pages/Download.tsx` |
| FAQ | `/faq/` | `src/pages/Faq.tsx` |
| Privacy Policy, Terms | `/privacy/`, `/terms/` | `src/pages/Legal.tsx` + `src/content/legal.ts` |
| 404 | any unknown path | `src/pages/NotFound.tsx` |

It shares the app's design v3 (`frontend/lib/app/theme.dart`): colours,
chunky "ledge" buttons, Nunito + Inter (self-hosted Latin-subset WOFF2 cut
from the app's own fonts — no third-party requests at all) and Sage
(`src/components/Sage.tsx`, an SVG port of the app's `SageMascot`).

## How it's built

```
src/routes.tsx          the page list: path, title, description, sitemap priority
src/entry-server.tsx    renders a page to HTML + its <head> tags (build time, Node)
src/entry-client.tsx    hydrates the page in the browser
scripts/prerender.mjs   client build -> server build -> dist/<page>/index.html,
                        404.html, sitemap.xml, robots.txt
src/site.ts             release facts: APK path, version, size, minimum Android, contact
```

Adding a page: create it in `src/pages/`, add it to `routes.tsx` (and to
`NAV` in `components/Layout.tsx` if it belongs in the header).

## Develop

```
npm install        # .npmrc sets legacy-peer-deps: npm 10's resolver crashes
                   # on @vitejs/plugin-react's optional peers
npm run dev        # http://localhost:5173 (client-rendered; fine for editing)
npm run build      # type-check, then the pre-rendered production build in dist/
npx vite preview   # serve dist/ to check the real thing
```

## Publish

The website is hosted on **HelioHost** at **https://studyos.helioho.st**
(Plesk, Apache behind nginx). The APK and the app's API stay on the Contabo
server, which 301-redirects its own website pages to HelioHost
(`setup_server.sh`, `WEBSITE_URL`).

```
./deploy.sh                 # build for HelioHost -> ~/Downloads/studyos-website.zip
./deploy.sh path/to/app.apk # the same, plus upload the APK to Contabo
./deploy.sh --contabo [apk] # serve the site from Contabo instead (needs WEBSITE_URL="")
```

Then in HelioHost: Plesk → Websites & Domains → studyos.helioho.st → Files →
`httpdocs` → Upload the zip → tick it → Extract Files (replace) → delete the
zip. The build is pointed at the right places by `VITE_SITE_URL` (canonical
links, sitemap, preview image) and `VITE_APK_URL` (download buttons) — see
`src/site.ts`. After a new APK, update `appVersion`/`apkSizeMb` there.

`public/.htaccess` gives Apache what nginx has on Contabo: custom 404, forced
HTTPS, security headers incl. a Content-Security-Policy that only allows
same-origin scripts (**so never add inline or third-party scripts/fonts** —
the pre-paint theme script is `public/theme-init.js` for this reason), and
caching. Known HelioHost limit: its nginx serves `/assets/*.js|css` directly,
so those files skip `.htaccess` (no long-cache header) — pages still get every
security header.

## Keep it honest

Every claim is checked against the app's code (10 question types, FSRS,
BYOK with the key encrypted on the phone, free built-in AI "in
development", Android 7.0+, retention periods). The Privacy Policy and
Terms are the same text as the app's `legal_screen.dart` — change both
together. Screenshots are real renders of the app (Flutter golden-file
harness, demo student "Amani"), not mock-ups.
