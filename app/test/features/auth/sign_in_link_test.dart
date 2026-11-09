import 'package:flutter_test/flutter_test.dart';
import 'package:wyrd/features/auth/sign_in_link.dart';

/// After a failed Google or GitHub sign-in, Auth sends the web app back with
/// the error in the query and again in the fragment; once the app has said
/// so, the address loses it and keeps everything else.
void main() {
  group('withoutSignInError', () {
    test('drops the error Auth put in the query and in the fragment', () {
      expect(
        withoutSignInError(
          'https://wyrd-app.pages.dev/?error=access_denied'
          '&error_description=The+user+has+denied+your+application+access.'
          '#error=access_denied&error_description=The+user+has+denied+your+application+access.',
        ),
        'https://wyrd-app.pages.dev/',
      );
      expect(
        withoutSignInError(
          'https://example.github.io/wyrd/?error=server_error&error_code=unexpected_failure'
          '&error_description=Unexpected+failure%2C+please+check+server+logs+for+more+information'
          '#error=server_error&error_code=unexpected_failure&error_description=Unexpected+failure',
        ),
        'https://example.github.io/wyrd/',
      );
    });

    test('keeps the hash route the app has moved to meanwhile', () {
      expect(
        withoutSignInError(
          'https://wyrd-app.pages.dev/?error=invalid_request&error_code=bad_oauth_state'
          '&error_description=OAuth+callback+with+invalid+state#/character',
        ),
        'https://wyrd-app.pages.dev/#/character',
      );
      expect(withoutSignInError('https://wyrd-app.pages.dev/?error=access_denied#/'), 'https://wyrd-app.pages.dev/#/');
    });

    test('keeps every other parameter, in order and as written', () {
      expect(
        withoutSignInError(
          'http://localhost:8080/?lang=fa&error=temporarily_unavailable&error_description=Service%20unavailable'
          '&utm_source=mail+list#/settings',
        ),
        'http://localhost:8080/?lang=fa&utm_source=mail+list#/settings',
      );
      expect(
        withoutSignInError('https://wyrd-app.pages.dev/?ref=home#error=access_denied&error_description=x&state=abc'),
        'https://wyrd-app.pages.dev/?ref=home#state=abc',
      );
    });

    test('takes the error out of a hash route\'s own parameters', () {
      expect(
        withoutSignInError('https://wyrd-app.pages.dev/#/settings?error=access_denied&tab=push'),
        'https://wyrd-app.pages.dev/#/settings?tab=push',
      );
      expect(
        withoutSignInError('https://wyrd-app.pages.dev/#/settings?error_code=bad_oauth_state&error=invalid_request'),
        'https://wyrd-app.pages.dev/#/settings',
      );
    });

    test('reads parameter names decoded, and leaves malformed ones alone', () {
      expect(
        withoutSignInError('https://wyrd-app.pages.dev/?%65rror=access_denied&a=1'),
        'https://wyrd-app.pages.dev/?a=1',
      );
      expect(
        withoutSignInError('https://wyrd-app.pages.dev/?%zz=1&error=access_denied'),
        'https://wyrd-app.pages.dev/?%zz=1',
      );
    });

    test('returns any other address unchanged', () {
      for (final url in [
        'https://wyrd-app.pages.dev/',
        'https://wyrd-app.pages.dev/#/character',
        'https://wyrd-app.pages.dev/?errors=2&error_count=1&my_error=x#/error',
        'https://wyrd-app.pages.dev/#/guilds?invite=ABCD',
        'https://wyrd-app.pages.dev/?',
        'https://wyrd-app.pages.dev/#',
        'https://wyrd-app.pages.dev/?a=1&&b=2#top',
      ]) {
        expect(withoutSignInError(url), url);
      }
    });
  });

  test('outside the browser there is no address to clean', () {
    expect(forgetSignInError, returnsNormally);
  });

  // forgetSignInError runs only after a sign-in error was reported, when
  // supabase_flutter has already tried (and failed) to trade the code.
  test('a sign-in code whose exchange failed leaves the query too, not a hash route', () {
    expect(
      withoutSignInError('https://wyrd-app.pages.dev/?code=0f9e#/character'),
      'https://wyrd-app.pages.dev/#/character',
    );
    expect(
      withoutSignInError('https://wyrd-app.pages.dev/?code=0f9e&ref=mail#/quests?code=keep'),
      'https://wyrd-app.pages.dev/?ref=mail#/quests?code=keep',
    );
  });
}
