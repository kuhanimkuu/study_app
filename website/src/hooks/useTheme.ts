import { useEffect, useState } from 'react'

export type Theme = 'light' | 'dark'

export const THEME_KEY = 'study-os-theme'

function systemTheme(): Theme {
  return window.matchMedia?.('(prefers-color-scheme: dark)').matches ? 'dark' : 'light'
}

function savedTheme(): Theme | null {
  try {
    const value = localStorage.getItem(THEME_KEY)
    return value === 'light' || value === 'dark' ? value : null
  } catch {
    return null // storage blocked (private mode etc.) — just follow the system
  }
}

/**
 * Follows the system theme until the visitor picks one; their pick is
 * remembered. Pages are pre-rendered at build time with no browser, so the
 * first render is always `null` (same markup on the server and in the
 * browser), and the real theme is read once the page is running. The page
 * colours themselves never flash: an inline script in index.html applies a
 * saved choice before first paint, and CSS follows the system otherwise.
 */
export function useTheme(): [Theme | null, () => void] {
  const [theme, setTheme] = useState<Theme | null>(null)

  useEffect(() => {
    setTheme(savedTheme() ?? systemTheme())
  }, [])

  const toggle = () => {
    const next: Theme = (theme ?? systemTheme()) === 'dark' ? 'light' : 'dark'
    setTheme(next)
    document.documentElement.dataset.theme = next
    try {
      localStorage.setItem(THEME_KEY, next)
    } catch {
      /* not remembered, still applied */
    }
  }

  return [theme, toggle]
}
