// Firebase Cloud Messaging service worker for the Wyrd web app.
//
// tool/gen_firebase_sw.sh turns this template into firebase-messaging-sw.js,
// filling in the Firebase placeholders below. The Firebase SDK in the page
// registers that file under its own scope (/firebase-cloud-messaging-push-scope),
// so it never takes over from Flutter's service worker at the site root.
//
// Keep the version in step with the JS SDK that firebase_core_web loads in the
// page (supportedFirebaseJsSdkVersion in firebase_core_web's sources).
importScripts('https://www.gstatic.com/firebasejs/13.1.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/13.1.0/firebase-messaging-compat.js');

const APP_URL = new URL('./', self.location.href).href;
const ICON = new URL('icons/Icon-192.png', APP_URL).href;

// Every notification gets the app icon, including the ones the SDK draws by
// itself for messages that carry a `notification` block.
const showNotification = self.registration.showNotification.bind(self.registration);
self.registration.showNotification = (title, options = {}) => showNotification(title, { icon: ICON, ...options });

// Added before the SDK's own click listener, so this one decides what a tap
// does: focus an open Wyrd window, or open the app.
self.addEventListener('notificationclick', (event) => {
  event.stopImmediatePropagation();
  event.notification.close();
  event.waitUntil(openApp());
});

async function openApp() {
  const windows = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
  const open = windows.find((client) => client.url.startsWith(APP_URL));
  return open ? open.focus() : self.clients.openWindow(APP_URL);
}

firebase.initializeApp({
  apiKey: '__FIREBASE_API_KEY__',
  appId: '__FIREBASE_APP_ID_WEB__',
  messagingSenderId: '__FIREBASE_MESSAGING_SENDER_ID__',
  projectId: '__FIREBASE_PROJECT_ID__',
});

const messaging = firebase.messaging();

// Messages with a `notification` block are already shown by the SDK, so only
// data-only messages are drawn here, from data.title and data.body.
messaging.onBackgroundMessage((payload) => {
  const data = payload.data || {};
  if (payload.notification || !data.title) return undefined;
  return self.registration.showNotification(data.title, { body: data.body || '', data });
});
