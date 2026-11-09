import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyrd/features/quests/quest_limits.dart';

void main() {
  group('parseMinutes', () {
    test('reads whole minutes in any digits', () {
      expect(parseMinutes('90'), 90);
      expect(parseMinutes(' ۹۰ '), 90);
      expect(parseMinutes('١٢٠'), 120);
      expect(parseMinutes('1,440'), 1440);
      expect(parseMinutes('۱٬۴۴۰'), 1440);
      expect(parseMinutes('0'), 0);
    });

    test('refuses anything that is not one whole number', () {
      for (final text in [
        '',
        '90-120',
        '1.5',
        '۱٫۵',
        '1,5',
        '5,10',
        '۱٬۵',
        '90,',
        ',90',
        '45 min',
        '-5',
        'an hour',
        '999999',
      ]) {
        expect(parseMinutes(text), isNull, reason: text);
      }
    });
  });

  group('StoredLengthLimit', () {
    const limit = StoredLengthLimit(10);

    TextEditingValue typed(String text) => TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );

    test('cuts between characters, never inside an emoji', () {
      // Nine units fit; the next emoji needs four more.
      expect(limit.formatEditUpdate(typed(''), typed('${'a' * 9}👍🏽')).text, 'a' * 9);
      expect(limit.formatEditUpdate(typed(''), typed('👍🏽👍🏽👍🏽')).text, '👍🏽👍🏽');
    });

    test('counts a ZWNJ, which takes no place on screen', () {
      expect(limit.formatEditUpdate(typed(''), typed('می‌خواهم می‌خواهم')).text, 'می‌خواهم م');
    });

    test('does not cut older text that is only just over the limit while a word is composed', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android; // the enforced path
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final old = TextEditingValue(
        text: 'a' * 12,
        selection: const TextSelection.collapsed(offset: 6),
        composing: const TextRange(start: 2, end: 6),
      );
      final backspace = TextEditingValue(
        text: 'a' * 11,
        selection: const TextSelection.collapsed(offset: 5),
        composing: const TextRange(start: 2, end: 5),
      );
      expect(limit.formatEditUpdate(old, backspace).text, 'a' * 11, reason: 'only what was deleted goes');
    });

    test('keeps the text when full and lets text over the limit be shortened', () {
      expect(limit.formatEditUpdate(typed('a' * 10), typed('a' * 11)).text, 'a' * 10);
      expect(limit.formatEditUpdate(typed('a' * 30), typed('a' * 29)).text, 'a' * 29);
    });
  });
}
