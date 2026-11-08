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
      for (final text in ['', '90-120', '1.5', '۱٫۵', '45 min', '-5', 'an hour', '999999']) {
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

    test('keeps the text when full and lets text over the limit be shortened', () {
      expect(limit.formatEditUpdate(typed('a' * 10), typed('a' * 11)).text, 'a' * 10);
      expect(limit.formatEditUpdate(typed('a' * 30), typed('a' * 29)).text, 'a' * 29);
    });
  });
}
