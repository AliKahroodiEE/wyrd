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

  testWidgets("a service without a model list says so, and typing still works", (tester) async {
    await pump(tester, (_) => http.Response('not found', 404));

    await tester.tap(find.byType(DropdownButtonFormField<AiProviderKind>));
    await settle(tester);
    await tester.tap(find.text('OpenAI-compatible service (OpenRouter, Groq, Ollama…)').last);
    await settle(tester);
    expect(requests, isEmpty, reason: 'nothing to ask until there is an address');

    await tester.enterText(find.widgetWithText(TextField, 'API base URL'), 'https://llm.example.test/v1');
    await tester.pump(const Duration(seconds: 1));
    await settle(tester);
    expect(requests.single.url.toString(), 'https://llm.example.test/v1/models');
    expect(find.text("This service doesn't share a model list, so type the model's name."), findsOneWidget);
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
}
