import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../data/sync/sync_coordinator.dart';
import 'auth_gateway.dart';
import 'sign_out.dart';

/// Asks, when someone signs in on a device that holds another account's
/// unsynced work, whether to remove that work or keep it, in which case the
/// new account is signed out again. `main()` wraps the app in it.
class HandoverHost extends ConsumerStatefulWidget {
  const HandoverHost({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<HandoverHost> createState() => _HandoverHostState();
}

class _HandoverHostState extends ConsumerState<HandoverHost> {
  Handover? _showing;
  BuildContext? _dialog;

  @override
  void initState() {
    super.initState();
    ref.listenManual<Handover?>(handoverProvider, (_, next) {
      final showing = _showing;
      // A withdrawn question (its sign-in ended) closes without an answer.
      if (showing != null && showing.withdrawn && !identical(next, showing)) {
        final dialog = _dialog;
        if (dialog != null && dialog.mounted) Navigator.of(dialog).pop();
      }
      if (next != null && !identical(next, _showing)) _show(next);
    }, fireImmediately: true);
  }

  Future<void> _show(Handover handover) async {
    _showing = handover;
    final navigator = ref.read(routerProvider).routerDelegate.navigatorKey.currentContext;
    if (navigator == null || !navigator.mounted) {
      // The first frame is not built yet: ask right after it.
      _showing = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && identical(ref.read(handoverProvider), handover)) _show(handover);
      });
      return;
    }
    final remove = await showDialog<bool>(
      context: navigator,
      barrierDismissible: false,
      builder: (context) {
        _dialog = context;
        final l10n = context.l10n;
        final changes = handover.unsynced == 1
            ? l10n.handoverOneChange
            : l10n.handoverChanges(ref.fmt(context).number(handover.unsynced));
        final email = handover.previousEmail;
        // Only the buttons answer: back and the barrier leave it open.
        return PopScope<bool>(
          canPop: false,
          child: AlertDialog(
            title: Text(l10n.handoverTitle),
            content: Text(
              // The address is isolated so it reads left to right in Persian.
              email == null ? l10n.handoverBodyNoEmail(changes) : l10n.handoverBody('\u2068$email\u2069', changes),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.handoverKeep)),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.handoverRemove)),
            ],
          ),
        );
      },
    );
    _dialog = null;
    if (handover.withdrawn) {
      if (identical(_showing, handover)) _showing = null;
      return;
    }
    if (remove == null) {
      // Closed unanswered: the page under it was replaced (a notification
      // opened another screen, or onboarding took over after another tab
      // cleared the device). That is no Keep; it is asked again while it
      // still applies.
      if (identical(_showing, handover)) _showing = null;
      if (mounted && identical(ref.read(handoverProvider), handover)) _show(handover);
      return;
    }
    if (!remove && mounted) {
      final gateway = ref.read(authGatewayProvider);
      if (gateway != null) {
        try {
          await signOutDevice(ref, gateway);
        } on Object {
          // Still signed in: sync stays held, and the question comes back on
          // the next start.
        }
      }
    }
    handover.decide(remove: remove);
    if (identical(_showing, handover)) _showing = null;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
