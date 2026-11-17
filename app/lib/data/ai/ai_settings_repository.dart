import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../db/database.dart';
import 'ai_client.dart';

/// Where the API key lives: the platform's secure storage (Keychain on
/// iOS, Keystore-backed storage on Android, encrypted browser storage on
/// the web). Abstracted for tests.
abstract class KeyStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> delete();
}

class SecureKeyStore implements KeyStore {
  SecureKeyStore([FlutterSecureStorage? storage]) : _s = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _s;
  static const _key = 'wyrd.ai.api_key';

  @override
  Future<String?> read() => _s.read(key: _key);
  @override
  Future<void> write(String value) => _s.write(key: _key, value: value);
  @override
  Future<void> delete() => _s.delete(key: _key);
}

class MemoryKeyStore implements KeyStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String v) async => value = v;
  @override
  Future<void> delete() async => value = null;
}

/// The user's own AI provider. Settings are stored locally, the key in
/// secure storage; neither is synced to the server.
class AiSettingsRepository {
  AiSettingsRepository(this._db, this._keys, {http.Client? httpClient}) : _http = httpClient;

  final AppDatabase _db;
  final KeyStore _keys;
  final http.Client? _http;
  static const _configKey = 'ai_provider';

  Future<AiProviderConfig?> config() async {
    final row = await (_db.select(_db.keyValues)..where((k) => k.key.equals(_configKey))).getSingleOrNull();
    if (row == null) return null;
    return AiProviderConfig.fromJson(jsonDecode(row.value) as Map<String, Object?>);
  }

  Stream<AiProviderConfig?> watchConfig() => (_db.select(_db.keyValues)..where((k) => k.key.equals(_configKey)))
      .watchSingleOrNull()
      .map((row) => row == null ? null : AiProviderConfig.fromJson(jsonDecode(row.value) as Map<String, Object?>));

  Future<bool> hasKey() async => ((await _keys.read()) ?? '').isNotEmpty;

  /// Whether [a] and [b] are the same service: the same kind at the same
  /// address. A key belongs to exactly one service.
  static bool sameService(AiProviderConfig? a, AiProviderConfig b) =>
      a != null && a.kind == b.kind && a.effectiveBaseUrl == b.effectiveBaseUrl;

  /// Saves the provider. A null or empty [apiKey] keeps the stored key for
  /// the same service only: moving to another service without a new key,
  /// or saving when no settings own the stored key, deletes it, so it can't
  /// be sent where it doesn't belong. The key is settled before the settings
  /// are written, so a failure can't leave new settings paired with an old
  /// key.
  Future<void> save(AiProviderConfig config, {String? apiKey}) async {
    final previous = await this.config();
    final key = apiKey?.trim() ?? '';
    if (key.isNotEmpty) {
      await _keys.write(key);
    } else if (!sameService(previous, config)) {
      await _keys.delete();
    }
    await _db
        .into(_db.keyValues)
        .insertOnConflictUpdate(KeyValuesCompanion.insert(key: _configKey, value: jsonEncode(config.toJson())));
  }

  Future<void> clear() async {
    await (_db.delete(_db.keyValues)..where((k) => k.key.equals(_configKey))).go();
    await _keys.delete();
  }

  /// The models [config]'s provider lists. Asks with [apiKey], or when that
  /// is empty with the saved key, but only if the saved provider is the
  /// same service, so a key never reaches a provider it wasn't made for.
  /// Null when there is no key to ask with. Custom services are tried
  /// without one, because local servers often need none.
  Future<List<AiModelInfo>?> listModels(AiProviderConfig config, {String? apiKey}) async {
    var key = apiKey?.trim() ?? '';
    if (key.isEmpty) {
      final saved = await this.config();
      if (sameService(saved, config)) {
        try {
          key = (await _keys.read())?.trim() ?? '';
        } on Object {
          key = '';
        }
      }
    }
    if (key.isEmpty && !config.kind.customEndpoint) return null;
    try {
      return await AiClient(config, key, httpClient: _http).listModels();
    } on AiException catch (e) {
      if (key.isEmpty && e.kind == AiErrorKind.auth) return null;
      rethrow;
    }
  }

  /// A ready client, or null when no complete provider is set, or when an
  /// official provider has no key. Custom services may run without one
  /// (local servers such as Ollama need none).
  Future<AiClient?> client() async {
    final c = await config();
    if (c == null || !c.isComplete) return null;
    String key;
    try {
      key = (await _keys.read())?.trim() ?? '';
    } on Object {
      key = '';
    }
    if (key.isEmpty && !c.kind.customEndpoint) return null;
    return AiClient(c, key, httpClient: _http);
  }
}
