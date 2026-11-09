#!/usr/bin/env bash
# Writes app/web/firebase-messaging-sw.js, the web push service worker, from
# app/web/firebase-messaging-sw.template.js. Run it before `flutter build web`.
#
# Reads FIREBASE_API_KEY, FIREBASE_APP_ID_WEB, FIREBASE_MESSAGING_SENDER_ID and
# FIREBASE_PROJECT_ID: the same values the web build gets as --dart-define.
# With none of them set it writes a harmless no-op worker instead (the
# committed version), so builds without push never fail. Setting only some of
# them is a mistake and fails.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
template="$root/app/web/firebase-messaging-sw.template.js"
out="$root/app/web/firebase-messaging-sw.js"
names="FIREBASE_API_KEY FIREBASE_APP_ID_WEB FIREBASE_MESSAGING_SENDER_ID FIREBASE_PROJECT_ID"

given=""
missing=""
for name in $names; do
  if [[ -n "${!name:-}" ]]; then given="$given $name"; else missing="$missing $name"; fi
done

if [[ -z "$given" ]]; then
  cat >"$out" <<'JS'
// Push is off in this build: tool/gen_firebase_sw.sh found no FIREBASE_*
// values, so it wrote this stand-in instead of the real worker. The page never
// registers it while push is off; if an older build left a messaging worker
// installed, this one replaces it and then removes itself.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => event.waitUntil(self.registration.unregister()));
JS
  echo "gen_firebase_sw: push off (no FIREBASE_* values), wrote the no-op worker" >&2
  exit 0
fi

if [[ -n "$missing" ]]; then
  echo "gen_firebase_sw: push is half configured; also set:$missing" >&2
  exit 1
fi

content="$(cat "$template")"
for name in $names; do
  value="${!name}"
  # Firebase identifiers are plain tokens; refuse anything that could break
  # out of the JavaScript string it is pasted into.
  if [[ ! "$value" =~ ^[A-Za-z0-9:._-]+$ ]]; then
    echo "gen_firebase_sw: $name contains unexpected characters" >&2
    exit 1
  fi
  content=${content//__${name}__/$value}
done
if [[ "$content" =~ __FIREBASE_[A-Z_]+__ ]]; then
  echo "gen_firebase_sw: the template has a placeholder this script does not fill" >&2
  exit 1
fi
printf '%s\n' "$content" >"$out"
echo "gen_firebase_sw: wrote the messaging worker for project $FIREBASE_PROJECT_ID"
if [[ -z "${FIREBASE_VAPID_KEY:-}" ]]; then
  echo "gen_firebase_sw: warning: FIREBASE_VAPID_KEY is unset; the web app keeps push off without it" >&2
fi
