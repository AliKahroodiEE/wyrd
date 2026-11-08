import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyrd/features/quests/quest_timer.dart';

void main() {
  test('a timer counts whole minutes, at least one, and stops counting at a day', () {
    var now = DateTime(2026, 11, 4, 8);
    final container = ProviderContainer(
      overrides: [questTimerProvider.overrideWith(() => QuestTimers(clock: () => now))],
    );
    addTearDown(container.dispose);
    final timers = container.read(questTimerProvider.notifier);

    timers.start('q');
    now = now.add(const Duration(minutes: 95, seconds: 40));
    expect(timers.stop('q'), 95);

    timers.start('q');
    now = now.add(const Duration(seconds: 20));
    expect(timers.stop('q'), 1);

    // Completions hold at most 1440 tracked minutes; more never syncs.
    timers.start('q');
    now = now.add(const Duration(hours: 30));
    expect(timers.stop('q'), 1440);
    expect(timers.stop('q'), isNull, reason: 'stopped already');
  });
}
