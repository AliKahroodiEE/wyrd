import 'package:flutter/foundation.dart';

import 'sign_in_link_browser_stub.dart' if (dart.library.js_interop) 'sign_in_link_browser_web.dart' as browser;

/// What Auth adds to the web app's address when a Google or GitHub sign-in
/// fails, in the query and again in the fragment:
/// `?error=access_denied&error_code=…&error_description=…#error=access_denied&…`.
const _errorKeys = {'error', 'error_code', 'error_description'};

/// The query also loses the sign-in `code` once an error was reported: a
/// code whose exchange failed (flow_state_not_found, a missing verifier)
/// would otherwise be tried, and fail, again on every reload.
const _queryKeys = {..._errorKeys, 'code'};

/// Takes a failed sign-in's error out of the browser's address once the app
/// has said so. supabase_flutter clears the address only after a sign-in that
/// worked, so until then every reload of the tab, a restored tab or a bookmark
/// of it would report the same error again. Does nothing outside the browser,
/// or when the address carries no such error.
void forgetSignInError() {
  final url = browser.currentUrl();
  if (url == null) return;
  final cleaned = withoutSignInError(url);
  if (cleaned != url) browser.replaceUrl(cleaned);
}

/// [url] without the `error`, `error_code` and `error_description` parameters
/// Auth adds to its query and its fragment, and without the query's sign-in
/// `code`. Everything else stays as written: other parameters, and the hash
/// route the web app's location lives in (`#/settings`), whose own
/// parameters lose the three error keys only. [url] comes back unchanged
/// when it has none of them.
@visibleForTesting
String withoutSignInError(String url) {
  final hashAt = url.indexOf('#');
  final beforeHash = hashAt < 0 ? url : url.substring(0, hashAt);
  final queryAt = beforeHash.indexOf('?');
  final cleaned = StringBuffer(queryAt < 0 ? beforeHash : beforeHash.substring(0, queryAt));
  if (queryAt >= 0) {
    final query = _withoutErrorKeys(beforeHash.substring(queryAt + 1), keys: _queryKeys);
    if (query != null) cleaned.write('?$query');
  }
  if (hashAt >= 0) {
    final fragment = _fragmentWithoutErrorKeys(url.substring(hashAt + 1));
    if (fragment != null) cleaned.write('#$fragment');
  }
  return cleaned.toString();
}

/// [fragment] without the error keys, or null when nothing is left of it.
String? _fragmentWithoutErrorKeys(String fragment) {
  // Auth writes plain parameters; a hash route (`/settings?tab=push`) keeps
  // its own after a `?`.
  if (!fragment.startsWith('/')) return _withoutErrorKeys(fragment);
  final queryAt = fragment.indexOf('?');
  if (queryAt < 0) return fragment;
  final route = fragment.substring(0, queryAt);
  final query = _withoutErrorKeys(fragment.substring(queryAt + 1));
  return query == null ? route : '$route?$query';
}

/// [parameters] (`a=1&b=2`) without [keys]: the same text when it has none
/// of them, null when nothing else is left.
String? _withoutErrorKeys(String parameters, {Set<String> keys = _errorKeys}) {
  final all = parameters.split('&');
  final kept = [
    for (final parameter in all)
      if (!keys.contains(_name(parameter))) parameter,
  ];
  if (kept.length == all.length) return parameters;
  final rest = kept.where((parameter) => parameter.isNotEmpty);
  return rest.isEmpty ? null : rest.join('&');
}

/// The decoded name of a `name=value` parameter; as written when malformed.
String _name(String parameter) {
  final name = parameter.split('=').first;
  try {
    return Uri.decodeQueryComponent(name);
  } on Object {
    return name;
  }
}
