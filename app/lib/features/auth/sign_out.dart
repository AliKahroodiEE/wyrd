import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../notifications/push_provider.dart';
import 'auth_gateway.dart';

/// Signs this device out. Its push registration goes first, while the
/// session still works; at most 5 s, so a dead connection never blocks
/// signing out (the sign-out also invalidates the token on the device).
Future<void> signOutDevice(WidgetRef ref, AuthGateway gateway) async {
  await ref.read(pushServiceProvider).beforeSignOut().timeout(const Duration(seconds: 5), onTimeout: () {});
  await gateway.signOut();
}
