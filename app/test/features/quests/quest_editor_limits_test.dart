import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyrd/data/db/database.dart';
import 'package:wyrd/data/models.dart';
import 'package:wyrd/data/repositories/quest_repository.dart';
import 'package:wyrd/features/quests/quest_editor_screen.dart';
import 'package:wyrd_engine/wyrd_engine.dart';

import 'quest_harness.dart';

/// The editor only saves what both stores take: the server's CHECKs in
/// core_schema.sql and the local title length. A value the server refuses
/// keeps the quest, and everything done with it, off every other device; a
/// title the local database refuses is not saved at all.
void main() {
  late AppDatabase db;

  setUp(() => db = memoryDatabase());

  const title = 'What will you do?';
  const intention = 'When and where will you do it?';
  const estimate = 'Estimated minutes';
  const estimateError = 'Enter whole minutes from 1 to 1,440.';

  Future<List<QuestRow>> quests(WidgetTester tester) async =>
      (await tester.runAsync(() => db.select(db.quests).get()))!;

  Future<Quest> seed(WidgetTester tester, QuestDraft draft) async =>
      (await tester.runAsync(() => QuestRepository(db).create(draft)))!;

  testWidgets('folded options cannot take the focus', (tester) async {
    await pumpQuestPage(tester, db, const QuestEditorScreen());
    final folded = tester.widget<ExcludeFocus>(
      find
          .ancestor(
            of: find.byType(TextFormField, skipOffstage: false).last,
            matching: find.byType(ExcludeFocus, skipOffstage: false),
          )
          .first,
    );
    expect(folded.excluding, isTrue, reason: 'Tab and an open keyboard must not land on invisible fields');

    await tapVisible(tester, find.text('More options'));
    final open = tester.widget<ExcludeFocus>(
      find.ancestor(of: field(estimate), matching: find.byType(ExcludeFocus)).first,
    );
    expect(open.excluding, isFalse);
  });

  testWidgets('estimated minutes take whole minutes from 1 to 1440 only', (tester) async {
    await pumpQuestPage(tester, db, const QuestEditorScreen());
    await tester.enterText(field(title), 'Study electronics');
    await tapVisible(tester, find.text('More options'));
    // "90-120" and "1.5" used to be read digit by digit, as 90120 and 15.
    for (final refused in ['0', '2000', '90-120', '1.5', 'an hour']) {
      await tester.enterText(field(estimate), refused);
      await tester.pump();
      expect(find.text(estimateError), findsOneWidget, reason: refused);
      await tapVisible(tester, find.text('Swear quest'));
      expect(find.text('quests page'), findsNothing, reason: refused);
    }
    expect(await quests(tester), isEmpty);

    await tester.enterText(field(estimate), '۹۰');
    await settle(tester);
    expect(find.text(estimateError), findsNothing);
    await tapVisible(tester, find.text('Swear quest'));
    expect(find.text('quests page'), findsOneWidget);
    expect((await quests(tester)).single.estimatedMinutes, 90);
    await closeDatabase(tester, db);
  });

  testWidgets('a refused estimate folded away in More options stops the save and is shown', (tester) async {
    await pumpQuestPage(tester, db, const QuestEditorScreen());
    await tester.enterText(field(title), 'Study electronics');
    await tapVisible(tester, find.text('More options'));
    await tester.enterText(field(estimate), '0');
    await tapVisible(tester, find.text('More options'));
    expect(field(estimate), findsNothing, reason: 'folded away');

    await tapVisible(tester, find.text('Swear quest'));
    expect(find.text('quests page'), findsNothing);
    expect(field(estimate), findsOneWidget, reason: 'unfolded to show why');
    expect(find.text(estimateError), findsOneWidget);
    expect(await quests(tester), isEmpty);
    await closeDatabase(tester, db);
  });

  testWidgets('the title stops at 200 as stored, so an emoji title still saves', (tester) async {
    await pumpQuestPage(tester, db, const QuestEditorScreen());
    // 150 characters on screen, but 600 UTF-16 units: the local database
    // allows 200 and refused the whole quest.
    await tester.enterText(field(title), '👍🏽' * 150);
    await tester.pump();
    expect(fieldText(tester, title), '👍🏽' * 50);
    expect(find.text('200/200'), findsOneWidget);

    await tapVisible(tester, find.text('Swear quest'));
    expect(find.text('quests page'), findsOneWidget);
    expect((await quests(tester)).single.title, '👍🏽' * 50);
    await closeDatabase(tester, db);
  });

  testWidgets('the intention stops at 280 as the server counts', (tester) async {
    await pumpQuestPage(tester, db, const QuestEditorScreen());
    await tester.enterText(field(title), 'مطالعه');
    // Each ZWNJ counts for the server without being a character on screen,
    // so 280 on screen would be 315 for the server.
    await tester.enterText(field(intention), 'می‌خواهم ' * 40);
    await tester.pump();
    expect(fieldText(tester, intention).length, 280);
    expect(find.text('280/280'), findsOneWidget);

    await tapVisible(tester, find.text('Swear quest'));
    expect(find.text('quests page'), findsOneWidget);
    expect((await quests(tester)).single.intention!.runes.length, lessThanOrEqualTo(280));
    await closeDatabase(tester, db);
  });

  testWidgets('notes stop at 2000, well within what the server takes', (tester) async {
    await pumpQuestPage(tester, db, const QuestEditorScreen());
    await tapVisible(tester, find.text('More options'));
    // 600 family emoji are 4200 code points, over the server's 4000.
    await tester.enterText(field('Notes'), '👨‍👩‍👧‍👦' * 600);
    await tester.pump();
    expect(fieldText(tester, 'Notes'), '👨‍👩‍👧‍👦' * 181, reason: 'whole emoji only, 11 units each');
    await closeDatabase(tester, db);
  });

  testWidgets('a quest saved with values the server refuses says so when opened', (tester) async {
    final quest = await seed(
      tester,
      QuestDraft(title: 'Study electronics', estimatedMinutes: 2000, intention: 'x' * 300),
    );
    await pumpQuestPage(tester, db, QuestEditorScreen(questId: quest.id));
    expect(find.text('Too long. Keep it to 280 characters.'), findsOneWidget);
    expect(find.text('300/280'), findsOneWidget);
    expect(find.text(estimateError), findsOneWidget);

    await tapVisible(tester, find.text('Save changes'));
    expect(find.text('quests page'), findsNothing);
    expect((await quests(tester)).single.estimatedMinutes, 2000, reason: 'nothing saved');

    // Shortening works even over the limit.
    await tester.enterText(field(intention), 'x' * 280);
    await tester.enterText(field(estimate), '120');
    await settle(tester);
    expect(find.text('Too long. Keep it to 280 characters.'), findsNothing);
    await tapVisible(tester, find.text('Save changes'));
    expect(find.text('quests page'), findsOneWidget);
    final saved = (await quests(tester)).single;
    expect(saved.intention, 'x' * 280);
    expect(saved.estimatedMinutes, 120);
    await closeDatabase(tester, db);
  });

  testWidgets('a cleared title is caught even after it scrolled out of view', (tester) async {
    final quest = await seed(tester, const QuestDraft(title: 'Write the report', tier: QuestTier.contract));
    await pumpQuestPage(tester, db, QuestEditorScreen(questId: quest.id), size: const Size(440, 640));
    await tester.enterText(field(title), '');
    // Moving on to the notes takes the focus, and the screen, away from the title.
    await tester.enterText(field('Notes'), 'Draft first');
    await tester.scrollUntilVisible(find.text('Save changes'), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Save changes'));
    await settle(tester);

    expect(find.text('quests page'), findsNothing);
    expect((await quests(tester)).single.title, 'Write the report');
    expect(find.text('Give the quest a name.'), findsOneWidget);
    final shown = tester.getRect(field(title));
    expect(shown.top, greaterThanOrEqualTo(0), reason: 'scrolled back into view');
    expect(shown.bottom, lessThanOrEqualTo(640));
    await closeDatabase(tester, db);
  });

  group('steps', () {
    final stepField = find.widgetWithText(TextField, 'Next step');

    Future<List<SubtaskRow>> steps(WidgetTester tester) async =>
        (await tester.runAsync(() => db.select(db.subtasks).get()))!;

    Future<void> openContract(WidgetTester tester) async {
      final quest = await seed(tester, const QuestDraft(title: 'Write the report', tier: QuestTier.contract));
      await pumpQuestPage(tester, db, QuestEditorScreen(questId: quest.id));
    }

    testWidgets('stop at 200, with the count shown near the limit', (tester) async {
      await openContract(tester);
      await tester.enterText(stepField, 'a' * 100);
      await tester.pump();
      expect(find.text('100/200'), findsNothing, reason: 'quiet while short');

      await tester.enterText(stepField, 'a' * 250);
      await tester.pump();
      expect(find.text('200/200'), findsOneWidget);
      await tapVisible(tester, find.byTooltip('Add step'));
      expect((await steps(tester)).single.title, 'a' * 200);
      await closeDatabase(tester, db);
    });

    testWidgets(
      'one still being composed past the limit is kept, not added',
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
      (tester) async {
        await openContract(tester);
        // On iOS an input method may run past the limit until it commits.
        await tester.showKeyboard(stepField);
        tester.testTextInput.updateEditingValue(
          TextEditingValue(
            text: 'a' * 250,
            selection: const TextSelection.collapsed(offset: 250),
            composing: const TextRange(start: 0, end: 250),
          ),
        );
        await tester.pump();
        await tapVisible(tester, find.byTooltip('Add step'));

        expect(find.text('Too long. Keep it to 200 characters.'), findsOneWidget);
        expect(tester.widget<TextField>(stepField).controller!.text, 'a' * 250, reason: 'nothing typed is lost');
        expect(await steps(tester), isEmpty);
        await closeDatabase(tester, db);
      },
    );
  });
}
