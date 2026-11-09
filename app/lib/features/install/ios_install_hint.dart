import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/providers.dart';
import '../../design/tokens.dart';
import 'install_hint_browser_stub.dart' if (dart.library.js_interop) 'install_hint_browser_web.dart' as browser;

/// What decides whether [IosInstallHint] shows.
@immutable
class InstallHintEnvironment {
  const InstallHintEnvironment({
    required this.isIosBrowser,
    required this.runsFromHomeScreen,
    required this.wasDismissed,
    this.onDismissed,
  });

  /// The running app: a web build on iPhone or iPad (Safari, or another iOS
  /// browser, which share Safari's Add to Home Screen since iOS 16.4).
  factory InstallHintEnvironment.current() {
    if (!kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return none;
    return InstallHintEnvironment(
      isIosBrowser: true,
      runsFromHomeScreen: browser.runsFromHomeScreen(),
      wasDismissed: browser.readFlag(_dismissedKey),
      onDismissed: () => browser.writeFlag(_dismissedKey),
    );
  }

  /// Native apps, desktop and Android browsers.
  static const none = InstallHintEnvironment(isIosBrowser: false, runsFromHomeScreen: false, wasDismissed: false);

  static const _dismissedKey = 'wyrd.installHintDismissed';

  final bool isIosBrowser;
  final bool runsFromHomeScreen;
  final bool wasDismissed;

  /// Remembers the dismissal so the hint never comes back.
  final VoidCallback? onDismissed;

  bool get shouldShow => isIosBrowser && !runsFromHomeScreen && !wasDismissed;
}

/// Tiny, dismissible tip for iPhone and iPad visitors of the web app: added to
/// the Home Screen, Wyrd opens full screen and can receive push notifications
/// (iOS 16.4+). Renders nothing anywhere else, once installed, or after it was
/// dismissed.
class IosInstallHint extends StatefulWidget {
  const IosInstallHint({super.key, this.environment});

  /// Replaces the browser checks (tests); defaults to [InstallHintEnvironment.current].
  final InstallHintEnvironment? environment;

  @override
  State<IosInstallHint> createState() => _IosInstallHintState();
}

class _IosInstallHintState extends State<IosInstallHint> {
  late final InstallHintEnvironment _environment = widget.environment ?? InstallHintEnvironment.current();
  late bool _visible = _environment.shouldShow;

  void _dismiss() {
    _environment.onDismissed?.call();
    setState(() => _visible = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    final l10n = context.l10n;
    final palette = context.palette;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: AppSpace.md),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.sunken,
          borderRadius: AppRadius.softAll,
          border: Border.all(color: palette.hairline),
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.only(start: AppSpace.md, top: AppSpace.xs, bottom: AppSpace.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.only(top: AppSpace.sm + 2),
                child: Icon(Icons.ios_share, size: 20, color: palette.accent),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(top: AppSpace.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.installHintTitle, style: text.titleSmall),
                      const SizedBox(height: AppSpace.xs),
                      Text(l10n.installHintBody, style: text.bodySmall),
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: l10n.actionClose,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close, size: 18),
                onPressed: _dismiss,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
