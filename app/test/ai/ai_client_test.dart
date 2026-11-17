import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wyrd/data/ai/ai_client.dart';
import 'package:wyrd/data/ai/ai_evaluator.dart';
import 'package:wyrd/data/ai/ai_settings_repository.dart';
import 'package:wyrd/data/ai/evaluation_prompt.dart';
import 'package:wyrd/data/db/database.dart';
import 'package:wyrd_engine/wyrd_engine.dart';

const _proposal = {
  'category': 'study',
  'similarityKey': 'study.electronics',
  'difficulty': 3,
  'estimatedMinutes': 90,
  'attributes': [
    {'attribute': 'intelligence', 'weight': 0.8, 'reason': 'Analysing circuits builds knowledge.'},
    {'attribute': 'discipline', 'weight': 0.2, 'reason': 'A long focused session.'},
  ],
  'trivial': false,
  'confidence': 0.9,
  'summary': '90 minutes of electronics study',
};

const _input = AiEvaluationInput(title: 'Study electronics <script>', tier: QuestTier.daily, outputLanguage: 'fa');

void main() {
  test('Anthropic: documented headers, structured output, text parsed', () async {
    late http.Request seen;
    final client = MockClient((req) async {
      seen = req;
      return http.Response(
        jsonEncode({
          'stop_reason': 'end_turn',
          'content': [
            {'type': 'text', 'text': jsonEncode(_proposal)},
          ],
        }),
        200,
      );
    });
    final ai = AiClient(
      const AiProviderConfig(kind: AiProviderKind.anthropic, model: 'claude-opus-5-5'),
      'sk-test',
      httpClient: client,
      isWeb: true,
    );
    final p = await AiEvaluator(ai).evaluate(_input);
    expect(seen.url.toString(), 'https://api.anthropic.com/v1/messages');
    expect(seen.headers['x-api-key'], 'sk-test');
    expect(seen.headers['anthropic-version'], AiClient.anthropicVersion);
    expect(seen.headers['anthropic-dangerous-direct-browser-access'], 'true');
    final body = jsonDecode(seen.body) as Map<String, Object?>;
    expect((body['output_config']! as Map)['format'], isNotNull);
    expect(body['system'], evaluationSystemPrompt);
    expect(body['messages'].toString(), contains(r'<script>'));
    expect(p.category, QuestCategory.study);
    expect(p.source, ProposalSource.ai);
  });

  test('OpenAI-compatible: base URL, bearer key, JSON mode, retry without it on 400', () async {
    final bodies = <Map<String, Object?>>[];
    late Uri url;
    late Map<String, String> headers;
    final client = MockClient((req) async {
      url = req.url;
      headers = req.headers;
      final body = jsonDecode(req.body) as Map<String, Object?>;
      bodies.add(body);
      if (body.containsKey('response_format')) return http.Response('{"error":"unsupported"}', 400);
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'finish_reason': 'stop',
              'message': {'content': 'Here you go:\n```json\n${jsonEncode(_proposal)}\n```'},
            },
          ],
        }),
        200,
      );
    });
    final ai = AiClient(
      const AiProviderConfig(
        kind: AiProviderKind.openaiCompatible,
        model: 'meta-llama/llama-4',
        baseUrl: 'https://openrouter.ai/api/v1/',
      ),
      'or-key',
      httpClient: client,
      isWeb: false,
    );
    final p = await AiEvaluator(ai).evaluate(_input);
    expect(url.toString(), 'https://openrouter.ai/api/v1/chat/completions');
    expect(headers['authorization'], 'Bearer or-key');
    expect(bodies, hasLength(2));
    expect(bodies.first['response_format'], {'type': 'json_object'});
    expect(bodies.last.containsKey('response_format'), isFalse);
    expect(((bodies.last['messages']! as List).first as Map)['content'], contains(AiEvaluator.jsonInstruction.trim()));
    expect(p.similarityKey, 'study.electronics');
  });

  test('Gemini: generateContent URL, key header, JSON mode, thoughts skipped', () async {
    late http.Request seen;
    final client = MockClient((req) async {
      seen = req;
      return http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'candidates': [
              {
                'finishReason': 'STOP',
                'content': {
                  'parts': [
                    {'text': 'thinking…', 'thought': true},
                    {'text': jsonEncode(_proposal)},
                  ],
                },
              },
            ],
          }),
        ),
        200,
      );
    });
    final ai = AiClient(
      const AiProviderConfig(kind: AiProviderKind.gemini, model: 'models/gemini-pro'),
      'g-key',
      httpClient: client,
    );
    final p = await AiEvaluator(ai).evaluate(_input);
    expect(seen.url.toString(), 'https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent');
    expect(seen.headers['x-goog-api-key'], 'g-key');
    expect(seen.url.queryParameters, isEmpty, reason: 'the key never goes in the URL');
    final body = jsonDecode(seen.body) as Map<String, Object?>;
    expect((body['generationConfig']! as Map)['responseMimeType'], 'application/json');
    expect(((body['systemInstruction']! as Map)['parts'] as List).first.toString(), contains('JSON object'));
    expect(p.estimatedMinutes, 90);
  });

  test('Gemini safety blocks are reported as refusals', () async {
    final ai = AiClient(
      const AiProviderConfig(kind: AiProviderKind.gemini, model: 'gemini-pro'),
      'k',
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'candidates': [
              {'finishReason': 'SAFETY'},
            ],
          }),
          200,
        ),
      ),
    );
    expect(
      () => ai.complete(system: 's', user: 'u'),
      throwsA(isA<AiException>().having((e) => e.kind, 'kind', AiErrorKind.refused)),
    );
  });

  test('errors map to clear kinds', () async {
    Future<AiErrorKind> kindFor(http.Response r) async {
      final ai = AiClient(
        const AiProviderConfig(kind: AiProviderKind.openai, model: 'm'),
        'k',
        httpClient: MockClient((_) async => r),
      );
      try {
        await ai.complete(system: 's', user: 'u');
        return AiErrorKind.http;
      } on AiException catch (e) {
        return e.kind;
      }
    }

    expect(await kindFor(http.Response('', 401)), AiErrorKind.auth);
    expect(await kindFor(http.Response('', 429)), AiErrorKind.rateLimited);
    expect(
      await kindFor(
        http.Response(
          jsonEncode({
            'choices': [
              {
                'finish_reason': 'stop',
                'message': {'content': null, 'refusal': 'no'},
              },
            ],
          }),
          200,
        ),
      ),
      AiErrorKind.refused,
    );
  });

  test('parser rejects incomplete or invalid proposals', () {
    expect(AiEvaluator.parseProposal('no json here'), isNull);
    expect(AiEvaluator.parseProposal(jsonEncode({..._proposal}..remove('summary'))), isNull);
    expect(AiEvaluator.parseProposal(jsonEncode({..._proposal, 'category': 'hacking'})), isNull);
    expect(AiEvaluator.parseProposal(jsonEncode({..._proposal, 'difficulty': 9})), isNull);
    expect(AiEvaluator.toServerJson(AiEvaluator.parseProposal(jsonEncode(_proposal))!).containsKey('source'), isFalse);
  });

  test('the app prompt matches the server prompt byte for byte', () {
    final ts = File('../backend/supabase/functions/_shared/ai/evaluation.ts').readAsStringSync();
    final server = RegExp(r'export const EVALUATION_SYSTEM_PROMPT = `(.*?)`;', dotAll: true).firstMatch(ts)!.group(1);
    expect(evaluationSystemPrompt, server);
  });

  test('settings keep the key in the key store and build a client', () async {
    final db = AppDatabase(DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true));
    addTearDown(db.close);
    final keys = MemoryKeyStore();
    final repo = AiSettingsRepository(db, keys);
    expect(await repo.client(), isNull);
    await repo.save(
      const AiProviderConfig(kind: AiProviderKind.anthropic, model: 'claude-opus-5-5'),
      apiKey: ' sk ',
    );
    expect(keys.value, 'sk');
    expect((await repo.config())!.model, 'claude-opus-5-5');
    expect(await repo.client(), isNotNull);
    final stored = await db.select(db.keyValues).get();
    expect(stored.any((r) => r.value.contains('sk')), isFalse, reason: 'key never stored in the database');
    await repo.clear();
    expect(await repo.hasKey(), isFalse);
  });

  group('model lists', () {
    AiClient clientFor(AiProviderConfig config, MockClient http, {String key = 'k', bool isWeb = false}) =>
        AiClient(config, key, httpClient: http, isWeb: isWeb);

    test('Anthropic: documented headers, every page, newest first', () async {
      final seen = <http.Request>[];
      final ai = clientFor(
        const AiProviderConfig(kind: AiProviderKind.anthropic, model: ''),
        MockClient((req) async {
          seen.add(req);
          final firstPage = req.url.queryParameters['after_id'] == null;
          return http.Response(
            jsonEncode(
              firstPage
                  ? {
                      'data': [
                        {'id': 'model-b', 'display_name': 'Model B', 'created_at': '2026-09-01T00:00:00Z'},
                        {'id': 'model-c', 'display_name': 'Model C', 'created_at': '2026-08-01T00:00:00Z'},
                      ],
                      'has_more': true,
                      'last_id': 'model-c',
                    }
                  : {
                      'data': [
                        {'id': 'model-a', 'display_name': 'Model A', 'created_at': '2026-10-01T00:00:00Z'},
                      ],
                      'has_more': false,
                      'last_id': 'model-a',
                    },
            ),
            200,
          );
        }),
        key: 'sk-test',
        isWeb: true,
      );
      final models = await ai.listModels();
      expect(models.map((m) => m.id), ['model-a', 'model-b', 'model-c']);
      expect(models.first.label, 'Model A');
      expect(seen, hasLength(2));
      expect(seen.first.method, 'GET');
      expect(seen.first.url.toString(), 'https://api.anthropic.com/v1/models?limit=1000');
      expect(seen.last.url.queryParameters['after_id'], 'model-c');
      expect(seen.first.headers['x-api-key'], 'sk-test');
      expect(seen.first.headers['anthropic-version'], AiClient.anthropicVersion);
      expect(seen.first.headers['anthropic-dangerous-direct-browser-access'], 'true');
    });

    test('Anthropic-compatible: a base URL that already ends in /v1', () async {
      late Uri url;
      final ai = clientFor(
        const AiProviderConfig(
          kind: AiProviderKind.anthropicCompatible,
          model: '',
          baseUrl: 'https://llm.example.test/anthropic/v1/',
        ),
        MockClient((req) async {
          url = req.url;
          return http.Response(
            jsonEncode({
              'data': [
                {'id': 'compatible-model'},
              ],
              'has_more': false,
            }),
            200,
          );
        }),
      );
      final models = await ai.listModels();
      expect(url.path, '/anthropic/v1/models');
      expect(models.single.label, 'compatible-model', reason: 'no display name: the id is shown');
    });

    test('OpenAI: bearer key, chat models only, newest first, no repeats', () async {
      late http.Request seen;
      final ai = clientFor(
        const AiProviderConfig(kind: AiProviderKind.openai, model: ''),
        MockClient((req) async {
          seen = req;
          return http.Response(
            jsonEncode({
              'object': 'list',
              'data': [
                {'id': 'gpt-old', 'created': 1600000000},
                {'id': 'text-embedding-3-large', 'created': 1700000000},
                {'id': 'gpt-new', 'created': 1790000000},
                {'id': 'whisper-1', 'created': 1650000000},
                {'id': 'gpt-new-mini-tts', 'created': 1780000000},
                {'id': 'gpt-image-2', 'created': 1781000000},
                {'id': 'o9-pro', 'created': 1785000000},
                {'id': 'gpt-new', 'created': 1790000000},
              ],
            }),
            200,
          );
        }),
        key: 'sk-o',
      );
      final models = await ai.listModels();
      expect(seen.url.toString(), 'https://api.openai.com/v1/models');
      expect(seen.headers['authorization'], 'Bearer sk-o');
      expect(models.map((m) => m.id), ['gpt-new', 'gpt-old']);
    });

    test('OpenAI-compatible: display names, bare lists, Ollama, and no key for local servers', () async {
      Future<List<AiModelInfo>> list(Object body, {String key = ''}) async {
        late http.Request seen;
        final models = await clientFor(
          const AiProviderConfig(
            kind: AiProviderKind.openaiCompatible,
            model: '',
            baseUrl: 'http://localhost:11434/v1',
          ),
          MockClient((req) async {
            seen = req;
            return http.Response(jsonEncode(body), 200);
          }),
          key: key,
        ).listModels();
        expect(seen.url.toString(), 'http://localhost:11434/v1/models');
        expect(seen.headers.containsKey('authorization'), key.isNotEmpty);
        return models;
      }

      final openRouter = await list({
        'data': [
          {'id': 'vendor/model-a', 'name': 'Vendor: Model A'},
          {
            'id': 'mistral-embed',
            'capabilities': {'completion_chat': false},
          },
        ],
      }, key: 'or-key');
      expect(openRouter.single.id, 'vendor/model-a');
      expect(openRouter.single.label, 'Vendor: Model A');

      final together = await list([
        {'id': 't/chat-model', 'display_name': 'Chat Model', 'type': 'chat'},
        {'id': 't/embedder', 'type': 'embedding'},
      ]);
      expect(together.map((m) => m.id), ['t/chat-model']);

      final ollama = await list({
        'models': [
          {'name': 'llama3:latest', 'model': 'llama3:latest'},
        ],
      });
      expect(ollama.single.id, 'llama3:latest');
      expect(ollama.single.displayName, isNull);
    });

    test('Gemini: key in a header, text models only, every page', () async {
      final seen = <http.Request>[];
      final ai = clientFor(
        const AiProviderConfig(kind: AiProviderKind.gemini, model: ''),
        MockClient((req) async {
          seen.add(req);
          return http.Response(
            jsonEncode(
              req.url.queryParameters['pageToken'] == null
                  ? {
                      'models': [
                        {
                          'name': 'models/gemini-x',
                          'displayName': 'Gemini X',
                          'supportedGenerationMethods': ['generateContent', 'countTokens'],
                        },
                        {
                          'name': 'models/text-embedder',
                          'supportedGenerationMethods': ['embedContent'],
                        },
                      ],
                      'nextPageToken': 'page-2',
                    }
                  : {
                      'models': [
                        {
                          'name': 'models/gemini-y',
                          'supportedGenerationMethods': ['generateContent'],
                        },
                      ],
                    },
            ),
            200,
          );
        }),
        key: 'g-key',
      );
      final models = await ai.listModels();
      expect(models.map((m) => m.id), ['gemini-x', 'gemini-y']);
      expect(models.first.label, 'Gemini X');
      expect(seen, hasLength(2));
      expect(seen.first.url.path, '/v1beta/models');
      expect(seen.first.url.queryParameters, {'pageSize': '1000'});
      expect(seen.last.url.queryParameters['pageToken'], 'page-2');
      expect(seen.every((r) => r.headers['x-goog-api-key'] == 'g-key'), isTrue);
      expect(
        seen.any((r) => r.url.queryParameters.containsKey('key')),
        isFalse,
        reason: 'the key never goes in the URL',
      );
    });

    test('errors map to clear kinds', () async {
      Future<AiException> failure(AiProviderKind kind, http.Response Function() respond) async {
        final ai = clientFor(
          AiProviderConfig(kind: kind, model: '', baseUrl: 'https://llm.example.test/v1'),
          MockClient((_) async => respond()),
        );
        try {
          await ai.listModels();
        } on AiException catch (e) {
          return e;
        }
        fail('expected an AiException');
      }

      final badKey = await failure(
        AiProviderKind.gemini,
        () => http.Response(
          jsonEncode({
            'error': {
              'code': 400,
              'status': 'INVALID_ARGUMENT',
              'details': [
                {'reason': 'API_KEY_INVALID'},
              ],
            },
          }),
          400,
        ),
      );
      expect(badKey.kind, AiErrorKind.auth, reason: 'Google answers a wrong key with 400');
      expect((await failure(AiProviderKind.openai, () => http.Response('', 401))).kind, AiErrorKind.auth);
      expect((await failure(AiProviderKind.openai, () => http.Response('', 429))).kind, AiErrorKind.rateLimited);
      final missing = await failure(AiProviderKind.anthropicCompatible, () => http.Response('not found', 404));
      expect((missing.kind, missing.status), (AiErrorKind.http, 404));
      expect(
        (await failure(AiProviderKind.openaiCompatible, () => http.Response('<html>', 200))).kind,
        AiErrorKind.badResponse,
      );
      expect(
        (await failure(AiProviderKind.openaiCompatible, () => http.Response('{"ok": true}', 200))).kind,
        AiErrorKind.badResponse,
      );
      final offline = clientFor(
        const AiProviderConfig(kind: AiProviderKind.openai, model: ''),
        MockClient((_) async => throw const SocketException('offline')),
      );
      expect(offline.listModels, throwsA(isA<AiException>().having((e) => e.kind, 'kind', AiErrorKind.network)));
    });

    test('settings ask with the typed key, or the saved key only for the same service', () async {
      final db = AppDatabase(DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true));
      addTearDown(db.close);
      final keys = MemoryKeyStore();
      final sent = <String?>[];
      final repo = AiSettingsRepository(
        db,
        keys,
        httpClient: MockClient((req) async {
          final key = req.headers['x-api-key'] ?? req.headers['authorization'];
          sent.add(key);
          if (req.url.host == 'needs-key.example.test' && key == null) return http.Response('', 401);
          return http.Response(
            jsonEncode({
              'data': [
                {'id': '${req.url.host}-model'},
              ],
              'has_more': false,
            }),
            200,
          );
        }),
      );
      const anthropic = AiProviderConfig(kind: AiProviderKind.anthropic, model: 'm');
      const openai = AiProviderConfig(kind: AiProviderKind.openai, model: '');

      expect(await repo.listModels(anthropic), isNull, reason: 'no key to ask with');
      expect(sent, isEmpty);

      await repo.save(anthropic, apiKey: 'sk-ant');
      expect((await repo.listModels(anthropic))!.single.id, 'api.anthropic.com-model');
      expect(sent.last, 'sk-ant');

      expect(await repo.listModels(openai), isNull, reason: 'the saved key belongs to another service');
      expect(sent, hasLength(1));

      expect((await repo.listModels(openai, apiKey: ' sk-oa '))!.single.id, 'api.openai.com-model');
      expect(sent.last, 'Bearer sk-oa');

      await repo.save(
        const AiProviderConfig(
          kind: AiProviderKind.openaiCompatible,
          model: 'm',
          baseUrl: 'https://one.example.test/v1',
        ),
        apiKey: 'sk-one',
      );
      const other = AiProviderConfig(
        kind: AiProviderKind.openaiCompatible,
        model: '',
        baseUrl: 'https://needs-key.example.test/v1',
      );
      expect(await repo.listModels(other), isNull, reason: 'a different address never gets the saved key');
      expect(sent.last, isNull);

      const local = AiProviderConfig(
        kind: AiProviderKind.openaiCompatible,
        model: '',
        baseUrl: 'http://localhost:11434/v1',
      );
      expect(
        (await repo.listModels(local))!.single.id,
        'localhost-model',
        reason: 'local servers are tried without a key',
      );
      expect(sent.where((k) => k == 'Bearer sk-one'), isEmpty);
    });
  });
}
