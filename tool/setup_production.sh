#!/usr/bin/env bash
# Stores Wyrd's production settings as GitHub Actions secrets and variables,
# so the deploy workflows can build and ship the app. Create the accounts in
# docs/deployment.md first, then run from anywhere in the repository:
#
#   tool/setup_production.sh [--repo OWNER/REPO]
#
# Every group can be skipped and the script can be re-run at any time: groups
# whose values are all stored are skipped unless you ask to change them, and
# Enter keeps a stored value. Passwords, tokens and keys are read without
# echo, passed to gh on stdin and never written to disk.
# Works with the bash 3.2 that ships with macOS.
set -euo pipefail

repo=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo)
      repo="${2:-}"
      [ -n "$repo" ] || {
        echo "--repo needs OWNER/REPO" >&2
        exit 2
      }
      shift 2
      ;;
    -h | --help)
      sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "Unknown option: $1 (try --help)" >&2
      exit 2
      ;;
  esac
done

if [ -t 1 ]; then
  bold=$'\033[1m' dim=$'\033[2m' reset=$'\033[0m'
else
  bold="" dim="" reset=""
fi

say() { printf '%s\n' "$*"; }
note() { printf '%s%s%s\n' "$dim" "$*" "$reset"; }
die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

# Hidden input turns terminal echo off; turn it back on if interrupted.
trap 'stty echo 2>/dev/null || true; printf "\n"; exit 130' INT

# ask "Prompt" [default] -> prints the answer (the prompt goes to stderr).
ask() {
  local prompt="$1" default="${2:-}" reply=""
  if [ -n "$default" ]; then prompt="$prompt [$default]"; fi
  read -r -p "$prompt: " reply || true
  printf '%s' "${reply:-$default}"
}

# ask_secret "Prompt" -> prints the answer; nothing is echoed while typing.
ask_secret() {
  local reply=""
  read -r -s -p "$1: " reply || true
  printf '\n' >&2
  printf '%s' "$reply"
}

# confirm "Question" [Y|N] -> succeeds on yes.
confirm() {
  local default="${2:-Y}" reply=""
  if [ "$default" = "Y" ]; then
    read -r -p "$1 [Y/n] " reply || true
  else
    read -r -p "$1 [y/N] " reply || true
  fi
  case "${reply:-$default}" in
    [yY]*) return 0 ;;
    *) return 1 ;;
  esac
}

# group "Title" "what it is for" [NAME...] -> succeeds when the user wants to
# set it now. When every NAME (secret or variable) is already stored, the
# group defaults to being skipped.
group() {
  local title="$1" about="$2" reply="" name="" complete=false
  shift 2
  if [ $# -gt 0 ]; then
    complete=true
    for name in "$@"; do
      if ! has_secret "$name" && ! has_variable "$name"; then complete=false; fi
    done
  fi
  printf '\n%s== %s ==%s\n' "$bold" "$title" "$reset"
  note "$about"
  if [ "$complete" = true ]; then
    note "Already stored: $*"
    read -r -p "Change it? [y/N/q] " reply || true
    reply="${reply:-n}"
  else
    read -r -p "Set this up now? [Y/n/q] " reply || true
  fi
  case "$reply" in
    [nN]*)
      say "  skipped"
      return 1
      ;;
    [qQ]*)
      say "Stopped. Run the script again to continue."
      exit 0
      ;;
    *) return 0 ;;
  esac
}

stored_secrets=""   # names of the secrets already stored, one per line
stored_variables="" # the same for variables
has_secret() {
  case $'\n'"$stored_secrets"$'\n' in
    *$'\n'"$1"$'\n'*) return 0 ;;
    *) return 1 ;;
  esac
}
has_variable() {
  case $'\n'"$stored_variables"$'\n' in
    *$'\n'"$1"$'\n'*) return 0 ;;
    *) return 1 ;;
  esac
}
current_variable() { gh variable get "$1" --repo "$repo" 2>/dev/null || true; }

# set_secret NAME VALUE: the value reaches gh on stdin, never on a command line.
set_secret() {
  if [ -z "$2" ]; then
    if has_secret "$1"; then say "  = secret $1 kept"; else say "  - secret $1 not set (empty)"; fi
    return 0
  fi
  printf '%s' "$2" | gh secret set "$1" --repo "$repo" >/dev/null
  say "  ✓ secret $1"
}

set_variable() {
  if [ -z "$2" ]; then
    say "  - variable $1 not set (empty)"
    return 0
  fi
  gh variable set "$1" --repo "$repo" --body "$2" >/dev/null
  say "  ✓ variable $1"
}

# secret_prompt NAME "Prompt" -> asks without echo; Enter keeps a stored value.
secret_prompt() {
  local hint=""
  if has_secret "$1"; then hint=" (Enter keeps the stored one)"; fi
  ask_secret "$2$hint"
}

# variable_prompt NAME "Prompt" [fallback default] -> visible; defaults to the stored value.
variable_prompt() {
  local stored
  stored="$(current_variable "$1")"
  ask "$2" "${stored:-${3:-}}"
}

warn_unless() { # warn_unless VALUE REGEX "message"
  if [ -n "$1" ] && ! [[ "$1" =~ $2 ]]; then note "  ! $3"; fi
}

# Creates (or reuses) the APK upload key and stores it. Anything missing skips
# the rest of this group instead of ending the script.
setup_android_key() {
  local keystore="" alias_name="" store_pass="" key_pass="" repeat="" owner_name="" fingerprints=""
  local keytool="" candidate=""
  # macOS has a /usr/bin/keytool stub that fails without a JDK, Homebrew's
  # openjdk is not linked onto PATH, and Android Studio's own JDK is not on
  # PATH either. Take the first one that runs.
  for candidate in "$(command -v keytool 2>/dev/null || true)" \
    "${JAVA_HOME:+$JAVA_HOME/bin/keytool}" \
    "$(/usr/libexec/java_home 2>/dev/null || true)/bin/keytool" \
    "/opt/homebrew/opt/openjdk/bin/keytool" \
    "/usr/local/opt/openjdk/bin/keytool" \
    "/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/keytool"; do
    if [ -n "$candidate" ] && [ -x "$candidate" ] && "$candidate" -help >/dev/null 2>&1; then
      keytool="$candidate"
      break
    fi
  done
  if [ -z "$keytool" ]; then
    say "  ! no working keytool: install a JDK (brew install openjdk) or Android Studio, then run the script again"
    return 0
  fi
  if confirm "Create a new upload keystore with keytool?" Y; then
    keystore="$(ask "Save it as" "${XDG_CONFIG_HOME:-$HOME/.config}/wyrd/wyrd-upload.jks")"
    keystore="${keystore/#\~/$HOME}"
    if [ -e "$keystore" ]; then
      say "  ! $keystore already exists: run again and answer n to use it"
      return 0
    fi
    alias_name="$(ask "Key alias" upload)"
    while :; do
      store_pass="$(ask_secret "Keystore password (6+ characters)")"
      if [ "${#store_pass}" -lt 6 ]; then
        say "  too short"
        continue
      fi
      repeat="$(ask_secret "Repeat the password")"
      if [ "$repeat" != "$store_pass" ]; then
        say "  the passwords differ"
        continue
      fi
      break
    done
    key_pass="$store_pass" # PKCS12 keystores use one password for both
    owner_name="$(ask "Name on the certificate" Wyrd)"
    # Characters with a meaning in a certificate name would break -dname.
    owner_name="${owner_name//[,+=\"\\<>;]/}"
    owner_name="${owner_name:-Wyrd}"
    mkdir -p "$(dirname "$keystore")"
    if ! WYRD_KEYSTORE_PASS="$store_pass" "$keytool" -genkeypair -keystore "$keystore" -storetype PKCS12 \
      -alias "$alias_name" -keyalg RSA -keysize 4096 -validity 10000 -dname "CN=$owner_name" \
      -storepass:env WYRD_KEYSTORE_PASS -keypass:env WYRD_KEYSTORE_PASS >/dev/null; then
      say "  ! keytool could not create the keystore; nothing stored"
      return 0
    fi
    chmod 600 "$keystore"
    say "  Created $keystore"
  else
    keystore="$(ask "Existing keystore file")"
    keystore="${keystore/#\~/$HOME}"
    if [ ! -f "$keystore" ]; then
      say "  ! $keystore not found"
      return 0
    fi
    alias_name="$(ask "Key alias" upload)"
    store_pass="$(ask_secret "Keystore password")"
    key_pass="$(ask_secret "Key password (Enter if the same)")"
    key_pass="${key_pass:-$store_pass}"
  fi
  if ! fingerprints="$(WYRD_KEYSTORE_PASS="$store_pass" "$keytool" -list -v -keystore "$keystore" \
    -alias "$alias_name" -storepass:env WYRD_KEYSTORE_PASS 2>/dev/null)"; then
    say "  ! the keystore does not open with that password or has no key named $alias_name; nothing stored"
    return 0
  fi
  say
  say "  ${bold}Signing certificate SHA-256${reset} (every release's notes show it, so people can check an APK is yours):"
  printf '%s\n' "$fingerprints" | grep -E '^[[:space:]]*SHA256:' | sed 's/^[[:space:]]*/    /' || true
  say
  base64 <"$keystore" | tr -d '\n' | gh secret set ANDROID_KEYSTORE_BASE64 --repo "$repo" >/dev/null
  say "  ✓ secret ANDROID_KEYSTORE_BASE64"
  set_secret ANDROID_KEYSTORE_PASSWORD "$store_pass"
  set_secret ANDROID_KEY_ALIAS "$alias_name"
  set_secret ANDROID_KEY_PASSWORD "$key_pass"
  note "  Back up $keystore and its password. If they are lost, phones can only"
  note "  install a newer Wyrd after uninstalling the old one (and losing local data)."
}

# --- Preconditions ------------------------------------------------------------

cd "$(dirname "${BASH_SOURCE[0]}")/.." || die "cannot find the repository root"
[ -f app/pubspec.yaml ] || die "run this script from the Wyrd repository"
command -v gh >/dev/null 2>&1 || die "install the GitHub CLI first: https://cli.github.com"
gh auth status >/dev/null 2>&1 || die "sign in to GitHub first: gh auth login"

if [ -z "$repo" ]; then
  repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)"
  [ -n "$repo" ] || die "could not tell which GitHub repository this is; pass --repo OWNER/REPO"
fi
say "${bold}Wyrd production setup${reset} for ${bold}$repo${reset}"
note "Values go to Settings > Secrets and variables > Actions of this repository."
confirm "Continue with $repo?" Y || exit 0
stored_secrets="$(gh secret list --repo "$repo" 2>/dev/null | cut -f1 || true)"
stored_variables="$(gh variable list --repo "$repo" 2>/dev/null | cut -f1 || true)"

# --- 1. Supabase ----------------------------------------------------------------

if group "Supabase" "Backend project, its API keys and the CLI token the backend deploy uses (docs/deployment.md, step 1)." \
  SUPABASE_PROJECT_ID SUPABASE_URL SUPABASE_PUBLISHABLE_KEY SUPABASE_SECRET_KEY SUPABASE_ACCESS_TOKEN SUPABASE_DB_PASSWORD; then
  known_ref=""
  stored_url="$(current_variable SUPABASE_URL)"
  if [[ "$stored_url" =~ ^https://([a-z0-9]{20})\.supabase\.co/?$ ]]; then known_ref="${BASH_REMATCH[1]}"; fi
  ref="$(ask "Project ref (from https://supabase.com/dashboard/project/<ref>)" "$known_ref")"
  warn_unless "$ref" '^[a-z0-9]{20}$' "a project ref is usually 20 lowercase letters"
  set_secret SUPABASE_PROJECT_ID "$ref"
  # A different project: its keys and database password are new too, so
  # nothing stored for the old project is offered as a default.
  new_project=false
  if [ -n "$ref" ] && [ -n "$known_ref" ] && [ "$ref" != "$known_ref" ]; then
    new_project=true
    note "  A new project: enter its own publishable key, secret key and database password."
  fi
  if [ -n "$ref" ]; then
    # The URL follows the ref typed now, even if another project's is stored.
    url="$(ask "Project URL" "https://$ref.supabase.co")"
    case "$url" in
      "https://$ref.supabase.co" | "https://$ref.supabase.co/") ;;
      *) note "  ! that URL is not the one of project $ref; the apps and the backend deploy would use different projects" ;;
    esac
  else
    url="$(variable_prompt SUPABASE_URL "Project URL")"
  fi
  set_variable SUPABASE_URL "${url%/}"
  if [ "$new_project" = true ]; then
    key="$(ask "Publishable key of $ref (sb_publishable_...)")"
  else
    key="$(variable_prompt SUPABASE_PUBLISHABLE_KEY "Publishable key (sb_publishable_...)")"
  fi
  case "$key" in
    sb_secret_*)
      # Variables are public: never store a secret key as one.
      say "  ! that is a secret key, not the publishable one; SUPABASE_PUBLISHABLE_KEY not changed"
      ;;
    *)
      warn_unless "$key" '^sb_publishable_' "that does not look like a publishable key"
      set_variable SUPABASE_PUBLISHABLE_KEY "$key"
      ;;
  esac
  if [ "$new_project" = true ]; then
    secret_key="$(ask_secret "Secret key of $ref (sb_secret_...; the backend deploy keeps it in the database Vault)")"
  else
    secret_key="$(secret_prompt SUPABASE_SECRET_KEY "Secret key (sb_secret_...; the backend deploy keeps it in the database Vault)")"
  fi
  warn_unless "$secret_key" '^sb_secret_' "secret keys start with sb_secret_"
  set_secret SUPABASE_SECRET_KEY "$secret_key"
  token="$(secret_prompt SUPABASE_ACCESS_TOKEN "Personal access token (sbp_..., https://supabase.com/dashboard/account/tokens)")"
  warn_unless "$token" '^sbp_' "personal access tokens start with sbp_"
  set_secret SUPABASE_ACCESS_TOKEN "$token"
  if [ "$new_project" = true ]; then
    db_password="$(ask_secret "Database password of $ref")"
  else
    db_password="$(secret_prompt SUPABASE_DB_PASSWORD "Database password")"
  fi
  set_secret SUPABASE_DB_PASSWORD "$db_password"
  if [ "$new_project" = true ] && { [ -z "$key" ] || [ -z "$secret_key" ] || [ -z "$db_password" ]; }; then
    note "  ! some values left empty still belong to the old project: deploys and the apps fail until you set them"
  fi
fi

# --- 2. Cloudflare --------------------------------------------------------------

pages_project="$(current_variable CF_PAGES_PROJECT)"
pages_project="${pages_project:-wyrd-app}"
old_pages_project="$pages_project"
if group "Cloudflare Pages" "Hosting for the web app; the deploy workflow creates the Pages project on its first run (step 2)." \
  CLOUDFLARE_API_TOKEN CLOUDFLARE_ACCOUNT_ID CF_PAGES_PROJECT; then
  set_secret CLOUDFLARE_API_TOKEN "$(secret_prompt CLOUDFLARE_API_TOKEN "API token with Account > Cloudflare Pages > Edit")"
  account=""
  if has_secret CLOUDFLARE_ACCOUNT_ID; then
    account="$(ask "Account ID (32 characters, Workers & Pages overview; Enter keeps the stored one)")"
  else
    account="$(ask "Account ID (32 characters, Workers & Pages overview)")"
  fi
  warn_unless "$account" '^[0-9a-f]{32}$' "an account ID is 32 hexadecimal characters"
  set_secret CLOUDFLARE_ACCOUNT_ID "$account"
  pages_project="$(ask "Pages project name (wyrd is taken)" "$pages_project")"
  warn_unless "$pages_project" '^[a-z0-9][a-z0-9-]*$' "use lowercase letters, digits and dashes"
  set_variable CF_PAGES_PROJECT "$pages_project"
fi

# --- Site address ---------------------------------------------------------------

# A renamed Pages project makes a stored https://<old name>.pages.dev address
# stale, so the group is offered again with the new address as default.
site_names="WYRD_SITE_URL"
site_default=""
stored_site="$(current_variable WYRD_SITE_URL)"
if [ "$pages_project" != "$old_pages_project" ] && [ "${stored_site%/}" = "https://$old_pages_project.pages.dev" ]; then
  site_names=""
  site_default="https://$pages_project.pages.dev"
  note "The Pages project is now $pages_project, but WYRD_SITE_URL still names $old_pages_project."
fi
# shellcheck disable=SC2086 # site_names is one name or none
if group "Site address" "The one public URL everything else uses (sign-in redirects, the backend's Site URL, release notes). Change it here when you move to your own domain." \
  $site_names; then
  if [ -n "$site_default" ]; then
    site="$(ask "Site URL" "$site_default")"
  else
    site="$(variable_prompt WYRD_SITE_URL "Site URL" "https://$pages_project.pages.dev")"
  fi
  site="${site%/}"
  warn_unless "$site" '^https://' "the site must be served over https"
  set_variable WYRD_SITE_URL "$site"
fi

# --- 3. E-mail ------------------------------------------------------------------

if group "E-mail sender (SMTP)" "Sign-in codes and password resets. Supabase's built-in mailer only reaches your team (step 3)." \
  SMTP_HOST SMTP_PORT SMTP_USER SMTP_PASS SMTP_ADMIN_EMAIL SMTP_SENDER_NAME; then
  say "  1) Brevo (free, 300 e-mails a day, verified sender address)"
  say "  2) Gmail with an app password"
  say "  3) Resend (needs your own domain)"
  say "  4) Other SMTP server"
  provider="$(ask "Provider" 1)"
  host="" port=587 user="" sender="" pass_hint="SMTP password"
  case "$provider" in
    1) host="smtp-relay.brevo.com" pass_hint="SMTP key (Brevo > SMTP & API > SMTP)" ;;
    2) host="smtp.gmail.com" pass_hint="16-character app password (https://myaccount.google.com/apppasswords)" ;;
    3) host="smtp.resend.com" user="resend" pass_hint="Resend API key (re_...)" ;;
    *) ;;
  esac
  host="$(ask "SMTP host" "$host")"
  port="$(ask "SMTP port" "$port")"
  warn_unless "$port" '^[0-9]+$' "the port is a number such as 587 or 465"
  if [ "$provider" = 1 ]; then note "  Brevo's SMTP login looks like 1a2b3c001@smtp-brevo.com (not your account e-mail)."; fi
  user="$(ask "SMTP user" "$user")"
  if [ "$provider" = 2 ]; then sender="$user"; fi
  sender="$(ask "Sender address (verified with the provider)" "$sender")"
  warn_unless "$sender" '^[^@ ]+@[^@ ]+$' "the sender should be an e-mail address"
  sender_name="$(ask "Sender name" "Wyrd")"
  set_secret SMTP_HOST "$host"
  set_secret SMTP_PORT "$port"
  set_secret SMTP_USER "$user"
  set_secret SMTP_PASS "$(secret_prompt SMTP_PASS "$pass_hint")"
  set_secret SMTP_ADMIN_EMAIL "$sender"
  set_secret SMTP_SENDER_NAME "$sender_name"
fi

# --- 4. Firebase ----------------------------------------------------------------

if group "Firebase Cloud Messaging" "Push notifications: the web and Android app config, the web push key and the server's service account (step 4)." \
  FIREBASE_PROJECT_ID FIREBASE_API_KEY FIREBASE_MESSAGING_SENDER_ID FIREBASE_APP_ID_WEB FIREBASE_APP_ID_ANDROID FIREBASE_VAPID_KEY FCM_SERVICE_ACCOUNT; then
  set_variable FIREBASE_PROJECT_ID "$(variable_prompt FIREBASE_PROJECT_ID "Project ID")"
  set_variable FIREBASE_API_KEY "$(variable_prompt FIREBASE_API_KEY "Web API key (apiKey, AIza...)")"
  set_variable FIREBASE_MESSAGING_SENDER_ID "$(variable_prompt FIREBASE_MESSAGING_SENDER_ID "Sender ID (messagingSenderId)")"
  set_variable FIREBASE_APP_ID_WEB "$(variable_prompt FIREBASE_APP_ID_WEB "Web app ID (1:...:web:...)")"
  set_variable FIREBASE_APP_ID_ANDROID "$(variable_prompt FIREBASE_APP_ID_ANDROID "Android app ID (1:...:android:...)")"
  set_variable FIREBASE_VAPID_KEY "$(variable_prompt FIREBASE_VAPID_KEY "Web push certificate key pair (VAPID public key)")"
  account_file="$(ask "Service-account JSON file (Enter to skip)")"
  account_file="${account_file/#\~/$HOME}"
  if [ -n "$account_file" ]; then
    if [ ! -f "$account_file" ]; then
      say "  ! $account_file not found; FCM_SERVICE_ACCOUNT not set"
    elif ! grep -q '"type": *"service_account"' "$account_file"; then
      say "  ! that file is not a service-account key; FCM_SERVICE_ACCOUNT not set"
    else
      gh secret set FCM_SERVICE_ACCOUNT --repo "$repo" <"$account_file" >/dev/null
      say "  ✓ secret FCM_SERVICE_ACCOUNT"
      note "  Delete the downloaded key file once you no longer need it: GitHub now holds a copy."
    fi
  fi
fi

# --- 5. Google and GitHub sign-in --------------------------------------------

if group "Google sign-in" "Web OAuth client in Google Cloud > Google Auth Platform > Clients (step 5). Its secret is shown once: if you did not keep it, open the client, click Add secret and paste the new one." \
  WYRD_GOOGLE_CLIENT_ID WYRD_GOOGLE_CLIENT_SECRET WYRD_AUTH_GOOGLE; then
  google_id="$(variable_prompt WYRD_GOOGLE_CLIENT_ID "Client ID (...apps.googleusercontent.com)")"
  warn_unless "$google_id" '\.apps\.googleusercontent\.com$' "Google client IDs end in .apps.googleusercontent.com"
  set_variable WYRD_GOOGLE_CLIENT_ID "$google_id"
  google_secret="$(secret_prompt WYRD_GOOGLE_CLIENT_SECRET "Client secret (GOCSPX-...)")"
  warn_unless "$google_secret" '^GOCSPX-' "Google client secrets start with GOCSPX-"
  set_secret WYRD_GOOGLE_CLIENT_SECRET "$google_secret"
  if confirm "Show the Google button in the app?" Y; then
    set_variable WYRD_AUTH_GOOGLE true
  else
    set_variable WYRD_AUTH_GOOGLE false
  fi
fi

if group "GitHub sign-in" "OAuth app from GitHub developer settings (step 5). GitHub reserves names starting with GITHUB_, so these are stored as WYRD_GITHUB_*." \
  WYRD_GITHUB_CLIENT_ID WYRD_GITHUB_CLIENT_SECRET WYRD_AUTH_GITHUB; then
  set_variable WYRD_GITHUB_CLIENT_ID "$(variable_prompt WYRD_GITHUB_CLIENT_ID "Client ID")"
  set_secret WYRD_GITHUB_CLIENT_SECRET "$(secret_prompt WYRD_GITHUB_CLIENT_SECRET "Client secret")"
  if confirm "Show the GitHub button in the app?" Y; then
    set_variable WYRD_AUTH_GITHUB true
  else
    set_variable WYRD_AUTH_GITHUB false
  fi
fi

# --- 6. Android -----------------------------------------------------------------

if group "Android release key" "Signs the APK on GitHub Releases. Every update must be signed with the same key: back it up (step 6)." \
  ANDROID_KEYSTORE_BASE64 ANDROID_KEYSTORE_PASSWORD ANDROID_KEY_ALIAS ANDROID_KEY_PASSWORD; then
  setup_android_key
fi

# --- 7. Backups -----------------------------------------------------------------

# succeeds when VALUE is one or more age public keys (comma or space separated).
age_recipients() {
  local one=""
  [ -n "$1" ] || return 1
  # shellcheck disable=SC2086 # split the list
  for one in ${1//,/ }; do
    [[ "$one" =~ ^age1[02-9ac-hj-np-z]{58}$ ]] || return 1
  done
}

stored_recipient="$(current_variable BACKUP_AGE_RECIPIENT)"
backup_names="BACKUP_AGE_RECIPIENT"
if [ -n "$stored_recipient" ] && ! age_recipients "$stored_recipient"; then
  # An earlier version stored whatever was typed. Never offer the value back.
  backup_names=""
  case "$stored_recipient" in
    *SECRET-KEY*)
      say "${bold}! BACKUP_AGE_RECIPIENT holds an age private key.${reset} Variables are not secret: treat the key pair as exposed."
      if confirm "Delete that variable now?" Y; then
        gh variable delete BACKUP_AGE_RECIPIENT --repo "$repo" >/dev/null
        say "  ✓ variable BACKUP_AGE_RECIPIENT deleted; create a new key pair below"
      fi
      ;;
    *) note "BACKUP_AGE_RECIPIENT is not an age public key; set it again below." ;;
  esac
  stored_recipient=""
fi

# shellcheck disable=SC2086 # backup_names is one name or none
if group "Encrypted backups" "Database dumps are encrypted to an age public key; only you keep the private key (step 7)." \
  $backup_names; then
  recipient="$stored_recipient"
  if [ -n "$recipient" ]; then
    recipient="$(ask "age public key" "$recipient")"
  else
    recipient="$(ask "age public key (age1...; Enter to create a new key pair)")"
  fi
  if [ -z "$recipient" ]; then
    if command -v age-keygen >/dev/null 2>&1; then
      key_file="$(ask "Where to save the private key" "${XDG_CONFIG_HOME:-$HOME/.config}/wyrd/wyrd-backup-key.txt")"
      key_file="${key_file/#\~/$HOME}"
      if [ -e "$key_file" ]; then
        say "  Using the existing key in $key_file"
      else
        mkdir -p "$(dirname "$key_file")"
        (umask 077 && age-keygen -o "$key_file" 2>/dev/null)
        say "  Created $key_file"
      fi
      recipient="$(age-keygen -y "$key_file")"
      note "  Keep a copy of $key_file somewhere safe and offline (a password manager works)."
      note "  Without it no backup can be decrypted."
    else
      say "  ! age-keygen not found (https://github.com/FiloSottile/age); BACKUP_AGE_RECIPIENT not set"
    fi
  fi
  # Variables are not secret: only public keys (age1...) may be stored, never
  # the private key (AGE-SECRET-KEY-...) from the same file.
  if [ -n "$recipient" ] && ! age_recipients "$recipient"; then
    case "$recipient" in
      *AGE-SECRET-KEY-*) say "  ! that is the private key: keep it offline and never put it in GitHub; BACKUP_AGE_RECIPIENT not changed" ;;
      *) say "  ! not an age public key (age1 followed by 58 characters); BACKUP_AGE_RECIPIENT not changed" ;;
    esac
  else
    set_variable BACKUP_AGE_RECIPIENT "$recipient"
  fi
fi

# --- Done -----------------------------------------------------------------------

printf '\n%sDone.%s Next (docs/deployment.md, "First deploy"):\n' "$bold" "$reset"
say "  1. Deploy the backend (Actions tab, backend deploy workflow)."
say "  2. Deploy the web app: gh workflow run deploy-web.yml --repo $repo"
say "  3. Release the Android app: git tag v1.0.0 && git push origin v1.0.0"
