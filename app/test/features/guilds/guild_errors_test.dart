import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:wyrd/features/guilds/guild_hall_screen.dart';
import 'package:wyrd/l10n/generated/app_localizations.dart';

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final fa = lookupAppLocalizations(const Locale('fa'));

  // As react, unreact and add_comment refuse past their limits.
  const reactionLimit = PostgrestException(
    message: 'reaction limit reached, try again later',
    code: '54000',
    hint: 'rate_limited',
  );
  const commentLimit = PostgrestException(
    message: 'comment limit reached, try again later',
    code: '54000',
    hint: 'rate_limited',
  );

  test('a rate-limited reaction asks for a minute: the limit is 60 changes a minute', () {
    expect(guildErrorMessage(en, reactionLimit, GuildAction.react), en.actionRateLimited);
    expect(en.actionRateLimited, contains('minute'));
  });

  test('a rate-limited comment asks to come back later: the limit is 30 an hour in a guild', () {
    expect(guildErrorMessage(en, commentLimit, GuildAction.comment), en.commentRateLimited);
    expect(guildErrorMessage(fa, commentLimit, GuildAction.comment), fa.commentRateLimited);
    expect(en.commentRateLimited, allOf(contains('hour'), isNot(contains('minute'))));
    expect(fa.commentRateLimited, isNot(fa.actionRateLimited));
  });

  test('other refusals, such as a full guild, get the general message', () {
    const full = PostgrestException(message: 'this guild is full', code: '54000', hint: 'guild_full');
    for (final action in GuildAction.values) {
      expect(guildErrorMessage(en, full, action), en.errorGeneric, reason: action.name);
      expect(guildErrorMessage(en, StateError('offline'), action), en.errorGeneric, reason: action.name);
    }
  });
}
