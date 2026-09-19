# Study OS — marketing website

A single-page marketing site for Study OS, built with **React + Vite +
TypeScript**. Design tokens (colors, radii, shadows, the light/dark pair)
are copied from `frontend/lib/app/theme.dart` so the site and the app
read as one product.

## Structure

```
website/
  index.html            Vite entry (loads /src/main.tsx)
  public/favicon.svg
  src/
    main.tsx            React root
    App.tsx             page layout — composes the sections below
    index.css           tokens + layout (light/dark via prefers-color-scheme,
                         with a manual toggle that overrides it)
    hooks/useTheme.ts    the manual dark/light toggle, persisted in localStorage
    components/
      Header.tsx         sticky nav + theme toggle + mobile menu
      Hero.tsx           headline, CTAs, phone mockup
      ModelStrip.tsx     "runs on" — local/Anthropic/OpenAI/DeepSeek
      Features.tsx       6-card feature grid
      HowItWorks.tsx     3-step flow
      Privacy.tsx        BYOK explanation + key-storage card
      GetStarted.tsx     honest CTA — links to GitHub, not a fake signup form
      Faq.tsx            <details> accordion
      Footer.tsx
```

## Running it locally

```
cd website
npm install
npm run dev       # http://localhost:5173, hot-reloading
npm run build     # type-checks (tsc -b) then builds to dist/
npm run preview   # serves the production build locally
```

`npm run build` runs `tsc -b` first — a type error fails the build, it
doesn't just warn.

## Deploying it

`npm run build` produces a static `dist/` folder — any static host works
(GitHub Pages, Netlify, Vercel, Render's static-site type, an S3 bucket,
etc.). Nothing here talks to the Study OS backend; "Get the app" links
out to the GitHub repo rather than a live signup flow, since there's no
public Play Store listing or hosted web app yet — update `GetStarted.tsx`
once there is one.

## Content honesty

Every claim on this page matches something real in the app as of
2026-09-19 (FSRS-based spaced repetition, 10 question types, the
Knowledge Graph, BYOK support for Anthropic/OpenAI/DeepSeek, real
account deletion). If a feature listed here is ever removed or changed
in the app, update this page in the same change — don't let it drift
into overselling what the app actually does.

## Known, accepted dev-tooling note

`npm audit` flags a moderate esbuild advisory (GHSA-67mh-4wv8-2f99) via
Vite 5's bundled esbuild — it only affects `vite dev`'s dev server being
reachable from an untrusted network while running locally, not the
production build output or the deployed static site. Fixing it means
jumping to Vite 8 (breaking change, untested here) — left as a known,
accepted dev-tooling-only risk rather than done in a rush.
