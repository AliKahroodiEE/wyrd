import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyrd/data/db/database.dart';
import 'package:wyrd/features/onboarding/onboarding_screen.dart';

import '../quests/quest_harness.dart';

/// The first quest is held to the same title limit as every other quest:
/// longer, the local database refuses it and onboarding cannot go on.
void main() {
  late AppDatabase db;

  setUp(() => db = memoryDatabase());

  final titleField = find.byType(TextField);
  final later = find.widgetWithText(OutlinedButton, "I'll do it later today");

  Future<List<QuestRow>> quests(WidgetTester tester) async =>
      (await tester.runAsync(() => db.select(db.quests).get()))!;

  /// Walks to the first-quest step: language, name, areas.
  Future<void> reachFirstQuest(WidgetTester tester) async {
    await pumpQuestPage(tester, db, const OnboardingScreen());
    await tester.tap(find.text('English'));
    await settle(tester);
    await tester.enterText(titleField, 'Arin');
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await settle(tester);
    await tester.tap(find.text('Skip'));
    await settle(tester);
    expect(find.text("I'll do it later today"), findsOneWidget);
  }

  testWidgets('the first quest title stops at 200', (tester) async {
    await reachFirstQuest(tester);
    await tester.enterText(titleField, 'a' * 250);
    await tester.pump();
    expect(tester.widget<TextField>(titleField).controller!.text, 'a' * 200);
    expect(find.text('200/200'), findsOneWidget);

    await tapVisible(tester, later);
    expect(find.text('How growth works'), findsOneWidget);
    expect((await quests(tester)).single.title, 'a' * 200);
    await closeDatabase(tester, db);
  });

  testWidgets(
    'one still being composed past the limit says so and is not sworn',
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    (tester) async {
      await reachFirstQuest(tester);
      await tester.showKeyboard(titleField);
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: 'a' * 250,
          selection: const TextSelection.collapsed(offset: 250),
          composing: const TextRange(start: 0, end: 250),
        ),
      );
      await tester.pump();
      expect(find.text('Too long. Keep it to 200 characters.'), findsOneWidget);
      expect(tester.widget<OutlinedButton>(later).onPressed, isNull);
      expect(await quests(tester), isEmpty);
      await closeDatabase(tester, db);
    },
  );
}
