// Facts about the product and the current release, in one place — a new APK
// or a new contact means changing this file only. Keep it honest: these are
// the real numbers.
export const site = {
  name: 'Study OS',
  url: 'https://studytutor.duckdns.org',
  contactEmail: 'davidmurunga27@gmail.com',

  /** Served by nginx from the same server as the API (see deploy.sh). */
  apkUrl: '/download/study-os.apk',
  appVersion: '1.0.0',
  apkSizeMb: 59,
  /** Flutter's default minSdk 24. */
  minAndroid: 'Android 7.0 or newer',

  sourceUrl: 'https://github.com/kuhanimkuu/study_app',
  issuesUrl: 'https://github.com/kuhanimkuu/study_app/issues',
} as const
