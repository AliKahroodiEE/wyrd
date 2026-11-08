import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyrd/data/db/database.dart';
import 'package:wyrd/data/models.dart';
import 'package:wyrd/data/repositories/quest_repository.dart';
import 'package:wyrd/features/quests/complete_flow.dart';
import 'package:wyrd/features/quests/quest_timer.dart';

import 'quest_harness.dart';

/// A button that completes [quest] the way the quest list does.
class _Complete extends ConsumerWidget {
  const _Complete(this.quest);

  final Quest quest;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    body: Center(
      child: TextButton(onPressed: () => completeQuest(context, ref, quest), child: const Text('complete')),
    ),
  );
}

/// A completion's minutes must be what the server takes (0 to 1440,
/// core_schema.sql), or the completion never syncs.
void main() {
  late AppDatabase db;

  setUp(() => db = memoryDatabase());

  const minutes = 'How many minutes did it take?';

  /// The answer field, as a TextField whether or not it sits in a form.
  Finder answer(String label) => find.widgetWithText(TextField, label);

  Future<Quest> seed(WidgetTester tester, QuestDraft draft) async =>
      (await tester.runAsync(() => QuestRepository(db).create(draft)))!;

  Future<List<CompletionRow>> completions(WidgetTester tester) async =>
      (await tester.runAsync(() => db.select(db.completions).get()))!;

  testWidgets('declared minutes take whole minutes up to a day', (tester) async {
    final quest = await seed(tester, const QuestDraft(title: 'Study electronics'));
    await pumpQuestPage(tester, db, _Complete(quest));
    await tester.tap(find.text('complete'));
    await settle(tester);

    // "90-120" used to become 90120, then quietly 960.
    for (final refused in ['90-120', '2000', '1.5']) {
      await tester.enterText(answer(minutes), refused);
      await tester.tap(find.text('Seal'));
      await settle(tester);
      expect(find.text('Enter whole minutes, up to 1,440.'), findsOneWidget, reason: refused);
    }
    expect(await completions(tester), isEmpty);

    await tester.enterText(answer(minutes), '90');
    await tester.tap(find.text('Seal'));
    await settle(tester);
    expect(find.text('Deed recorded'), findsOneWidget);
    expect((await completions(tester)).single.declaredMinutes, 90);
    await closeDatabase(tester, db);
  });

  testWidgets('says so in Persian, with Persian digits', (tester) async {
    final quest = await seed(tester, const QuestDraft(title: 'مطالعه'));
    await pumpQuestPage(tester, db, _Complete(quest), locale: const Locale('fa'));
    await tester.tap(find.text('complete'));
    await settle(tester);
    await tester.enterText(answer('چند دقیقه طول کشید؟'), '۲۰۰۰');
    await tester.tap(find.text('مُهر کن'));
    await settle(tester);
    expect(find.text('یک عدد صحیح تا سقف ۱٬۴۴۰ دقیقه بنویس.'), findsOneWidget);
    expect(await completions(tester), isEmpty);
    await closeDatabase(tester, db);
  });

  testWidgets('a planned estimate the server refuses is not offered as the answer', (tester) async {
    final quest = await seed(tester, const QuestDraft(title: 'Study electronics', estimatedMinutes: 2000));
    await pumpQuestPage(tester, db, _Complete(quest));
    await tester.tap(find.text('complete'));
    await settle(tester);
    expect(tester.widget<TextField>(answer(minutes)).controller!.text, isEmpty);
    await closeDatabase(tester, db);
  });

  testWidgets('a timer left running for more than a day records a day', (tester) async {
    var now = DateTime(2026, 11, 4, 8);
    final quest = await seed(tester, const QuestDraft(title: 'Study electronics'));
    await pumpQuestPage(
      tester,
      db,
      _Complete(quest),
      overrides: [questTimerProvider.overrideWith(() => QuestTimers(clock: () => now))],
    );
    ProviderScope.containerOf(tester.element(find.byType(_Complete))).read(questTimerProvider.notifier).start(quest.id);
    now = now.add(const Duration(hours: 30));

    await tester.tap(find.text('complete'));
    await settle(tester);
    expect(answer(minutes), findsNothing, reason: 'the timer answers for itself');
    expect(find.text('Deed recorded'), findsOneWidget);
    expect((await completions(tester)).single.trackedMinutes, 1440);
    await closeDatabase(tester, db);
  });
}
