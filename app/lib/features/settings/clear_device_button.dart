import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../data/clear_device.dart';
import '../../data/remote/backend.dart';
import '../../data/sync/sync_coordinator.dart';
import '../auth/auth_errors.dart';
import '../auth/auth_gateway.dart';
import '../auth/sign_out.dart';

/// Guests: "Delete all data", which lives only on this device. Signed in,
/// wiping alone would only download everything again, so the button signs
/// out first and then clears the device; deleting the account itself is
/// "Delete account" above.
class ClearDeviceButton extends ConsumerWidget {
  const ClearDeviceButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final gateway = ref.watch(authGatewayProvider);
    final signedIn = ref.watch(currentUserProvider).value != null && gateway != null;
    final label = signedIn ? l10n.signOutClearDevice : l10n.deleteAllData;
    return TextButton(
      onPressed: () async {
        final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text(label),
            content: Text(signedIn ? l10n.signOutClearDeviceBody : l10n.deleteAllDataBody),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: Text(l10n.actionCancel)),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: Text(signedIn ? l10n.signOut : l10n.actionDelete),
              ),
            ],
          ),
        );
        if (ok != true || !context.mounted) return;
        // Signing out can rebuild this button, so everything needed is taken now.
        final sync = ref.read(syncControlProvider);
        final data = ref.read(dataRepositoryProvider);
        final ai = ref.read(aiSettingsRepositoryProvider);
        final messenger = ScaffoldMessenger.of(context);
        final router = GoRouter.of(context);
        if (signedIn) {
          try {
            await signOutDevice(ref, gateway);
          } on Object catch (e) {
            messenger.showSnackBar(SnackBar(content: Text(authErrorMessage(l10n, e))));
            return;
          }
        }
        await clearDevice(sync: sync, data: data, ai: ai);
        messenger.showSnackBar(SnackBar(content: Text(signedIn ? l10n.deviceCleared : l10n.dataDeleted)));
        router.go('/onboarding');
      },
      child: Text(label),
    );
  }
}
