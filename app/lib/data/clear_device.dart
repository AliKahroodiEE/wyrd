import 'ai/ai_settings_repository.dart';
import 'repositories/data_repository.dart';
import 'sync/sync_coordinator.dart';

/// Forgets everything this device holds: stops sync and waits for a cycle in
/// progress (so nothing lands afterwards), wipes the database and removes
/// the AI key from secure storage.
Future<void> clearDevice({
  required SyncControl sync,
  required DataRepository data,
  required AiSettingsRepository ai,
}) async {
  await sync.stop();
  await data.wipe();
  await ai.clear();
}
