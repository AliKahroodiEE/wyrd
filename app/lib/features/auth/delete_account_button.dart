import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../data/clear_device.dart';
import '../../data/sync/sync_coordinator.dart';
import 'auth_errors.dart';
import 'auth_gateway.dart';

/// "Delete account", after a confirmation: the server deletes the account
/// and its data (`public.delete_my_account()`), then this device signs out,
/// forgets its local copy (and the AI key) and starts over at onboarding.
class DeleteAccountButton extends ConsumerStatefulWidget {
  const DeleteAccountButton({super.key});

  @override
  ConsumerState<DeleteAccountButton> createState() => _DeleteAccountButtonState();
}

class _DeleteAccountButtonState extends ConsumerState<DeleteAccountButton> {
  bool _busy = false;

  Future<void> _delete() async {
    final l10n = context.l10n;
    final gateway = ref.read(authGatewayProvider);
    if (gateway == null || _busy) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l10n.deleteAccount),
        content: Text(l10n.deleteAccountBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(l10n.actionCancel)),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(l10n.deleteAccount)),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    // Signing out removes this button from the Account panel, so everything
    // needed afterwards is taken now.
    final sync = ref.read(syncControlProvider);
    final data = ref.read(dataRepositoryProvider);
    final ai = ref.read(aiSettingsRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    setState(() => _busy = true);
    try {
      await gateway.deleteAccount();
    } on Object catch (e) {
      if (mounted) setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text(authErrorMessage(l10n, e))));
      return;
    }
    try {
      await gateway.signOut();
    } on Object {
      // The local session is dropped before the server is told; the server
      // one went with the account.
    }
    // Stops sync first, so a download in progress cannot refill the device.
    await clearDevice(sync: sync, data: data, ai: ai);
    messenger.showSnackBar(SnackBar(content: Text(l10n.accountDeleted)));
    router.go('/onboarding');
  }

  @override
  Widget build(BuildContext context) => TextButton.icon(
    icon: _busy
        ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
        : const Icon(Icons.person_remove_outlined, size: 18),
    label: Text(context.l10n.deleteAccount),
    onPressed: _busy ? null : _delete,
  );
}
