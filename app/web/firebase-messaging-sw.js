// Push is off in this build: tool/gen_firebase_sw.sh found no FIREBASE_*
// values, so it wrote this stand-in instead of the real worker. The page never
// registers it while push is off; if an older build left a messaging worker
// installed, this one replaces it and then removes itself.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => event.waitUntil(self.registration.unregister()));
