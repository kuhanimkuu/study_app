// Facts about the product and the current release, in one place — a new APK
// or a new contact means changing this file only. Keep it honest: these are
// the real numbers.
//
// Where the site and the APK live is set at build time, so the same code can
// be published to Contabo (default) or HelioHost:
//   VITE_SITE_URL   the site's own address (canonical links, sitemap, previews)
//   VITE_APK_URL    where the Download buttons point
const env = import.meta.env

export const site = {
  name: 'Study OS',
  url: (env.VITE_SITE_URL ?? 'https://studytutor.duckdns.org').replace(/\/$/, ''),
  contactEmail: 'davidmurunga27@gmail.com',

  /** The APK stays on the app's own server (Contabo) wherever the site is hosted. */
  apkUrl: env.VITE_APK_URL ?? '/download/study-os.apk',
  appVersion: '1.0.4',
  apkSizeMb: 59,
  /** Flutter's default minSdk 24. */
  minAndroid: 'Android 7.0 or newer',

  sourceUrl: 'https://github.com/kuhanimkuu/study_app',
  issuesUrl: 'https://github.com/kuhanimkuu/study_app/issues',
} as const
