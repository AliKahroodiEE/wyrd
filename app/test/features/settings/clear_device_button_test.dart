import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;
import 'package:wyrd/app/providers.dart';
import 'package:wyrd/data/ai/ai_settings_repository.dart';
import 'package:wyrd/data/db/database.dart';
import 'package:wyrd/data/remote/backend.dart';
import 'package:wyrd/data/repositories/data_repository.dart';
import 'package:wyrd/features/auth/auth_gateway.dart';
import 'package:wyrd/features/settings/clear_device_button.dart';

import '../auth/fake_auth_gateway.dart';

/// Remembers whether the device copy was wiped.
class _FakeData implements DataRepository {
  bool wiped = false;

  @override
  Future<void> wipe() async => wiped = true;

  @override
  Future<Map<String, Object?>> exportAll() async => const {};
}

const _user = User(
  id: '00000000-0000-4000-8000-00000000000a',
  appMetadata: {},
  userMetadata: {},
  aud: 'authenticated',
  email: 'arin@example.test',
  createdAt: '2026-11-04T00:00:00Z',
);

void main() {
  late AppDatabase db;
  late MemoryKeyStore keys;

  setUp(() {
    db = AppDatabase(DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true));
    keys = MemoryKeyStore()..value = 'sk-users-own-key';
  });
  tearDown(() => db.close());

  Future<(FakeAuthGateway, _FakeData)> pump(WidgetTester tester, {required bool signedIn}) async {
    final gateway = FakeAuthGateway();
    final data = _FakeData();
    await pumpPage(
      tester,
      const Scaffold(body: Center(child: ClearDeviceButton())),
      overrides: [
        authGatewayProvider.overrideWithValue(gateway),
        dataRepositoryProvider.overrideWithValue(data),
        aiSettingsRepositoryProvider.overrideWithValue(AiSettingsRepository(db, keys)),
        currentUserProvider.overrideWith((ref) => Stream.value(signedIn ? _user : null)),
      ],
    );
    return (gateway, data);
  }

  testWidgets('guests delete the data on this device, which is all there is', (tester) async {
    final (gateway, data) = await pump(tester, signedIn: false);
    await tester.tap(find.text('Delete all data'));
    await settle(tester);
    expect(find.textContaining('from this device.'), findsOneWidget);
    expect(find.textContaining('servers'), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await settle(tester);
    expect(gateway.calls, isEmpty);
    expect(data.wiped, isTrue);
    expect(keys.value, isNull, reason: 'the AI key goes too');
    expect(find.text('onboarding page'), findsOneWidget);
  });

  testWidgets('signed in: signs out first, then clears the device', (tester) async {
    final (gateway, data) = await pump(tester, signedIn: true);
    expect(find.text('Delete all data'), findsNothing);
    await tester.tap(find.text('Sign out and clear this device'));
    await settle(tester);
    expect(find.textContaining('stays in your account'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
    await settle(tester);
    expect(gateway.calls, ['signOut']);
    expect(data.wiped, isTrue);
    expect(keys.value, isNull, reason: 'the next person cannot use the AI key');
    expect(find.text('onboarding page'), findsOneWidget);
    expect(find.text('Signed out. This device no longer holds your data.'), findsOneWidget);
  });

  testWidgets('signed in: a failed sign-out keeps the data', (tester) async {
    final (gateway, data) = await pump(tester, signedIn: true);
    gateway.failWith = StateError('network down');
    await tester.tap(find.text('Sign out and clear this device'));
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
    await settle(tester);
    expect(gateway.calls, ['signOut']);
    expect(data.wiped, isFalse);
    expect(keys.value, 'sk-users-own-key');
    expect(find.text('onboarding page'), findsNothing);
  });

  testWidgets('cancelling changes nothing', (tester) async {
    final (gateway, data) = await pump(tester, signedIn: true);
    await tester.tap(find.text('Sign out and clear this device'));
    await settle(tester);
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(gateway.calls, isEmpty);
    expect(data.wiped, isFalse);
  });
}
