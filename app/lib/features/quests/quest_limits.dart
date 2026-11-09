import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wyrd_engine/wyrd_engine.dart';

import '../../core/format/formatters.dart';
import '../../l10n/generated/app_localizations.dart';

/// What quests, steps and completions may hold. A value the server refuses
/// (the CHECK constraints in
/// `backend/supabase/migrations/20261104000100_core_schema.sql`) never
/// leaves this device, and a title the local database refuses (drift
/// `withLength`) is not saved at all; the inputs stop both before saving.
///
/// Text lengths are in UTF-16 code units, Dart's `String.length`: what the
/// local database counts, and never less than the code points the server's
/// `char_length` counts. Both can be more than the characters on screen,
/// which Flutter's `maxLength` counts: 👍🏽 is one character but four units,
/// and the ZWNJ in "می‌خواهم" is a unit of its own.
abstract final class QuestLimits {
  /// Quest and step titles (`quests_title_length`, `subtasks_title_length`,
  /// and `withLength(max: 200)` on both local tables).
  static const titleMax = 200;

  /// The "when and where" intention (`quests_intention_length`).
  static const intentionMax = 280;

  /// The editor's own limit for notes, well within the server's 4000
  /// (`quests_notes_length`).
  static const notesMax = 2000;

  /// The shortest estimate (`quests_estimated_minutes`).
  static const estimateMin = 1;

  /// A day: the most an estimate (`quests_estimated_minutes`), declared
  /// minutes (`completions_declared_minutes`) or a timer
  /// (`completions_tracked_minutes`) may hold.
  static const minutesMax = 1440;
}

/// Stops input at [max] UTF-16 code units, as [QuestLimits] counts. Text
/// is cut between characters, so an emoji or a letter with its marks is
/// never split. Text that was over the limit before it existed can still
/// be shortened or edited in place, but not lengthened, and is never cut.
class StoredLengthLimit extends TextInputFormatter {
  const StoredLengthLimit(this.max);

  final int max;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final length = newValue.text.length;
    if (length <= max) return newValue;
    final enforcement = LengthLimitingTextInputFormatter.getDefaultMaxLengthEnforcement();
    if (enforcement == MaxLengthEnforcement.none) return newValue;
    final before = oldValue.text.length;
    // Over the limit even without what an input method is still composing:
    // saved before the limit existed. Cutting it would lose what was written.
    // (Only where composing may overshoot: on the enforced path it never can.)
    final saved = enforcement == MaxLengthEnforcement.enforced ? before : before - _composingLength(oldValue);
    if (saved > max) return length <= before ? newValue : oldValue;
    // Otherwise the rules `maxLength` follows on this platform, in these units.
    switch (enforcement) {
      case MaxLengthEnforcement.none:
        return newValue;
      case MaxLengthEnforcement.enforced:
        if (before == max && oldValue.selection.isCollapsed) return oldValue;
      case MaxLengthEnforcement.truncateAfterCompositionEnds:
        if (before == max && !oldValue.composing.isValid) return oldValue;
        // Let the input method finish the word it is composing first.
        if (newValue.composing.isValid) return newValue;
    }
    return _truncate(newValue);
  }

  static int _composingLength(TextEditingValue value) {
    final composing = value.composing;
    return composing.isValid && composing.isNormalized ? composing.end - composing.start : 0;
  }

  TextEditingValue _truncate(TextEditingValue value) {
    var end = 0;
    for (final character in value.text.characters) {
      if (end + character.length > max) break;
      end += character.length;
    }
    final composing = value.composing;
    return TextEditingValue(
      text: value.text.substring(0, end),
      selection: value.selection.copyWith(
        baseOffset: math.min(value.selection.start, end),
        extentOffset: math.min(value.selection.end, end),
      ),
      composing: !composing.isCollapsed && end > composing.start
          ? TextRange(start: composing.start, end: math.min(composing.end, end))
          : TextRange.empty,
    );
  }
}

/// A field counter that counts what [StoredLengthLimit] counts, in the
/// person's digits. A [quiet] counter stays hidden until the text is within
/// a fifth of [max], which keeps small or optional fields calm.
InputCounterWidgetBuilder lengthCounter(
  TextEditingController controller,
  int max,
  AppFormatters f, {
  bool quiet = false,
}) => (context, {required currentLength, required isFocused, required maxLength}) {
  final length = controller.text.length;
  if (quiet && length < max * 4 ~/ 5) return null;
  final theme = InputDecorationTheme.of(context);
  final small = Theme.of(context).textTheme.bodySmall;
  return Text(
    '${f.number(length)}/${f.number(max)}',
    style: length > max
        ? theme.errorStyle ?? small?.copyWith(color: Theme.of(context).colorScheme.error)
        : theme.helperStyle ?? small,
    semanticsLabel: MaterialLocalizations.of(context).remainingTextFieldCharacterCount(math.max(0, max - length)),
  );
};

/// The message for [text] that is over [max] once trimmed (as the
/// repositories store it), or null when it fits.
String? tooLongError(String text, int max, AppLocalizations l10n, AppFormatters f) =>
    text.trim().length > max ? l10n.fieldTooLong(f.number(max)) : null;

/// Whole minutes in Latin, Persian or Arabic-Indic digits, with or without
/// a thousands separator ("90", "۹۰", "1,440"). Anything else is null: "90-120",
/// "1.5" or "1,5" are not read as 90120 or 15 by keeping only their digits.
int? parseMinutes(String text) {
  final value = HeuristicEvaluator.normaliseText(text);
  if (!RegExp(r'^(\d{1,5}|\d{1,2}[,٬]\d{3})$').hasMatch(value)) return null;
  return int.parse(value.replaceAll(RegExp(r'[,٬]'), ''));
}

/// Whether [minutes] is an estimate a quest can hold.
bool isEstimate(int? minutes) =>
    minutes != null && minutes >= QuestLimits.estimateMin && minutes <= QuestLimits.minutesMax;

/// A quest's estimate: empty, or whole minutes from 1 to a day.
String? estimateError(String text, AppLocalizations l10n, AppFormatters f) {
  if (text.trim().isEmpty) return null;
  return isEstimate(parseMinutes(text))
      ? null
      : l10n.fieldEstimateInvalid(f.number(QuestLimits.estimateMin), f.number(QuestLimits.minutesMax));
}

/// Minutes declared when sealing a deed: empty, or whole minutes up to a day.
String? declaredMinutesError(String text, AppLocalizations l10n, AppFormatters f) {
  if (text.trim().isEmpty) return null;
  final minutes = parseMinutes(text);
  return minutes == null || minutes > QuestLimits.minutesMax
      ? l10n.completeSheetMinutesInvalid(f.number(QuestLimits.minutesMax))
      : null;
}
