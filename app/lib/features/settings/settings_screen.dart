import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/config.dart';
import '../../core/locale/locale_registry.dart';
import '../../core/locale/regional_settings.dart';
import '../../data/models.dart';
import '../../data/remote/backend.dart';
import '../../data/repositories/settings_repository.dart';
import '../../design/components/panel.dart';
import '../../design/tokens.dart';
import '../auth/delete_account_button.dart';
import '../install/ios_install_hint.dart';
import '../notifications/push_tile.dart';
import 'ai_provider_screen.dart';
import 'clear_device_button.dart';
import 'legal_links.dart';
import 'theme_picker.dart';

/// Settings (requirements §4.10).
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final profile = ref.watch(profileProvider).value ?? const UserProfile();
    final regional = ref.watch(regionalProvider);
    final settings = ref.read(settingsRepositoryProvider);
    final f = ref.fmt(context);
    final text = Theme.of(context).textTheme;

    Future<void> setProfile(UserProfile Function(UserProfile) change) => settings.updateProfile(change);
    Future<void> setRegional(RegionalPrefs Function(RegionalPrefs) change) => settings.updateRegionalPrefs(change);

    const gap = SizedBox(height: AppSpace.lg);
    final weekdays = {
      DateTime.saturday: DateTime(2026, 11, 7),
      DateTime.sunday: DateTime(2026, 11, 8),
      DateTime.monday: DateTime(2026, 11, 2),
    };
    final hasNativeDigits = regional.meta.nativeZeroCodeUnit != 0x30;
    final todayKey = dayKey(DateTime.now());
    final restToday = ref.watch(characterStateProvider).value?.restToday ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settingsTitle),
        leading: context.canPop()
            ? null
            : IconButton(
                tooltip: l10n.actionClose,
                icon: const Icon(Icons.close),
                onPressed: () => context.go('/character'),
              ),
      ),
      body: Align(
        alignment: AlignmentDirectional.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsetsDirectional.all(AppSpace.lg),
            children: [
              Panel(
                title: l10n.sectionLanguageRegion,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(l10n.language, style: text.labelMedium),
                    const SizedBox(height: AppSpace.sm),
                    SegmentedButton<String>(
                      showSelectedIcon: false,
                      segments: [
                        ButtonSegment(value: '', label: Text(l10n.languageAuto)),
                        for (final m in LocaleRegistry.all)
                          ButtonSegment(value: m.locale.languageCode, label: Text(m.nativeName)),
                      ],
                      selected: {regional.followsDevice ? '' : regional.locale.languageCode},
                      onSelectionChanged: (s) =>
                          setRegional((r) => r.copyWith(language: s.first.isEmpty ? null : s.first)),
                    ),
                    if (regional.followsDevice) ...[
                      const SizedBox(height: AppSpace.xs),
                      Text(l10n.languageFollowsDevice(regional.meta.nativeName), style: text.bodySmall),
                    ],
                    const SizedBox(height: AppSpace.lg),
                    Text(l10n.calendar, style: text.labelMedium),
                    const SizedBox(height: AppSpace.sm),
                    SegmentedButton<CalendarSystem>(
                      showSelectedIcon: false,
                      segments: [
                        ButtonSegment(value: CalendarSystem.gregorian, label: Text(l10n.calendarGregorian)),
                        ButtonSegment(value: CalendarSystem.jalali, label: Text(l10n.calendarJalali)),
                      ],
                      selected: {regional.calendar},
                      onSelectionChanged: (s) => setRegional((r) => r.copyWith(calendar: s.first)),
                    ),
                    if (hasNativeDigits) ...[
                      const SizedBox(height: AppSpace.lg),
                      Text(l10n.digits, style: text.labelMedium),
                      const SizedBox(height: AppSpace.sm),
                      SegmentedButton<DigitStyle>(
                        showSelectedIcon: false,
                        segments: [
                          ButtonSegment(value: DigitStyle.native, label: Text(l10n.digitsNative)),
                          ButtonSegment(value: DigitStyle.latin, label: Text(l10n.digitsLatin)),
                        ],
                        selected: {regional.digits},
                        onSelectionChanged: (s) => setRegional((r) => r.copyWith(digits: s.first)),
                      ),
                    ],
                    const SizedBox(height: AppSpace.lg),
                    DropdownButtonFormField<int>(
                      initialValue: weekdays.containsKey(regional.firstWeekday)
                          ? regional.firstWeekday
                          : DateTime.monday,
                      decoration: InputDecoration(labelText: l10n.firstDayOfWeek),
                      items: [
                        for (final e in weekdays.entries)
                          DropdownMenuItem(value: e.key, child: Text(f.weekdayLong(e.value))),
                      ],
                      onChanged: (v) => setRegional((r) => r.copyWith(firstWeekday: v)),
                    ),
                  ],
                ),
              ),
              gap,
              Panel(
                title: l10n.sectionAppearance,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(l10n.themeLabel, style: text.labelMedium),
                    const SizedBox(height: AppSpace.sm),
                    SegmentedButton<ThemePreference>(
                      showSelectedIcon: false,
                      segments: [
                        for (final t in ThemePreference.values)
                          ButtonSegment(
                            value: t,
                            icon: Icon(themePreferenceIcon(t), size: 18),
                            label: Text(themePreferenceLabel(l10n, t)),
                          ),
                      ],
                      selected: {profile.theme},
                      onSelectionChanged: (s) => setProfile((p) => p.copyWith(theme: s.first)),
                    ),
                    const SizedBox(height: AppSpace.sm),
                    SwitchListTile(
                      contentPadding: EdgeInsetsDirectional.zero,
                      title: Text(l10n.reducedMotion),
                      value: profile.reducedMotion,
                      onChanged: (v) => setProfile((p) => p.copyWith(reducedMotion: v)),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsetsDirectional.zero,
                      title: Text(l10n.reducedEffects),
                      value: profile.reducedEffects,
                      onChanged: (v) => setProfile((p) => p.copyWith(reducedEffects: v)),
                    ),
                    const IosInstallHint(),
                  ],
                ),
              ),
              gap,
              Panel(
                title: l10n.sectionProgress,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(l10n.weeklyTarget, style: text.titleSmall)),
                        Text(
                          l10n.weeklyTargetValue(profile.weeklyTarget, f.number(profile.weeklyTarget)),
                          style: text.labelLarge,
                        ),
                      ],
                    ),
                    Slider(
                      value: profile.weeklyTarget.toDouble(),
                      min: 1,
                      max: 7,
                      divisions: 6,
                      label: f.number(profile.weeklyTarget),
                      onChanged: (v) => setProfile((p) => p.copyWith(weeklyTarget: v.round())),
                    ),
                    Text(l10n.weeklyTargetHelp, style: text.bodySmall),
                    const Divider(height: AppSpace.xxl),
                    SwitchListTile(
                      contentPadding: EdgeInsetsDirectional.zero,
                      title: Text(l10n.restDayToday),
                      subtitle: restToday ? Text(l10n.restDayDeclared) : null,
                      value: restToday,
                      onChanged: (v) => ref.read(progressionRepositoryProvider).setRestDay(todayKey, v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsetsDirectional.zero,
                      title: Text(l10n.pauseMode),
                      subtitle: Text(l10n.pauseModeHelp),
                      value: profile.paused,
                      onChanged: (v) async {
                        if (!v && profile.pauseStartedDay != null) {
                          final days = <String>[];
                          final end = parseDayKey(todayKey);
                          for (
                            var d = parseDayKey(profile.pauseStartedDay!);
                            !d.isAfter(end);
                            d = DateTime.utc(d.year, d.month, d.day + 1)
                          ) {
                            days.add(dayKey(d));
                          }
                          await ref.read(progressionRepositoryProvider).markPausedDays(days);
                        }
                        await setProfile((p) => p.copyWith(pauseStartedDay: v ? todayKey : null));
                      },
                    ),
                  ],
                ),
              ),
              gap,
              Panel(
                title: l10n.sectionMotivation,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(l10n.motivationTone, style: text.titleSmall),
                    const SizedBox(height: AppSpace.sm),
                    Wrap(
                      spacing: AppSpace.sm,
                      runSpacing: AppSpace.sm,
                      children: [
                        for (final (id, label) in [
                          ('direct', l10n.toneDirect),
                          ('gentle', l10n.toneGentle),
                          ('achievement', l10n.toneAchievement),
                          ('analytical', l10n.toneAnalytical),
                        ])
                          ChoiceChip(
                            label: Text(label),
                            selected: profile.tone == id,
                            onSelected: (sel) => setProfile((p) => p.copyWith(tone: sel ? id : null)),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpace.lg),
                    Text(l10n.motivationDrivers, style: text.titleSmall),
                    const SizedBox(height: AppSpace.sm),
                    Wrap(
                      spacing: AppSpace.sm,
                      runSpacing: AppSpace.sm,
                      children: [
                        for (final (id, label) in [
                          ('achievement', l10n.driverAchievement),
                          ('social', l10n.driverSocial),
                          ('progress', l10n.driverProgress),
                          ('longTerm', l10n.driverLongTerm),
                          ('exploration', l10n.driverExploration),
                          ('routine', l10n.driverRoutine),
                        ])
                          FilterChip(
                            label: Text(label),
                            selected: profile.drivers.contains(id),
                            onSelected: (sel) => setProfile(
                              (p) => p.copyWith(
                                drivers: sel ? [...p.drivers, id] : p.drivers.where((d) => d != id).toList(),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpace.md),
                    Text(l10n.motivationPrivacy, style: text.bodySmall),
                  ],
                ),
              ),
              gap,
              Panel(
                title: l10n.sectionAi,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsetsDirectional.zero,
                      title: Text(l10n.aiEvaluation),
                      subtitle: Text(l10n.aiEvaluationHelp),
                      value: profile.aiEnabled,
                      onChanged: (v) => setProfile((p) => p.copyWith(aiEnabled: v)),
                    ),
                    Builder(
                      builder: (context) {
                        final config = ref.watch(aiProviderConfigProvider).value;
                        return ListTile(
                          contentPadding: EdgeInsetsDirectional.zero,
                          leading: const Icon(Icons.key_outlined),
                          title: Text(l10n.aiProvider),
                          subtitle: Text(
                            config == null
                                ? l10n.aiProviderSummaryNone
                                : '${aiProviderLabel(l10n, config.kind)} · ${config.model}',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          enabled: profile.aiEnabled,
                          onTap: () => context.push('/settings/ai'),
                        );
                      },
                    ),
                    const SizedBox(height: AppSpace.sm),
                    DropdownButtonFormField<String?>(
                      initialValue: profile.aiLocale,
                      decoration: InputDecoration(labelText: l10n.aiLanguage),
                      items: [
                        DropdownMenuItem(value: null, child: Text(l10n.aiSameAsApp)),
                        for (final m in LocaleRegistry.all)
                          DropdownMenuItem(value: m.locale.languageCode, child: Text(m.nativeName)),
                      ],
                      onChanged: (v) => setProfile((p) => p.copyWith(aiLocale: v)),
                    ),
                    const SizedBox(height: AppSpace.md),
                    ExpansionTile(
                      tilePadding: EdgeInsetsDirectional.zero,
                      shape: const Border(),
                      collapsedShape: const Border(),
                      title: Text(l10n.aiTransparency, style: text.titleSmall),
                      children: [Text(l10n.aiTransparencyBody, style: text.bodyMedium)],
                    ),
                  ],
                ),
              ),
              gap,
              Panel(
                title: l10n.sectionNotifications,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsetsDirectional.zero,
                      title: Text(l10n.notifReminders),
                      value: profile.notifReminders,
                      onChanged: (v) => setProfile((p) => p.copyWith(notifReminders: v)),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsetsDirectional.zero,
                      title: Text(l10n.notifGuild),
                      value: profile.notifGuild,
                      onChanged: (v) {
                        if (v) ref.read(pushServiceProvider).enable(); // Ask inside the tap.
                        setProfile((p) => p.copyWith(notifGuild: v));
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsetsDirectional.zero,
                      title: Text(l10n.notifWeekly),
                      value: profile.notifWeekly,
                      onChanged: (v) {
                        if (v) ref.read(pushServiceProvider).enable(); // Ask inside the tap.
                        setProfile((p) => p.copyWith(notifWeekly: v));
                      },
                    ),
                    const PushDeviceTile(),
                    ListTile(
                      contentPadding: EdgeInsetsDirectional.zero,
                      title: Text(l10n.quietHours),
                      subtitle: Text(
                        l10n.quietHoursValue(
                          _hm(f.digits, profile.quietStartMinutes),
                          _hm(f.digits, profile.quietEndMinutes),
                        ),
                      ),
                      trailing: const Icon(Icons.schedule),
                      onTap: () async {
                        final start = await showTimePicker(
                          context: context,
                          initialTime: _tod(profile.quietStartMinutes),
                        );
                        if (start == null || !context.mounted) return;
                        final end = await showTimePicker(context: context, initialTime: _tod(profile.quietEndMinutes));
                        if (end == null) return;
                        await setProfile(
                          (p) => p.copyWith(
                            quietStartMinutes: start.hour * 60 + start.minute,
                            quietEndMinutes: end.hour * 60 + end.minute,
                          ),
                        );
                      },
                    ),
                    if (kIsWeb) Text(l10n.notificationsWebNote, style: text.bodySmall),
                  ],
                ),
              ),
              gap,
              Panel(
                title: l10n.sectionAccount,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Builder(
                      builder: (context) {
                        final user = ref.watch(currentUserProvider).value;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              user != null
                                  ? l10n.signedInAs(user.email ?? '')
                                  : BackendConfig.isConfigured
                                  ? l10n.guestMode
                                  : '${l10n.guestMode} ${l10n.authBackendMissing}',
                              style: text.bodyMedium,
                            ),
                            if (BackendConfig.isConfigured) ...[
                              const SizedBox(height: AppSpace.md),
                              OutlinedButton(
                                onPressed: () => context.push('/auth'),
                                child: Text(user != null ? l10n.signOut : l10n.signIn),
                              ),
                            ],
                            if (user != null) ...[const SizedBox(height: AppSpace.xs), const DeleteAccountButton()],
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: AppSpace.lg),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.download_outlined, size: 18),
                      label: Text(l10n.exportData),
                      onPressed: () async {
                        final data = await ref.read(dataRepositoryProvider).exportAll();
                        await Clipboard.setData(ClipboardData(text: const JsonEncoder.withIndent('  ').convert(data)));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.exportReady)));
                        }
                      },
                    ),
                    const SizedBox(height: AppSpace.sm),
                    const ClearDeviceButton(),
                  ],
                ),
              ),
              gap,
              Text(l10n.aboutLicense, style: text.bodySmall, textAlign: TextAlign.center),
              const LegalLinks(),
              const SizedBox(height: AppSpace.xxl),
            ],
          ),
        ),
      ),
    );
  }

  static TimeOfDay _tod(int minutes) => TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);

  static String _hm(String Function(String) digits, int minutes) =>
      digits('${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}');
}
