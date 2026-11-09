import 'dart:js_interop';

// Browser facts for the install hint. Every access is guarded: storage can be
// blocked (private browsing, disabled cookies) and the hint is never worth an
// error.

@JS('window')
external _Window get _window;

extension type _Window._(JSObject _) implements JSObject {
  external _MediaQueryList matchMedia(String query);
  external _Navigator get navigator;
  external _Storage get localStorage;
}

extension type _MediaQueryList._(JSObject _) implements JSObject {
  external bool get matches;
}

extension type _Navigator._(JSObject _) implements JSObject {
  /// Safari only: true when the page was opened from the Home Screen.
  external bool? get standalone;
}

extension type _Storage._(JSObject _) implements JSObject {
  external String? getItem(String key);
  external void setItem(String key, String value);
}

/// Whether the app already runs as an installed (Home Screen) web app.
bool runsFromHomeScreen() {
  try {
    return _window.navigator.standalone == true || _window.matchMedia('(display-mode: standalone)').matches;
  } catch (_) {
    return false;
  }
}

bool readFlag(String key) {
  try {
    return _window.localStorage.getItem(key) != null;
  } catch (_) {
    return false;
  }
}

void writeFlag(String key) {
  try {
    _window.localStorage.setItem(key, '1');
  } catch (_) {
    // Not remembered; the hint may show again on the next visit.
  }
}
