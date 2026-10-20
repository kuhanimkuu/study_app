import type { ComponentType } from 'react'
import Ai from './pages/Ai'
import Download from './pages/Download'
import Faq from './pages/Faq'
import Features from './pages/Features'
import Home from './pages/Home'
import { Privacy, Terms } from './pages/Legal'
import NotFound from './pages/NotFound'

export type Route = {
  /** Always with a trailing slash — nginx serves /features/ from features/index.html. */
  path: string
  title: string
  description: string
  Page: ComponentType
  /** Relative weight in sitemap.xml. */
  priority: number
}

export const routes: Route[] = [
  {
    path: '/',
    title: 'Study OS — study smarter with Sage',
    description:
      'Turn your notes into flashcards, quizzes and a study plan. Ask Sage, your AI study buddy, about anything — with a photo, PDF, voice note or link. Free Android app.',
    Page: Home,
    priority: 1.0,
  },
  {
    path: '/features/',
    title: 'Features — Study OS',
    description:
      'Subjects built from your notes, an AI study buddy that reads photos, PDFs and voice notes, spaced-repetition flashcards, ten question types, and a study plan around your weak spots.',
    Page: Features,
    priority: 0.9,
  },
  {
    path: '/ai/',
    title: 'AI & API keys — Study OS',
    description:
      'Study OS runs on the AI you choose. How to get an API key from DeepSeek, OpenAI or Anthropic, add it to the app, and what it costs — your key stays encrypted on your phone.',
    Page: Ai,
    priority: 0.8,
  },
  {
    path: '/download/',
    title: 'Download for Android — Study OS',
    description: 'Download the free Study OS app for Android 7.0 or newer, with step-by-step install help and troubleshooting.',
    Page: Download,
    priority: 0.9,
  },
  {
    path: '/faq/',
    title: 'FAQ — Study OS',
    description: 'Answers about cost, API keys, privacy, installing, and using Study OS.',
    Page: Faq,
    priority: 0.7,
  },
  {
    path: '/privacy/',
    title: 'Privacy Policy — Study OS',
    description: 'What Study OS stores, where, for how long, who else is involved, and how to delete your data.',
    Page: Privacy,
    priority: 0.4,
  },
  {
    path: '/terms/',
    title: 'Terms of Service — Study OS',
    description: 'The terms for using Study OS, in plain language.',
    Page: Terms,
    priority: 0.4,
  },
]

export const notFoundRoute: Route = {
  path: '/404/',
  title: 'Page not found — Study OS',
  description: 'This page doesn’t exist.',
  Page: NotFound,
  priority: 0,
}

/** "/features" and "/features/index.html" both mean "/features/". */
export function normalizePath(pathname: string): string {
  let p = pathname.replace(/index\.html$/, '')
  if (!p.endsWith('/')) p += '/'
  return p
}

export function findRoute(pathname: string): Route {
  const p = normalizePath(pathname)
  return routes.find((r) => r.path === p) ?? notFoundRoute
}
