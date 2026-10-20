import Icon from '../components/Icon'
import Sage from '../components/Sage'
import { site } from '../site'

const TROUBLE = [
  {
    q: 'Android says installing apps from this source isn’t allowed',
    a: 'Tap Settings on that message, turn on “Allow from this source” for your browser (or Files app), then go back and tap Install. You only need to do this once.',
  },
  {
    q: 'Google Play Protect warns about the app',
    a: 'Play Protect shows this for apps that don’t come from the Play Store. If you downloaded Study OS from this site, choose “More details” → “Install anyway”.',
  },
  {
    q: '“App not installed”',
    a: 'Usually the download didn’t finish, or your phone is low on storage. Free up some space, download the APK again, and retry.',
  },
  {
    q: 'Nothing happens when I tap the downloaded file',
    a: 'Open your Downloads folder (or the Files app) and tap study-os.apk from there.',
  },
  {
    q: 'The app can’t connect',
    a: 'Study OS needs an internet connection. Check you’re online, then try again in a minute — the server may be restarting after an update.',
  },
]

export default function Download() {
  return (
    <>
      <section className="page-hero download-hero">
        <div className="container download-page">
          <div>
            <span className="eyebrow">
              <Icon name="download" size={16} /> Download
            </span>
            <h1>
              Get Study OS <span className="accent">for Android</span>
            </h1>
            <p className="page-lead">Free to download. Install it in a minute, sign up, and Sage will show you around.</p>
            <a className="btn btn-success btn-big" href={site.apkUrl} download>
              <Icon name="download" /> Download APK
            </a>
            <dl className="release-facts">
              <div>
                <dt>Version</dt>
                <dd>{site.appVersion}</dd>
              </div>
              <div>
                <dt>Size</dt>
                <dd>{site.apkSizeMb} MB</dd>
              </div>
              <div>
                <dt>Needs</dt>
                <dd>{site.minAndroid}</dd>
              </div>
            </dl>
            <p className="muted small">Not on the Play Store yet — that’s why Android asks you to allow the install. There’s no iPhone version yet.</p>
          </div>
          <Sage size={190} mood="cheer" className="download-page-sage" />
        </div>
      </section>

      <section className="section section-tight">
        <div className="container narrow">
          <div className="section-head">
            <h2>How to install</h2>
          </div>
          <ol className="number-steps">
            <li>
              <strong>Download the APK on your Android phone</strong>
              <span>Tap Download APK above. If your browser asks whether to keep the file, choose Download anyway.</span>
            </li>
            <li>
              <strong>Open it</strong>
              <span>Tap the download notification, or find study-os.apk in your Downloads folder.</span>
            </li>
            <li>
              <strong>Allow the install</strong>
              <span>The first time, Android asks you to allow installs from your browser. Choose Settings → Allow from this source, go back, then tap Install.</span>
            </li>
            <li>
              <strong>Sign up and say hi to Sage</strong>
              <span>
                Create your account, take the quick tour, then add your AI key in Profile — <a href="/ai/">here’s how</a>.
              </span>
            </li>
          </ol>
        </div>
      </section>

      <section className="section section-tight">
        <div className="container narrow">
          <div className="update-card">
            <Icon name="flame" size={26} />
            <div>
              <h3>Updating</h3>
              <p>
                Download the latest APK from this page and install it over the old one — your account and study data are on our server and stay put. Your chats stay on your phone as long as you don’t uninstall the app first.
              </p>
            </div>
          </div>
        </div>
      </section>

      <section className="section section-tight">
        <div className="container narrow">
          <div className="section-head">
            <h2>Trouble installing?</h2>
          </div>
          <div className="faq">
            {TROUBLE.map((t) => (
              <details key={t.q}>
                <summary>{t.q}</summary>
                <p>{t.a}</p>
              </details>
            ))}
          </div>
          <p className="muted center" style={{ marginTop: 24 }}>
            Still stuck? Email <a href={`mailto:${site.contactEmail}`}>{site.contactEmail}</a>.
          </p>
        </div>
      </section>
    </>
  )
}
