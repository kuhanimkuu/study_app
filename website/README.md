# Study OS — website

The public site at **https://studytutor.duckdns.org**. React 19 + Vite 8 +
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

```
./deploy.sh                                   # website only
./deploy.sh ../frontend/build/app/outputs/flutter-apk/app-release.apk   # + new APK
```

Builds here (the server has no Node), uploads over SSH and swaps the new
site in atomically. The published APK is kept across website-only deploys.
After a new APK, update `appVersion`/`apkSizeMb` in `src/site.ts`.

nginx (`setup_server.sh`, step 9) serves `/var/www/studyos`, answers unknown
paths with `404.html`, sends `/api/` and `/generated/` to the app, serves
`*.apk` as an Android package, and adds security headers to everything,
including a Content-Security-Policy that only allows same-origin scripts —
**so never add inline `<script>`s or third-party scripts/fonts** (the theme
pre-paint script lives in `public/theme-init.js` for this reason).

## Keep it honest

Every claim is checked against the app's code (10 question types, FSRS,
BYOK with the key encrypted on the phone, free built-in AI "in
development", Android 7.0+, retention periods). The Privacy Policy and
Terms are the same text as the app's `legal_screen.dart` — change both
together. Screenshots are real renders of the app (Flutter golden-file
harness, demo student "Amani"), not mock-ups.
