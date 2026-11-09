import 'dart:js_interop';

// The browser's address, for taking a failed sign-in's error out of it.
// Every access is guarded: the address is never worth an error.

@JS('window')
external _Window get _window;

extension type _Window._(JSObject _) implements JSObject {
  external _Location get location;
  external _History get history;
}

extension type _Location._(JSObject _) implements JSObject {
  external String get href;
}

extension type _History._(JSObject _) implements JSObject {
  external JSAny? get state;
  external void replaceState(JSAny? state, String unused, String url);
}

String? currentUrl() {
  try {
    return _window.location.href;
  } catch (_) {
    return null;
  }
}

void replaceUrl(String url) {
  try {
    final history = _window.history;
    // The entry keeps its state: Flutter's router numbers its history there.
    history.replaceState(history.state, '', url);
  } catch (_) {
    // The address stays as it was; a reload shows the error once more.
  }
}
