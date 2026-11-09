# Deploying Wyrd to production

[فارسی](deployment.fa.md)

The owner's checklist for running Wyrd for real users at **$0 a month**. **No step needs a credit
card**: every service below is a free plan that never asks for one (only the optional
[custom domain](#custom-domain-later) costs money). Do the steps in order once; afterwards every
push to `main` that changes the app or the backend redeploys it, and every `v*` tag publishes a
new Android release. Changing a variable alone deploys nothing: run the workflow by hand.

| Piece | Where it runs | How it ships |
| --- | --- | --- |
| Web app (also the iPhone app) | Cloudflare Pages, `https://wyrd-app.pages.dev` | [`deploy-web.yml`](../.github/workflows/deploy-web.yml) when a push to `main` changes the app |
| Backend (database, sign-in, Edge Functions) | Supabase Free | the backend deploy workflow (see [backend/README.md](../backend/README.md)) |
| Android app | Signed APK on GitHub Releases | [`release-android.yml`](../.github/workflows/release-android.yml) on a `v*` tag |
| Sign-in e-mails | Brevo (or Gmail) over SMTP | Supabase custom SMTP |
| Push notifications | Firebase Cloud Messaging | the `notify` Edge Function |

People sign in with a 6-digit code sent by e-mail, with e-mail and password (the sign-up
confirmation and password resets also use 6-digit codes), or with Google or GitHub.

The public address lives in **one** place: the GitHub repository variable `WYRD_SITE_URL`.
Everything that needs it (the web build, the APK, Supabase's redirect settings) reads that
variable, so moving to your own domain later is a short procedure
([Custom domain later](#custom-domain-later)).

## Free-tier limits

| Service | Free allowance | Watch out for |
| --- | --- | --- |
| Supabase | 500 MB database, 5 GB egress a month, 50,000 monthly active users, 1 GB file storage, 500,000 Edge Function calls a month | The project **pauses after 7 days without database activity** (restore it from the dashboard). **No automatic backups**: step 7 covers that. |
| Cloudflare Pages | Static requests and bandwidth unlimited | At most 20,000 files per deployment, 25 MiB per file (the web build is far below). |
| Brevo | 300 e-mails a day | Sender address must be verified; without your own domain some mail lands in spam. |
| Gmail (alternative) | About 500 e-mails a day | Needs 2-Step Verification and an app password. |
| Resend (later, own domain) | 3,000 e-mails a month, 100 a day | Needs DNS records on your domain. |
| Firebase Cloud Messaging | Free on the Spark plan | Stay on Spark: Blaze is the only Firebase plan that wants a card, and push does not need it. |
| GitHub | Actions free for public repositories, Releases free | Private repositories get 2,000 Actions minutes a month. |

## What you need

Seven things, all free, none of which asks for a credit card:

1. **Supabase**: an account for the backend project (step 1).
2. **Cloudflare**: an account for the web hosting (step 2).
3. **Brevo or a Gmail app password**: the sender of sign-in e-mails (step 3).
4. **Firebase**: a project for push notifications (step 4).
5. **A Google OAuth client and a GitHub OAuth app**: the "Continue with Google" and "Continue
   with GitHub" buttons (step 5). Google Cloud may offer a free trial that wants a card: skip it,
   sign-in clients do not need billing.
6. **An Android keystore**: the key that signs the APK (step 6). The setup script creates it with
   `keytool`, which comes with every JDK (Android Studio includes one).
7. **age** for backups: encrypts the database backups (step 7). Install it with
   `brew install age`, `sudo apt install age` or `winget install FiloSottile.age`.

Collect the values in steps 1–5, then run `tool/setup_production.sh` (step 8): it stores them in
GitHub and creates the Android keystore and the age key if you do not have them yet. Names in
`code` are the GitHub secrets (private) and variables (public client configuration) the values
end up in; the script asks for each one. Keep a password manager at hand: several values are
shown only once.

## 1. Supabase project

1. Create the project at <https://supabase.com/dashboard/new> on the **Free** plan: name `wyrd`, a
   long generated **database password** (save it: `SUPABASE_DB_PASSWORD`) and the **region
   closest to most of your users** (for Europe and the Middle East, Frankfurt is a good default).
   The Free plan allows two active projects.
2. The **project ref** is the id in the dashboard URL,
   `https://supabase.com/dashboard/project/<ref>`: `SUPABASE_PROJECT_ID`. The **project URL** is
   `https://<ref>.supabase.co`: `SUPABASE_URL`.
3. API keys, <https://supabase.com/dashboard/project/_/settings/api-keys> (new projects have no
   legacy `anon`/`service_role` keys):
   - The **publishable key** (`sb_publishable_…`) goes into the apps: `SUPABASE_PUBLISHABLE_KEY`.
   - Under **Secret keys**, create a new secret key named `github-deploy` and copy it
     (`sb_secret_…`): `SUPABASE_SECRET_KEY`. The backend deploy keeps it in the database's Vault,
     so scheduled jobs and database triggers can call the Edge Functions. It bypasses row-level
     security: treat it like a password and never put it in an app build. The Edge Functions get
     their own keys from Supabase automatically.
4. Personal access token for the backend deploy, <https://supabase.com/dashboard/account/tokens>:
   **Generate new token**: `SUPABASE_ACCESS_TOKEN`.
5. Lost the database password? Reset it at
   <https://supabase.com/dashboard/project/_/database/settings>.

Nothing else is clicked in the dashboard: sign-in methods, redirect URLs, SMTP and e-mail
templates come from `backend/supabase/config.toml` and are applied by the backend deploy.
Tables are not exposed to the Data API automatically on new projects; the migrations grant
exactly what the app uses.

## 2. Cloudflare account

1. Sign up at <https://dash.cloudflare.com/sign-up> (free plan, no card needed).
2. **Account ID**: open <https://dash.cloudflare.com/?to=/:account/workers-and-pages> and copy
   the Account ID from the side panel: `CLOUDFLARE_ACCOUNT_ID`.
3. **API token**: <https://dash.cloudflare.com/profile/api-tokens> → **Create Token** →
   **Create Custom Token**. Permissions: *Account* · *Cloudflare Pages* · *Edit*. Account
   resources: *Include* · your account. Save it: `CLOUDFLARE_API_TOKEN`.
4. Pages project name: `wyrd-app` (`wyrd` is taken): `CF_PAGES_PROJECT`. You do not create it
   by hand; the first deploy does. If its `pages.dev` name is taken too, Cloudflare adds a
   suffix (`wyrd-app-abc.pages.dev`): the first web deploy warns, and `WYRD_SITE_URL` must then
   be set to that address.

## 3. E-mail sender

Sign-in codes, sign-up confirmations and password resets are 6-digit codes sent by e-mail.
Supabase's built-in mailer only reaches members of your Supabase team (2 an hour), so
production needs its own SMTP account (custom SMTP is allowed on the Free plan). Pick one:

**Brevo (recommended for now).** Free, 300 e-mails a day, no domain and no card needed.

1. Sign up at <https://www.brevo.com>.
2. Add and verify the sender address you will send from (a mailbox you own):
   <https://app.brevo.com/senders/list>. This is `SMTP_ADMIN_EMAIL`.
3. SMTP settings, <https://app.brevo.com/settings/keys/smtp>: server `smtp-relay.brevo.com`
   (`SMTP_HOST`), port `587` (`SMTP_PORT`), the **login** shown there, which looks like
   `…@smtp-brevo.com` (`SMTP_USER`), and a new **SMTP key** (`SMTP_PASS`).

**Gmail.** Uses a Gmail address you already have; about 500 e-mails a day.

1. Turn on 2-Step Verification: <https://myaccount.google.com/signinoptions/twosv>.
2. Create an app password named `Wyrd`: <https://myaccount.google.com/apppasswords> (16
   characters, `SMTP_PASS`).
3. Server `smtp.gmail.com`, port `587`, user and sender = your Gmail address.

The sender name (`SMTP_SENDER_NAME`) is `Wyrd`. Without your own domain, ask testers to check
their spam folder the first time. Once you have a domain, switch to Resend
([Custom domain later](#custom-domain-later)).

## 4. Firebase (push notifications)

1. <https://console.firebase.google.com> → **Create a project**, name `wyrd`. Google Analytics is
   not needed. New projects are on the free **Spark** plan, which includes Cloud Messaging; do
   not upgrade to Blaze.
2. **Web app**: Project settings → *Your apps* → add a web app (`</>`), name `Wyrd`, no
   Hosting. From the config it shows: `apiKey` → `FIREBASE_API_KEY`, `appId` →
   `FIREBASE_APP_ID_WEB`, `messagingSenderId` → `FIREBASE_MESSAGING_SENDER_ID`, `projectId` →
   `FIREBASE_PROJECT_ID`.
3. **Android app**: add an Android app with package name `app.wyrd` and leave the optional
   certificate fingerprint empty (push does not need it). Its App ID (`1:…:android:…`) →
   `FIREBASE_APP_ID_ANDROID`. The app is configured from these values at build time;
   `google-services.json` is not needed (and stays out of git).
4. **Web push key**: <https://console.firebase.google.com/project/_/settings/cloudmessaging> →
   *Web configuration* → **Generate key pair**. The public key → `FIREBASE_VAPID_KEY`.
5. **Server key** for the `notify` function:
   <https://console.firebase.google.com/project/_/settings/serviceaccounts/adminsdk> →
   **Generate new private key**. Keep the downloaded JSON file outside the repository; the
   setup script reads it into `FCM_SERVICE_ACCOUNT`, then you can delete it.

Firebase web config values are public by design; only the service-account key is secret.

## 5. Google and GitHub sign-in

Both providers send people back to Supabase at the same callback,
`https://<ref>.supabase.co/auth/v1/callback`. On the web, sign-in then returns to
`WYRD_SITE_URL`; phones come back to the app through `app.wyrd://auth-callback`. The backend
configuration allows both.

**Google.** In the [Google Cloud console](https://console.cloud.google.com), with the project
Firebase created (or a new one; no billing account is needed):

1. **Google Auth Platform → Branding** (<https://console.cloud.google.com/auth/branding>): app
   name `Wyrd`, your support e-mail, and the app's pages: home `WYRD_SITE_URL`, privacy policy
   `WYRD_SITE_URL/privacy`, terms `WYRD_SITE_URL/terms` (both pages ship with the web app; edit
   `app/web/privacy.html` and `app/web/terms.html` if your setup differs). Do not upload a
   logo: a logo makes Google require verification.
2. **Audience**: *External*, then **Publish app** (only the basic e-mail and profile scopes are
   used, so no review is needed).
3. **Clients → Create client** → *Web application*, name `Wyrd web (Supabase)`. Authorized
   JavaScript origin `WYRD_SITE_URL`; authorized redirect URI
   `https://<ref>.supabase.co/auth/v1/callback`.
4. Copy the **client ID** (`WYRD_GOOGLE_CLIENT_ID`) and the **client secret**
   (`WYRD_GOOGLE_CLIENT_SECRET`). The secret is shown only once; if you lose it, open the client,
   **Add secret**, and delete the old one.

Until the app's brand is verified (which needs a domain of your own), Google's consent screen
names `<ref>.supabase.co` rather than Wyrd. Sign-in works the same.

**GitHub.**

1. New OAuth app: <https://github.com/settings/applications/new> (an *OAuth App*, not a
   GitHub App).
   - Application name `Wyrd`, homepage URL `WYRD_SITE_URL`.
   - Authorization callback URL: `https://<ref>.supabase.co/auth/v1/callback`.
2. **Generate a new client secret**. Copy the client ID and the secret.

GitHub does not allow secret or variable names that start with `GITHUB_`, so they are stored
as `WYRD_GITHUB_CLIENT_ID` (variable) and `WYRD_GITHUB_CLIENT_SECRET` (secret).

`WYRD_AUTH_GOOGLE=true` and `WYRD_AUTH_GITHUB=true` switch the providers on. A button appears
only when its switch is on and both its client ID and secret are stored, so a half-configured
provider never shows a broken button.

## 6. Android signing key

The APK must be signed with the same key forever: Android only installs an update over an
existing app when the signatures match. The setup script creates the key with `keytool`
(4096-bit RSA, valid for 27 years), prints its SHA-256 fingerprint (every release's notes show
it too, so people can check an APK is yours) and stores it in GitHub as
`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` and
`ANDROID_KEY_PASSWORD`.

**Back up the keystore file and its password.** If they are lost, users can only install a
newer Wyrd after uninstalling the old one, which deletes its local data.

To sign release builds on your own machine, copy `app/android/key.properties.example` to
`app/android/key.properties` (gitignored) and fill it in. Without it, local release builds
are signed with the debug key.

## 7. Backups

Free Supabase projects have no automatic backups. A complete backup is three database dumps:
the roles, the schema and the data. Backups are encrypted to an
[age](https://github.com/FiloSottile/age) key, so they can be stored anywhere and only you can
read them. The setup script can create the key, or by hand:

```bash
mkdir -p ~/.config/wyrd
age-keygen -o ~/.config/wyrd/wyrd-backup-key.txt   # prints "Public key: age1…"
```

- The public key (`age1…`) → `BACKUP_AGE_RECIPIENT` (a variable; it can only encrypt).
- The key file is the only way to decrypt. Put a copy in your password manager or another
  offline place. Never commit it or store it in GitHub.
- To read a backup: `age --decrypt -i ~/.config/wyrd/wyrd-backup-key.txt <file>.age > <file>`.

## 8. Store everything in GitHub

From the repository, with the [GitHub CLI](https://cli.github.com) and admin rights on the
repository:

```bash
gh auth login                    # once
tool/setup_production.sh         # or: tool/setup_production.sh --repo OWNER/REPO
```

The script walks through the groups above in the same order, lets you skip any of them and can
be re-run at any time: groups that are already complete are skipped unless you ask to change
them, and Enter keeps a stored value. Passwords, tokens and keys are typed without
echo and handed to `gh` on stdin. You can check the result at
`https://github.com/OWNER/REPO/settings/secrets/actions` (secrets and variables tabs).

| Name | Kind | Used by |
| --- | --- | --- |
| `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY` | variables | web and Android builds |
| `SUPABASE_PROJECT_ID`, `SUPABASE_ACCESS_TOKEN`, `SUPABASE_DB_PASSWORD` | secrets | backend deploy, backups |
| `SUPABASE_SECRET_KEY` | secret | backend deploy (stored in the database's Vault) |
| `WYRD_SITE_URL` | variable | everything that needs the public address |
| `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID` | secrets | web deploy |
| `CF_PAGES_PROJECT` | variable | web deploy (default `wyrd-app`) |
| `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASS`, `SMTP_ADMIN_EMAIL`, `SMTP_SENDER_NAME` | secrets | backend deploy (Supabase custom SMTP) |
| `FIREBASE_API_KEY`, `FIREBASE_APP_ID_WEB`, `FIREBASE_APP_ID_ANDROID`, `FIREBASE_MESSAGING_SENDER_ID`, `FIREBASE_PROJECT_ID`, `FIREBASE_VAPID_KEY` | variables | builds |
| `FCM_SERVICE_ACCOUNT` | secret | backend deploy (`notify` function) |
| `WYRD_GOOGLE_CLIENT_ID` / `WYRD_GOOGLE_CLIENT_SECRET` | variable / secret | backend deploy, builds (whether to show the button) |
| `WYRD_AUTH_GOOGLE` | variable | builds and backend deploy (`true` turns Google sign-in on) |
| `WYRD_GITHUB_CLIENT_ID` / `WYRD_GITHUB_CLIENT_SECRET` | variable / secret | backend deploy, builds (whether to show the button) |
| `WYRD_AUTH_GITHUB` | variable | builds and backend deploy (`true` turns GitHub sign-in on) |
| `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` | secrets | Android release |
| `BACKUP_AGE_RECIPIENT` | variable | backups |

## 9. First deploy

Order matters: the apps need a backend to talk to.

1. **Backend.** Run the backend deploy workflow from the repository's **Actions** tab (or push
   to `main`). It applies the migrations, the auth and SMTP settings and the Edge Functions.
   Then check <https://supabase.com/dashboard/project/_/auth/url-configuration>: the Site URL is
   your `WYRD_SITE_URL` and the redirect list contains it and `app.wyrd://auth-callback`.
2. **Web.** **Actions** → **Deploy web (Cloudflare Pages)** → **Run workflow**, or
   `gh workflow run deploy-web.yml`. The first run creates the Pages project. Open
   `https://wyrd-app.pages.dev`, create an account with an e-mail code, try a password account
   and Google and GitHub sign-in.
3. **Android.** Tag the first release:

   ```bash
   git tag v1.0.0
   git push origin v1.0.0
   ```

   **Release Android APK** builds `wyrd-1.0.0.apk`, checks it is signed with your release key
   and publishes the GitHub Release with install notes. The tag sets the version (`v1.4.2` →
   1.4.2); keep `version:` in `app/pubspec.yaml` in step to avoid a warning.

From then on: pushes to `main` that touch `app/` or `packages/` redeploy the web app, and each
new tag ships an APK. If `CLOUDFLARE_API_TOKEN` is missing, the web workflow skips with a
notice instead of failing.

## How people install Wyrd

- **Any browser:** open `https://wyrd-app.pages.dev`. Chrome and Edge on desktop offer
  **Install** in the address bar.
- **iPhone and iPad (iOS 16.4 or newer):** open the site in Safari, tap **Share** (on iOS 26 it
  can be under the **•••** button), then **Add to Home Screen**, keep **Open as Web App** on and
  open Wyrd from the Home Screen. Notifications only work in this Home Screen app, after
  allowing them when the app asks. Until then the app shows this tip under Settings →
  Appearance (it can be dismissed).
- **Android:** install [Obtainium](https://obtainium.imranr.dev), then add
  `https://github.com/OWNER/REPO`. Obtainium installs the APK from GitHub Releases and offers
  each update. Or download `wyrd-x.y.z.apk` from the Releases page, open it and allow the
  browser to install apps. Play Protect may ask for confirmation (*More details* →
  *Install anyway*). Push notifications work in this APK too.

Google is rolling out developer verification for apps installed outside the Play Store
(enforced in a few countries since September 2026, more from 2027). Check the current
requirements at <https://developer.android.com/developer-verification> before they reach your
users' countries.

## Custom domain later

`https://wyrd-app.pages.dev` can stay the address for good. A domain of your own is optional and
the only thing in this guide that costs money (a `.com` is about $10 a year); everything else
stays free.

1. Get a domain (Cloudflare Registrar sells at cost:
   <https://dash.cloudflare.com/?to=/:account/domains/register>).
2. Cloudflare → Workers & Pages → `wyrd-app` → **Custom domains** → **Set up a custom
   domain**. With the domain on Cloudflare, the DNS record is created for you.
3. Point everything at it with one change: `gh variable set WYRD_SITE_URL --body https://your.domain`
   (or the *Site address* group of the setup script).
4. Google: in Google Auth Platform, change the home, privacy and terms links (Branding) and the
   client's JavaScript origin to the new address. GitHub OAuth app: change the homepage URL.
   The callback URL (`https://<ref>.supabase.co/auth/v1/callback`) does not change for either.
5. E-mail: add the domain at <https://resend.com/domains>, create the DNS records it lists in
   Cloudflare DNS and wait for *Verified*. Create an API key at <https://resend.com/api-keys>,
   then re-run the setup script's e-mail group with *Resend*: host `smtp.resend.com`, port
   `587`, user `resend`, the API key as password, sender `no-reply@your.domain`.
6. Redeploy: the backend (Site URL, redirect list, SMTP), then the web app (**Run workflow**).
   The next Android release picks up the new address; phone sign-in does not depend on it.

The `pages.dev` address keeps working, but Google and GitHub sign-in only return to the new
address, so share that one. Home Screen apps on iPhone belong to the address they were added from, so ask
iPhone users to add the new address once (their synced data comes back after signing in).

## If something goes wrong

- **Web workflow says "skipped":** `CLOUDFLARE_API_TOKEN` is not set; run the setup script.
- **No e-mails:** check the sender is verified at the provider, look at the Auth logs in
  Supabase, and the spam folder.
- **Google or GitHub sign-in fails:** the callback URL must be
  `https://<ref>.supabase.co/auth/v1/callback` (Google: *redirect_uri_mismatch* means it is not
  in the client's redirect URIs), and the backend deploy must have run after the client ID,
  the secret and `WYRD_AUTH_GOOGLE=true` / `WYRD_AUTH_GITHUB=true` were stored. Google's *Access
  blocked: app not published* means the Audience page still says *Testing*.
- **No Google or GitHub button:** its switch, client ID or secret is missing; the web deploy
  shows a warning naming it. Store it and redeploy the web app.
- **The app cannot reach the backend after a quiet week:** the Free project paused; restore it
  from the Supabase dashboard.
- **Release workflow fails at "Check signing secrets":** run the setup script's Android step.
