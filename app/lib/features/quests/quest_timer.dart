import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'quest_limits.dart';

/// Optional time tracking (Q6): one running timer per quest. Stopping
/// returns elapsed whole minutes (at least 1, at most the day a completion
/// can hold), which the engine treats as the strongest evidence of effort.
class QuestTimers extends Notifier<Map<String, DateTime>> {
  QuestTimers({DateTime Function()? clock}) : _now = clock ?? DateTime.now;

  final DateTime Function() _now;

  @override
  Map<String, DateTime> build() => const {};

  void start(String questId) => state = {...state, questId: _now()};

  int? stop(String questId) {
    final started = state[questId];
    if (started == null) return null;
    state = Map.of(state)..remove(questId);
    return _now().difference(started).inMinutes.clamp(1, QuestLimits.minutesMax);
  }

  void cancel(String questId) => state = Map.of(state)..remove(questId);
}

final questTimerProvider = NotifierProvider<QuestTimers, Map<String, DateTime>>(QuestTimers.new);
