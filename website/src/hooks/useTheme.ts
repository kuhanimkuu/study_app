import { useCallback, useEffect, useState } from 'react'

type Theme = 'light' | 'dark'

const STORAGE_KEY = 'studyos-theme'

function readStoredTheme(): Theme | null {
  try {
    const stored = localStorage.getItem(STORAGE_KEY)
    return stored === 'light' || stored === 'dark' ? stored : null
  } catch {
    // localStorage unavailable (private browsing, blocked storage) — the
    // page still works, it just always follows the OS preference.
    return null
  }
}

/** Manual override on top of the OS `prefers-color-scheme`, persisted so a
 * visitor's choice survives a reload. Mirrors the app's own light/dark
 * theme pair (see frontend/lib/app/theme.dart) rather than inventing a
 * third look. */
export function useTheme() {
  const [theme, setThemeState] = useState<Theme | null>(() => readStoredTheme())

  useEffect(() => {
    if (theme) {
      document.documentElement.setAttribute('data-theme', theme)
    } else {
      document.documentElement.removeAttribute('data-theme')
    }
  }, [theme])

  const toggle = useCallback(() => {
    setThemeState((current) => {
      const prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches
      const effectiveCurrent = current ?? (prefersDark ? 'dark' : 'light')
      const next: Theme = effectiveCurrent === 'dark' ? 'light' : 'dark'
      try {
        localStorage.setItem(STORAGE_KEY, next)
      } catch {
        // Non-fatal — the toggle still works for this page view.
      }
      return next
    })
  }, [])

  return { theme, toggle }
}
