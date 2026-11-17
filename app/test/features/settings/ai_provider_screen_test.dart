import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wyrd/app/providers.dart';
import 'package:wyrd/data/ai/ai_client.dart';
import 'package:wyrd/data/ai/ai_settings_repository.dart';
import 'package:wyrd/data/db/database.dart';
import 'package:wyrd/features/settings/ai_provider_screen.dart';

import '../auth/fake_auth_gateway.dart';

http.Response _models(List<Map<String, Object?>> data) =>
    http.Response(jsonEncode({'data': data, 'has_more': false}), 200);

const _claude = [
  {'id': 'claude-opus-5-5', 'display_name': 'Claude Opus 5.5'},
  {'id': 'claude-sonnet-x', 'display_name': 'Claude Sonnet X'},
];

void main() {
  late AppDatabase db;
  late MemoryKeyStore keys;
  late List<http.Request> requests;

  setUp(() {
    db = AppDatabase(DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true));
    keys = MemoryKeyStore();
    requests = [];
  });
  tearDown(() => db.close());

  AiSettingsRepository repo(http.Response Function(http.Request) respond) => AiSettingsRepository(
    db,
    keys,
    httpClient: MockClient((req) async {
      requests.add(req);
      return respond(req);
    }),
  );

  Future<void> pump(
    WidgetTester tester,
    http.Response Function(http.Request) respond, {
    Locale locale = const Locale('en'),
  }) => pumpPage(
    tester,
    const AiProviderScreen(),
    locale: locale,
    overrides: [aiSettingsRepositoryProvider.overrideWithValue(repo(respond))],
  );

  Future<void> saveAnthropic({String model = 'claude-opus-5-5'}) => AiSettingsRepository(db, keys).save(
    AiProviderConfig(kind: AiProviderKind.anthropic, model: model),
    apiKey: 'sk-saved',
  );

  String modelText(WidgetTester tester) =>
      tester.widget<TextField>(find.widgetWithText(TextField, 'Model')).controller!.text;

  /// Leaves the address field the way the keyboard's Done key does.
  Future<void> finishAddress(WidgetTester tester) async {
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
  }

  Future<void> chooseProvider(WidgetTester tester, String label) async {
    await tester.tap(find.byType(DropdownButtonFormField<AiProviderKind>));
    await settle(tester);
    await tester.tap(find.text(label).last);
    await settle(tester);
  }

  const compatible = 'OpenAI-compatible service (OpenRouter, Groq, Ollama…)';

  testWidgets("the saved provider's models load on open and one tap picks a model", (tester) async {
    await saveAnthropic();
    await pump(tester, (_) => _models(_claude));

    expect(requests.single.url.toString(), 'https://api.anthropic.com/v1/models?limit=1000');
    expect(requests.single.headers['x-api-key'], 'sk-saved');
    expect(find.text('2 models available — choose one from the list, or type a name.'), findsOneWidget);

    await tester.tap(find.byTooltip('Choose a model'));
    await settle(tester);
    expect(find.text('Claude Opus 5.5'), findsOneWidget);
    expect(find.text('claude-sonnet-x'), findsOneWidget, reason: 'the id shows under the display name');

    await tester.enterText(find.widgetWithText(TextField, 'Search models'), 'sonnet');
    await settle(tester);
    expect(find.text('Claude Opus 5.5'), findsNothing);

    await tester.tap(find.text('Claude Sonnet X'));
    await settle(tester);
    expect(modelText(tester), 'claude-sonnet-x');
    expect(find.text('Search models'), findsNothing, reason: 'the list closes after a choice');
  });

  testWidgets('another provider waits for its own key and never gets the saved one', (tester) async {
    await saveAnthropic();
    await pump(
      tester,
      (req) => req.url.host == 'api.openai.com'
          ? _models([
              {'id': 'gpt-x', 'created': 1790000000},
              {'id': 'gpt-y', 'created': 1780000000},
              {'id': 'gpt-z', 'created': 1770000000},
            ])
          : _models(_claude),
    );

    await tester.tap(find.byType(DropdownButtonFormField<AiProviderKind>));
    await settle(tester);
    await tester.tap(find.text('OpenAI').last);
    await settle(tester);
    expect(find.text("Enter your API key to see this provider's models."), findsOneWidget);
    expect(requests.where((r) => r.url.host == 'api.openai.com'), isEmpty);

    await tester.enterText(find.widgetWithText(TextField, 'API key'), 'sk-openai');
    await tester.pump(const Duration(seconds: 1));
    await settle(tester);
    final openai = requests.where((r) => r.url.host == 'api.openai.com').toList();
    expect(openai, hasLength(1));
    expect(openai.single.headers['authorization'], 'Bearer sk-openai');
    expect(find.text('3 models available — choose one from the list, or type a name.'), findsOneWidget);
  });

  testWidgets('a custom address without a model list points at the address, and typing still works', (tester) async {
    await pump(tester, (_) => http.Response('not found', 404));

    await tester.tap(find.byType(DropdownButtonFormField<AiProviderKind>));
    await settle(tester);
    await tester.tap(find.text('OpenAI-compatible service (OpenRouter, Groq, Ollama…)').last);
    await settle(tester);
    expect(requests, isEmpty, reason: 'nothing to ask until there is an address');

    await tester.enterText(find.widgetWithText(TextField, 'API base URL'), 'https://llm.example.test/v1');
    await tester.pump(const Duration(seconds: 1));
    expect(requests, isEmpty, reason: 'nothing is asked while the address is being typed');
    await finishAddress(tester);
    expect(requests.single.url.toString(), 'https://llm.example.test/v1/models');
    expect(
      find.text("No model list at this address. Check the API base URL, or type the model's name."),
      findsOneWidget,
    );
    expect(find.byTooltip('Load the list again'), findsNothing, reason: 'reloading will not help');

    await tester.enterText(find.widgetWithText(TextField, 'Model'), 'my-model');
    await settle(tester);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save')).onPressed, isNotNull);
  });

  testWidgets("a name the provider doesn't list is flagged, and a failure can be retried", (tester) async {
    await saveAnthropic(model: 'claude-typo');
    var fail = true;
    await pump(tester, (_) => fail ? http.Response('', 500) : _models(_claude));
    expect(
      find.text("Couldn't load the model list: the provider returned an error (500). You can still type the name."),
      findsOneWidget,
    );

    fail = false;
    await tester.tap(find.byTooltip('Load the list again'));
    await settle(tester);
    expect(find.text("This name isn't in the provider's list. Check it, or choose one from the list."), findsOneWidget);
  });

  testWidgets('Persian: the count uses Persian digits and the list opens in RTL', (tester) async {
    await saveAnthropic();
    await pump(tester, (_) => _models(_claude), locale: const Locale('fa'));
    expect(find.textContaining('۲ مدل'), findsOneWidget);

    await tester.tap(find.byTooltip('انتخاب مدل'));
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Claude Sonnet X'), findsOneWidget);
  });

  testWidgets('a typed key only ever goes to the address it was typed for', (tester) async {
    await pump(
      tester,
      (req) => _models([
        {'id': '${req.url.host}-model'},
      ]),
    );
    await chooseProvider(tester, compatible);
    await tester.enterText(find.widgetWithText(TextField, 'API base URL'), 'https://openrouter.ai/api/v1');
    await finishAddress(tester);
    await tester.enterText(find.widgetWithText(TextField, 'API key'), 'sk-or');
    await tester.pump(const Duration(seconds: 1));
    await settle(tester);
    expect(requests.last.url.host, 'openrouter.ai');
    expect(requests.last.headers['authorization'], 'Bearer sk-or');

    // Retype the address character by character, pausing as a slow typist would.
    const next = 'https://api.groq.com/openai/v1';
    final before = requests.length;
    for (var i = 8; i <= next.length; i++) {
      await tester.enterText(find.widgetWithText(TextField, 'API base URL'), next.substring(0, i));
      await tester.pump(const Duration(seconds: 1));
    }
    expect(requests.length, before, reason: 'no request while the address is half-typed');
    await finishAddress(tester);

    final elsewhere = requests.where((r) => r.url.host != 'openrouter.ai').toList();
    expect(elsewhere.single.url.toString(), 'https://api.groq.com/openai/v1/models');
    expect(
      elsewhere.single.headers.containsKey('authorization'),
      isFalse,
      reason: "the OpenRouter key stays with OpenRouter",
    );
    expect(tester.widget<TextField>(find.widgetWithText(TextField, 'API key')).controller!.text, isEmpty);
  });

  testWidgets('editing the path of the same address keeps the typed key', (tester) async {
    await pump(tester, (_) => _models(_claude));
    await chooseProvider(tester, compatible);
    await tester.enterText(find.widgetWithText(TextField, 'API base URL'), 'https://llm.example.test');
    await finishAddress(tester);
    await tester.enterText(find.widgetWithText(TextField, 'API key'), 'sk-same');
    await tester.pump(const Duration(seconds: 1));
    await settle(tester);
    await tester.enterText(find.widgetWithText(TextField, 'API base URL'), 'https://llm.example.test/v1');
    await finishAddress(tester);
    expect(requests.last.url.toString(), 'https://llm.example.test/v1/models');
    expect(requests.last.headers['authorization'], 'Bearer sk-same');
  });

  testWidgets("after a switch, saving doesn't pair the old key with the new provider", (tester) async {
    await saveAnthropic();
    await pump(tester, (req) => req.headers['authorization'] == null ? http.Response('', 401) : _models(_claude));
    expect(find.text('A key is saved on this device. Leave this empty to keep it.'), findsOneWidget);

    await chooseProvider(tester, compatible);
    expect(find.text('A key is saved on this device. Leave this empty to keep it.'), findsNothing);
    await tester.enterText(find.widgetWithText(TextField, 'API base URL'), 'https://llm.example.test/v1');
    await finishAddress(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Model'), 'some-model');
    await settle(tester);

    await tester.tap(find.text('Test connection'));
    await settle(tester);
    expect(keys.value, isNull, reason: "the Anthropic key isn't kept for another service");
    expect(requests.where((r) => r.headers.values.any((v) => v.contains('sk-saved'))), hasLength(1));
    expect(
      requests.where((r) => r.url.host == 'llm.example.test').every((r) => r.headers['authorization'] == null),
      isTrue,
    );
    expect(find.text("Couldn't connect: there's no API key for this provider yet"), findsOneWidget);
  });

  testWidgets("a late answer for the previous provider doesn't overwrite the new one", (tester) async {
    await saveAnthropic();
    final slow = Completer<http.Response>();
    await pumpPage(
      tester,
      const AiProviderScreen(),
      overrides: [
        aiSettingsRepositoryProvider.overrideWithValue(
          AiSettingsRepository(
            db,
            keys,
            httpClient: MockClient((req) {
              requests.add(req);
              return slow.future;
            }),
          ),
        ),
      ],
    );
    expect(find.text("Loading the provider's models…"), findsOneWidget);
    await chooseProvider(tester, 'OpenAI');
    expect(find.text("Enter your API key to see this provider's models."), findsOneWidget);

    slow.complete(_models(_claude));
    await settle(tester);
    expect(find.text("Enter your API key to see this provider's models."), findsOneWidget);
    expect(find.byTooltip('Choose a model'), findsNothing);
  });

  testWidgets('ids with a models/ prefix match the name in the field', (tester) async {
    await AiSettingsRepository(db, keys).save(
      const AiProviderConfig(
        kind: AiProviderKind.openaiCompatible,
        model: 'gemini-x',
        baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
      ),
      apiKey: 'g-key',
    );
    await pump(
      tester,
      (_) => _models([
        {'id': 'models/gemini-x'},
        {'id': 'models/gemini-y'},
      ]),
    );
    expect(find.text('2 models available — choose one from the list, or type a name.'), findsOneWidget);
    await tester.tap(find.byTooltip('Choose a model'));
    await settle(tester);
    final tile = tester.widget<ListTile>(
      find.ancestor(of: find.text('models/gemini-x'), matching: find.byType(ListTile)),
    );
    expect(tile.selected, isTrue);
  });

  testWidgets('a key pasted before the address never reaches a half-typed host when focus leaves by itself', (
    tester,
  ) async {
    await pump(tester, (_) => _models(_claude));
    await chooseProvider(tester, compatible);
    await tester.enterText(find.widgetWithText(TextField, 'API key'), 'sk-early');
    await tester.pump(const Duration(seconds: 1));
    await tester.enterText(find.widgetWithText(TextField, 'API base URL'), 'https://api.deepseek.co');
    await settle(tester);

    // Opening the provider menu takes focus from the half-typed address.
    await tester.tap(find.byType(DropdownButtonFormField<AiProviderKind>));
    await settle(tester);
    expect(requests, isEmpty);
    await tester.tap(find.text(compatible).last);
    await settle(tester);
    expect(requests, isEmpty, reason: 'nothing is asked until the user leaves the field');
  });

  testWidgets('editing the address drops the old list and ignores a late reply for it', (tester) async {
    await AiSettingsRepository(db, keys).save(
      const AiProviderConfig(kind: AiProviderKind.openaiCompatible, model: 'm', baseUrl: 'https://old.example.test/v1'),
      apiKey: 'sk-old',
    );
    final slow = Completer<http.Response>();
    await pumpPage(
      tester,
      const AiProviderScreen(),
      overrides: [
        aiSettingsRepositoryProvider.overrideWithValue(
          AiSettingsRepository(
            db,
            keys,
            httpClient: MockClient((req) {
              requests.add(req);
              return slow.future;
            }),
          ),
        ),
      ],
    );
    await tester.enterText(find.widgetWithText(TextField, 'API base URL'), 'https://new.example.test/v1');
    await settle(tester);
    slow.complete(_models(_claude));
    await settle(tester);
    expect(find.byTooltip('Choose a model'), findsNothing, reason: "the old address's list no longer applies");
    expect(find.text('The model name exactly as your provider lists it'), findsOneWidget);
  });

  testWidgets('Save and Test wait for a complete address', (tester) async {
    await pump(tester, (_) => _models(_claude));
    await chooseProvider(tester, compatible);
    await tester.enterText(find.widgetWithText(TextField, 'API base URL'), 'https//api.example.test/v1');
    await tester.enterText(find.widgetWithText(TextField, 'Model'), 'm');
    await settle(tester);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save')).onPressed, isNull);
    await tester.enterText(find.widgetWithText(TextField, 'API base URL'), 'https://api.example.test/v1');
    await settle(tester);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save')).onPressed, isNotNull);
  });
}
