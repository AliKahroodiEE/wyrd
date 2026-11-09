import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyrd/features/install/ios_install_hint.dart';
import 'package:wyrd/l10n/generated/app_localizations.dart';

const _title = 'Add Wyrd to your Home Screen';

// The hint reads its environment once, so every pump gets a fresh element.
Future<void> _pump(WidgetTester tester, InstallHintEnvironment environment, {Locale? locale}) => tester.pumpWidget(
  MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: IosInstallHint(key: UniqueKey(), environment: environment),
    ),
  ),
);

InstallHintEnvironment _ios({bool fromHomeScreen = false, bool dismissed = false, VoidCallback? onDismissed}) =>
    InstallHintEnvironment(
      isIosBrowser: true,
      runsFromHomeScreen: fromHomeScreen,
      wasDismissed: dismissed,
      onDismissed: onDismissed,
    );

void main() {
  testWidgets('shows in an iOS browser and remembers the dismissal', (tester) async {
    var remembered = false;
    await _pump(tester, _ios(onDismissed: () => remembered = true));
    expect(find.text(_title), findsOneWidget);

    await tester.tap(find.byTooltip('Close'));
    await tester.pump();
    expect(find.text(_title), findsNothing);
    expect(remembered, isTrue);
  });

  testWidgets('stays hidden when installed, dismissed or not on iOS', (tester) async {
    final cases = {
      'installed': _ios(fromHomeScreen: true),
      'dismissed': _ios(dismissed: true),
      'not an iOS browser': InstallHintEnvironment.none,
    };
    for (final MapEntry(key: name, value: environment) in cases.entries) {
      await _pump(tester, environment);
      expect(find.text(_title), findsNothing, reason: name);
      expect(find.byType(IconButton), findsNothing, reason: name);
    }
  });

  testWidgets('is translated into Persian', (tester) async {
    await _pump(tester, _ios(), locale: const Locale('fa'));
    final l10n = lookupAppLocalizations(const Locale('fa'));
    expect(find.text(l10n.installHintTitle), findsOneWidget);
    expect(find.byTooltip(l10n.actionClose), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('the running test platform is not a browser', () {
    expect(InstallHintEnvironment.current().shouldShow, isFalse);
  });
}
