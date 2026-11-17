import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// AI services a user can connect with their own key.
enum AiProviderKind {
  anthropic,
  openai,
  gemini,
  anthropicCompatible,
  openaiCompatible;

  bool get anthropicProtocol => this == anthropic || this == anthropicCompatible;
  bool get geminiProtocol => this == gemini;
  bool get customEndpoint => this == anthropicCompatible || this == openaiCompatible;

  String get defaultBaseUrl => switch (this) {
    anthropic => 'https://api.anthropic.com',
    openai => 'https://api.openai.com/v1',
    gemini => 'https://generativelanguage.googleapis.com/v1beta',
    _ => '',
  };

  static AiProviderKind? parse(Object? v) => AiProviderKind.values.asNameMap()[v];
}

/// A model id without Gemini's `models/` prefix, so `models/gemini-x` and
/// `gemini-x` compare equal wherever ids are matched.
String bareModelId(String id) => id.trim().replaceFirst(RegExp('^models/'), '');

/// Non-secret provider settings. The API key is stored separately in the
/// platform's secure storage and never synced.
@immutable
class AiProviderConfig {
  const AiProviderConfig({required this.kind, required this.model, this.baseUrl = ''});

  final AiProviderKind kind;
  final String model;

  /// Only used for compatible endpoints; official providers use theirs.
  final String baseUrl;

  String get effectiveBaseUrl {
    final url = (kind.customEndpoint ? baseUrl : kind.defaultBaseUrl).trim();
    return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  bool get isComplete => model.trim().isNotEmpty && effectiveBaseUrl.startsWith(RegExp('https?://'));

  Map<String, Object> toJson() => {'kind': kind.name, 'model': model, 'baseUrl': baseUrl};

  static AiProviderConfig? fromJson(Map<String, Object?> j) {
    final kind = AiProviderKind.parse(j['kind']);
    final model = j['model'];
    if (kind == null || model is! String) return null;
    return AiProviderConfig(kind: kind, model: model, baseUrl: j['baseUrl'] is String ? j['baseUrl']! as String : '');
  }
}

/// A model as a provider's model list names it.
@immutable
class AiModelInfo {
  const AiModelInfo(this.id, {this.displayName, this.created});

  /// The name requests use.
  final String id;

  /// A friendlier name, when the provider gives one.
  final String? displayName;

  /// When the provider released it, if it says; newer models come first.
  final DateTime? created;

  String get label {
    final name = displayName?.trim();
    return name == null || name.isEmpty ? id : name;
  }
}

/// Why a call failed. [region]: the provider refused the request, most
/// likely because it doesn't serve the country it came from (OpenAI,
/// Anthropic and Google refuse several, Iran among them).
enum AiErrorKind { auth, rateLimited, network, refused, badResponse, http, region }

class AiException implements Exception {
  const AiException(this.kind, [this.status, this.detail]);
  final AiErrorKind kind;
  final int? status;

  /// The provider's own explanation, shortened for display, with the key
  /// removed. Kept out of [toString] so it never reaches logs.
  final String? detail;

  @override
  String toString() => 'AiException(${kind.name}${status == null ? '' : ', $status'})';
}

/// Minimal client for the Anthropic Messages API, the OpenAI Chat
/// Completions API and Google's Gemini API, including services that
/// implement the first two protocols (OpenRouter, Groq, DeepSeek, Together,
/// Ollama, LM Studio, …). Requests are raw HTTP.
class AiClient {
  AiClient(this.config, this._apiKey, {http.Client? httpClient, bool? isWeb})
    : _http = httpClient ?? http.Client(),
      _isWeb = isWeb ?? kIsWeb;

  final AiProviderConfig config;
  final String _apiKey;
  final http.Client _http;
  final bool _isWeb;

  static const anthropicVersion = '2026-10-21';

  /// Returns the model's text reply. When [schema] is given, official
  /// Anthropic requests use structured output and OpenAI-protocol requests
  /// ask for a JSON object; endpoints that reject those options are retried
  /// once without them (the prompt itself also asks for JSON).
  Future<String> complete({
    required String system,
    required String user,
    Map<String, Object?>? schema,
    int maxTokens = 2048,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final structured = schema != null;
    try {
      return await _send(system, user, schema, maxTokens, structured: structured).timeout(timeout);
    } on AiException catch (e) {
      if (structured && e.kind == AiErrorKind.http && e.status == 400) {
        // A timeout here isn't caught by the sibling clause below.
        try {
          return await _send(system, user, schema, maxTokens, structured: false).timeout(timeout);
        } on TimeoutException {
          throw const AiException(AiErrorKind.network);
        }
      }
      rethrow;
    } on TimeoutException {
      throw const AiException(AiErrorKind.network);
    }
  }

  Future<String> _send(
    String system,
    String user,
    Map<String, Object?>? schema,
    int maxTokens, {
    required bool structured,
  }) => config.kind.anthropicProtocol
      ? _anthropic(system, user, schema, maxTokens, structured: structured)
      : config.kind.geminiProtocol
      ? _gemini(system, user, structured: structured)
      : _openai(system, user, maxTokens, structured: structured);

  Future<String> _anthropic(
    String system,
    String user,
    Map<String, Object?>? schema,
    int maxTokens, {
    required bool structured,
  }) async {
    final base = config.effectiveBaseUrl;
    final url = Uri.parse(base.endsWith('/v1') ? '$base/messages' : '$base/v1/messages');
    final body = <String, Object?>{
      'model': config.model.trim(),
      'max_tokens': maxTokens,
      'system': system,
      'messages': [
        {'role': 'user', 'content': user},
      ],
      // Structured output only on Anthropic's own API; compatible services
      // may not support output_config.
      if (structured && schema != null && config.kind == AiProviderKind.anthropic)
        'output_config': {
          'format': {'type': 'json_schema', 'schema': schema},
        },
    };
    final json = await _post(url, _anthropicHeaders, body);
    if (json['stop_reason'] == 'refusal') throw const AiException(AiErrorKind.refused);
    final content = json['content'];
    if (content is! List) throw const AiException(AiErrorKind.badResponse);
    final text = content
        .whereType<Map<Object?, Object?>>()
        .where((b) => b['type'] == 'text')
        .map((b) => b['text'])
        .whereType<String>()
        .join();
    if (text.trim().isEmpty) throw const AiException(AiErrorKind.badResponse);
    return text;
  }

  Future<String> _openai(String system, String user, int maxTokens, {required bool structured}) async {
    final url = Uri.parse('${config.effectiveBaseUrl}/chat/completions');
    final body = <String, Object?>{
      'model': config.model.trim(),
      'messages': [
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': user},
      ],
      if (structured) 'response_format': {'type': 'json_object'},
    };
    final json = await _post(url, {if (_apiKey.isNotEmpty) 'authorization': 'Bearer $_apiKey'}, body);
    final choices = json['choices'];
    if (choices is! List || choices.isEmpty || choices.first is! Map) {
      throw const AiException(AiErrorKind.badResponse);
    }
    final choice = choices.first as Map;
    final message = choice['message'];
    if (choice['finish_reason'] == 'content_filter' || (message is Map && message['refusal'] != null)) {
      throw const AiException(AiErrorKind.refused);
    }
    final text = message is Map ? message['content'] : null;
    if (text is! String || text.trim().isEmpty) throw const AiException(AiErrorKind.badResponse);
    return text;
  }

  /// Google Gemini `generateContent`. JSON mode via `responseMimeType`;
  /// no output-token cap, because thinking models count their reasoning
  /// against it and could cut the answer short.
  Future<String> _gemini(String system, String user, {required bool structured}) async {
    final model = bareModelId(config.model);
    final url = Uri.parse('${config.effectiveBaseUrl}/models/${Uri.encodeComponent(model)}:generateContent');
    final body = <String, Object?>{
      'systemInstruction': {
        'parts': [
          {'text': system},
        ],
      },
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': user},
          ],
        },
      ],
      if (structured) 'generationConfig': {'responseMimeType': 'application/json'},
    };
    final json = await _post(url, {'x-goog-api-key': _apiKey}, body);
    final feedback = json['promptFeedback'];
    if (feedback is Map && feedback['blockReason'] != null) throw const AiException(AiErrorKind.refused);
    final candidates = json['candidates'];
    if (candidates is! List || candidates.isEmpty || candidates.first is! Map) {
      throw const AiException(AiErrorKind.badResponse);
    }
    final candidate = candidates.first as Map;
    const blocked = {'SAFETY', 'PROHIBITED_CONTENT', 'BLOCKLIST', 'SPII', 'RECITATION'};
    if (blocked.contains(candidate['finishReason'])) throw const AiException(AiErrorKind.refused);
    final content = candidate['content'];
    final parts = content is Map ? content['parts'] : null;
    if (parts is! List) throw const AiException(AiErrorKind.badResponse);
    final text = parts
        .whereType<Map<Object?, Object?>>()
        .where((p) => p['thought'] != true)
        .map((p) => p['text'])
        .whereType<String>()
        .join();
    if (text.trim().isEmpty) throw const AiException(AiErrorKind.badResponse);
    return text;
  }

  Map<String, String> get _anthropicHeaders => {
    if (_apiKey.isNotEmpty) 'x-api-key': _apiKey,
    'anthropic-version': anthropicVersion,
    // Required for calls made directly from a browser (CORS).
    if (_isWeb) 'anthropic-dangerous-direct-browser-access': 'true',
  };

  /// Pages read at most when a model list is paged.
  static const _maxModelPages = 10;

  /// The models this provider offers for the key, so nobody has to type a
  /// name. Newest first when the provider dates them, otherwise in its own
  /// order. Gemini's list keeps only models that can write text, and
  /// OpenAI's only models its Chat Completions API serves; compatible
  /// services are listed as they come, minus entries that say they can't
  /// chat.
  Future<List<AiModelInfo>> listModels({Duration timeout = const Duration(seconds: 15)}) async {
    try {
      final models =
          await (config.kind.anthropicProtocol
                  ? _anthropicModels()
                  : config.kind.geminiProtocol
                  ? _geminiModels()
                  : _openaiModels())
              .timeout(timeout);
      return _newestFirst(models);
    } on TimeoutException {
      throw const AiException(AiErrorKind.network);
    } on FormatException {
      // A base URL that isn't a valid address.
      throw const AiException(AiErrorKind.network);
    }
  }

  Future<List<AiModelInfo>> _anthropicModels() async {
    final base = config.effectiveBaseUrl;
    final root = base.endsWith('/v1') ? base : '$base/v1';
    final models = <AiModelInfo>[];
    String? afterId;
    for (var page = 0; page < _maxModelPages; page++) {
      final json = await _get(
        Uri.parse('$root/models').replace(queryParameters: {'limit': '1000', 'after_id': ?afterId}),
        _anthropicHeaders,
      );
      if (json is! Map || json['data'] is! List) throw const AiException(AiErrorKind.badResponse);
      for (final m in (json['data'] as List).whereType<Map<Object?, Object?>>()) {
        final id = _text(m['id']);
        if (id == null) continue;
        models.add(AiModelInfo(id, displayName: _text(m['display_name']), created: _date(m['created_at'])));
      }
      final last = _text(json['last_id']);
      if (json['has_more'] != true || last == null) break;
      afterId = last;
    }
    return models;
  }

  Future<List<AiModelInfo>> _openaiModels() async {
    final json = await _get(Uri.parse('${config.effectiveBaseUrl}/models'), {
      // Local servers (Ollama, LM Studio) often need no key.
      if (_apiKey.isNotEmpty) 'authorization': 'Bearer $_apiKey',
    });
    // OpenAI and most compatible services answer {"data": [...]}; a few
    // (Together) send a bare list, and Ollama's own API uses "models".
    final list = switch (json) {
      final List<Object?> l => l,
      {'data': final List<Object?> l} => l,
      {'models': final List<Object?> l} => l,
      _ => null,
    };
    if (list == null) throw const AiException(AiErrorKind.badResponse);
    final official = config.kind == AiProviderKind.openai;
    final models = <AiModelInfo>[];
    for (final m in list.whereType<Map<Object?, Object?>>()) {
      final hasId = _text(m['id']) != null;
      final id = _text(m['id']) ?? _text(m['model']) ?? _text(m['name']);
      if (id == null || _cannotChat(m) || (official && _openAiNotForChat.hasMatch(id.toLowerCase()))) continue;
      // With an id, "name" is a display name (OpenRouter); without one it
      // is the id itself (Ollama).
      final name = _text(m['display_name']) ?? (hasId ? _text(m['name']) : null);
      models.add(AiModelInfo(id, displayName: name, created: _date(m['created'])));
    }
    return models;
  }

  Future<List<AiModelInfo>> _geminiModels() async {
    final models = <AiModelInfo>[];
    String? pageToken;
    for (var page = 0; page < _maxModelPages; page++) {
      final json = await _get(
        Uri.parse('${config.effectiveBaseUrl}/models')
            .replace(queryParameters: {'pageSize': '1000', 'pageToken': ?pageToken}),
        // In a header, never in the URL, where logs and proxies keep it.
        {'x-goog-api-key': _apiKey},
      );
      if (json is! Map) throw const AiException(AiErrorKind.badResponse);
      final list = json['models'] ?? const <Object?>[];
      if (list is! List) throw const AiException(AiErrorKind.badResponse);
      for (final m in list.whereType<Map<Object?, Object?>>()) {
        final name = _text(m['name']);
        final methods = m['supportedGenerationMethods'];
        if (name == null || (methods is List && !methods.contains('generateContent'))) continue;
        final id = bareModelId(name);
        if (_geminiNotForText.hasMatch(id)) continue;
        models.add(AiModelInfo(id, displayName: _text(m['displayName'])));
      }
      final next = _text(json['nextPageToken']);
      if (next == null) break;
      pageToken = next;
    }
    return models;
  }

  /// OpenAI models its Chat Completions API can't use for text: embeddings,
  /// speech, images, video, moderation, legacy completions, and models only
  /// its Responses API serves.
  static final _openAiNotForChat = RegExp(
    r'embedding|whisper|tts|transcri|realtime|audio|image|dall-e|sora|moderation|babbage|davinci|instruct'
    r'|computer-use|deep-research|codex|-pro\b',
  );

  /// Gemini models that answer with speech or images rather than text,
  /// although the list says they support generateContent.
  static final _geminiNotForText = RegExp(r'-tts\b|native-audio|image');

  /// Entries a compatible service marks as unable to chat, such as
  /// Mistral's capability flags or Together's model types.
  static bool _cannotChat(Map<Object?, Object?> m) {
    final capabilities = m['capabilities'];
    if (capabilities is Map && capabilities['completion_chat'] == false) return true;
    final type = m['type'];
    return type is String && _notChatTypes.contains(type.toLowerCase());
  }

  static const _notChatTypes = {'embedding', 'image', 'video', 'audio', 'transcribe', 'tts', 'moderation', 'rerank'};

  /// Drops repeats; puts newer models first when every one is dated.
  static List<AiModelInfo> _newestFirst(List<AiModelInfo> models) {
    final seen = <String>{};
    final unique = [
      for (final m in models)
        if (seen.add(m.id)) m,
    ];
    if (unique.any((m) => m.created == null)) return unique;
    final position = {for (final (i, m) in unique.indexed) m.id: i};
    return unique..sort((a, b) {
      final byDate = b.created!.compareTo(a.created!);
      return byDate != 0 ? byDate : position[a.id]!.compareTo(position[b.id]!);
    });
  }

  static String? _text(Object? v) => v is String && v.trim().isNotEmpty ? v.trim() : null;

  /// Seconds since 1970 (OpenAI style) or an ISO date (Anthropic style).
  static DateTime? _date(Object? v) => switch (v) {
    final num seconds when seconds > 0 => DateTime.fromMillisecondsSinceEpoch((seconds * 1000).round(), isUtc: true),
    final String s => DateTime.tryParse(s),
    _ => null,
  };

  Future<Map<String, Object?>> _post(Uri url, Map<String, String> headers, Map<String, Object?> body) async {
    final http.Response res;
    try {
      // Not followed, like model lists: a redirect could carry a key header
      // such as x-api-key to another host. In browsers a redirect then fails
      // as a network error.
      final request = http.Request('POST', url)
        ..followRedirects = false
        ..headers.addAll({'content-type': 'application/json', ...headers})
        ..body = jsonEncode(body);
      res = await http.Response.fromStream(await _http.send(request));
    } on Object {
      // Offline, DNS, TLS or a browser CORS block.
      throw const AiException(AiErrorKind.network);
    }
    final decoded = _decode(res);
    if (decoded is! Map) throw const AiException(AiErrorKind.badResponse);
    return Map<String, Object?>.from(decoded);
  }

  Future<Object?> _get(Uri url, Map<String, String> headers) async {
    final http.Response res;
    try {
      // Not followed on any platform: a redirect could carry a key header
      // such as x-api-key to another host. In browsers a redirect then fails
      // as a network error.
      final request = http.Request('GET', url)
        ..followRedirects = false
        ..headers.addAll(headers);
      res = await http.Response.fromStream(await _http.send(request));
    } on Object {
      throw const AiException(AiErrorKind.network);
    }
    return _decode(res);
  }

  Object? _decode(http.Response res) {
    final status = res.statusCode;
    if (status < 200 || status >= 300) {
      final body = utf8.decode(res.bodyBytes, allowMalformed: true);
      final detail = _providerMessage(body);
      // First: a region block also arrives as 400 or 403, and would
      // otherwise read as a bad key.
      if (_regionBlocked(status, body)) throw AiException(AiErrorKind.region, status, detail);
      // Anthropic refuses browser calls for some organisations; Anthropic
      // says this isn't a problem with the key.
      if (status == 401 && body.contains('CORS requests are not allowed')) {
        throw AiException(AiErrorKind.network, status, detail);
      }
      if (status == 401 || status == 403) throw AiException(AiErrorKind.auth, status, detail);
      if (status == 429) throw AiException(AiErrorKind.rateLimited, status, detail);
      // Google answers a wrong key with 400 rather than 401.
      if (status == 400 && config.kind.geminiProtocol && body.contains('API_KEY_INVALID')) {
        throw AiException(AiErrorKind.auth, status, detail);
      }
      throw AiException(AiErrorKind.http, status, detail);
    }
    try {
      return jsonDecode(utf8.decode(res.bodyBytes));
    } on FormatException {
      throw const AiException(AiErrorKind.badResponse);
    }
  }

  /// How providers say a request was refused because of where it came
  /// from: OpenAI (403 unsupported_country_region_territory), Google (400
  /// "User location is not supported"), Anthropic through clouds (400
  /// "unsupported countries, regions, or territories"), OpenRouter (403 "not
  /// available in your region") and Cloudflare's country ban (403 "error
  /// code: 1009"). Anthropic's own API answers 403 forbidden "Request not
  /// allowed", which can also mean a closed workspace; the message says
  /// "most likely".
  static final _regionMarkers = RegExp(
    r'unsupported_country_region_territory|User location is not supported'
    r'|unsupported countries, regions,? or territories|not available in your (region|country)'
    r'|error code: 1009|banned the country or region',
    caseSensitive: false,
  );

  static bool _regionBlocked(int status, String body) =>
      status == 451 ||
      ((status == 400 || status == 403) && _regionMarkers.hasMatch(body)) ||
      (status == 403 && body.contains('"forbidden"') && body.contains('Request not allowed'));

  /// The provider's error message, if the body has one: `error.message`
  /// (OpenAI, Anthropic, Gemini and most compatible services), the same
  /// inside a list (Google's OpenAI-compatible endpoint), a bare `error`
  /// string, or a top-level `message` or `detail`. One line, at most 200
  /// characters, never containing the key.
  String? _providerMessage(String body) {
    Object? json;
    try {
      json = jsonDecode(body);
    } on FormatException {
      return null;
    }
    final message = switch (json) {
      {'error': {'message': final String m}} => m,
      [{'error': {'message': final String m}}, ...] => m,
      {'error': final String m} => m,
      {'message': final String m} => m,
      {'detail': final String m} => m,
      _ => null,
    };
    if (message == null) return null;
    var text = message.replaceAll(RegExp(r'\s+'), ' ').trim();
    final key = _apiKey.trim();
    if (key.length >= 4) text = text.replaceAll(key, '…');
    if (text.isEmpty) return null;
    if (text.length <= 200) return text;
    // Never cut a character in half: an emoji is two code units.
    var end = 199;
    final last = text.codeUnitAt(end - 1);
    if (last >= 0xD800 && last <= 0xDBFF) end--;
    return '${text.substring(0, end)}…';
  }
}
