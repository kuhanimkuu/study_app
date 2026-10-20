// Apply a saved light/dark choice before first paint (see src/hooks/useTheme.ts).
// A separate file rather than inline, so the Content-Security-Policy can allow
// only same-origin scripts.
try {
  var t = localStorage.getItem('study-os-theme')
  if (t === 'light' || t === 'dark') document.documentElement.dataset.theme = t
} catch (e) {}
