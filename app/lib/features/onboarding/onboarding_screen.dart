import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wyrd_engine/wyrd_engine.dart';

import '../../app/providers.dart';
import '../../core/locale/locale_registry.dart';
import '../../data/models.dart';
import '../../design/components/background.dart';
import '../../design/components/game.dart';
import '../../design/sigils.dart';
import '../../design/tokens.dart';
import '../../l10n/content.dart';
import '../quests/complete_flow.dart';
import '../quests/quest_limits.dart';
import '../settings/theme_picker.dart';

/// First-run flow (ux-spec §4): language → name and sigil → areas →
/// first quest (complete now or later) → how growth works. The first
/// meaningful moment — a real deed and visible growth — happens inside
/// three minutes, and nothing else is required up front.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  int _step = 0;
  final _name = TextEditingController();
  final _quest = TextEditingController();
  String _portrait = 'tower';
  final Set<QuestCategory> _areas = {};
  bool _busy = false;

  static const _areaChoices = [
    QuestCategory.study,
    QuestCategory.fitness,
    QuestCategory.creative,
    QuestCategory.social,
    QuestCategory.health,
    QuestCategory.work,
    QuestCategory.reading,
    QuestCategory.mindfulness,
  ];

  @override
  void dispose() {
    _name.dispose();
    _quest.dispose();
    super.dispose();
  }

  void _next() => setState(() => _step++);

  /// Null keeps following the device language.
  Future<void> _chooseLanguage(Locale? locale) async {
    await ref.read(settingsRepositoryProvider).updateRegionalPrefs((r) => r.copyWith(language: locale?.languageCode));
    _next();
  }

  Future<void> _saveIdentity() async {
    await ref
        .read(settingsRepositoryProvider)
        .updateProfile((p) => p.copyWith(characterName: _name.text.trim(), portrait: _portrait));
    _next();
  }

  Future<void> _saveAreas() async {
    await ref
        .read(settingsRepositoryProvider)
        .updateProfile((p) => p.copyWith(areas: [for (final a in _areas) a.name]));
    _next();
  }

  Future<void> _swear({required bool completeNow}) async {
    final title = _quest.text.trim();
    if (title.isEmpty || title.length > QuestLimits.titleMax || _busy) return;
    setState(() => _busy = true);
    final now = DateTime.now();
    final quest = await ref
        .read(questRepositoryProvider)
        .create(QuestDraft(title: title, dueAt: DateTime(now.year, now.month, now.day)));
    if (completeNow && mounted) await completeQuest(context, ref, quest);
    if (!mounted) return;
    setState(() => _busy = false);
    _next();
  }

  Future<void> _finish() async {
    await ref.read(settingsRepositoryProvider).updateProfile((p) => p.copyWith(onboardingComplete: true));
    if (mounted) context.go('/character');
  }

  List<String> _suggestions() {
    final l10n = context.l10n;
    final byArea = {
      QuestCategory.study: l10n.suggestStudy,
      QuestCategory.fitness: l10n.suggestWalk,
      QuestCategory.health: l10n.suggestWalk,
      QuestCategory.reading: l10n.suggestRead,
      QuestCategory.social: l10n.suggestCall,
      QuestCategory.work: l10n.suggestTidy,
      QuestCategory.creative: l10n.suggestCreate,
      QuestCategory.mindfulness: l10n.suggestWalk,
    };
    final picked = {for (final a in _areas) ?byArea[a]};
    return {...picked, l10n.suggestStudy, l10n.suggestWalk, l10n.suggestRead, l10n.suggestCall}.take(4).toList();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final l10n = context.l10n;
    final steps = [_language, _identity, _areasStep, _firstQuest, _howItWorks];
    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.xl, AppSpace.lg, AppSpace.xl, 0),
                    child: Row(
                      children: [
                        if (_step > 0)
                          IconButton(
                            tooltip: l10n.actionBack,
                            onPressed: () => setState(() => _step--),
                            icon: const BackButtonIcon(),
                          ),
                        const Spacer(),
                        Text(l10n.appName, style: text.labelSmall),
                        const SizedBox(width: AppSpace.xs),
                        const ThemeMenuButton(),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsetsDirectional.symmetric(horizontal: AppSpace.xl),
                    child: LinearProgressIndicator(value: (_step + 1) / steps.length, minHeight: 2),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsetsDirectional.all(AppSpace.xl),
                      child: steps[_step](context),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _language(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final device = LocaleRegistry.of(ref.watch(deviceLocaleProvider));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpace.xl),
        Center(
          child: XpRing(
            fraction: 1,
            size: 148,
            stroke: 6,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [context.palette.glow, context.palette.sunken]),
              ),
              child: const Center(child: Icon(Icons.local_fire_department_rounded, size: 54, color: AppColors.ember)),
            ),
          ),
        ),
        const SizedBox(height: AppSpace.xl),
        Text(l10n.appTagline, style: text.displayMedium, textAlign: TextAlign.center),
        const SizedBox(height: AppSpace.lg),
        Text(l10n.onbWelcomeBody, style: text.bodyLarge),
        const SizedBox(height: AppSpace.xxxl),
        Text(l10n.onbChooseLanguage, style: text.labelSmall),
        const SizedBox(height: AppSpace.md),
        // The device language comes first and keeps following the device.
        GlowButton(label: device.nativeName, icon: Icons.translate_rounded, onPressed: () => _chooseLanguage(null)),
        const SizedBox(height: AppSpace.xs),
        Text(l10n.deviceLanguage, style: text.bodySmall, textAlign: TextAlign.center),
        const SizedBox(height: AppSpace.lg),
        for (final m in LocaleRegistry.all.where((m) => m.locale != device.locale)) ...[
          OutlinedButton(
            onPressed: () => _chooseLanguage(m.locale),
            child: Text(m.nativeName, style: text.titleMedium),
          ),
          const SizedBox(height: AppSpace.md),
        ],
      ],
    );
  }

  Widget _identity(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.onbNameTitle, style: text.headlineSmall),
        const SizedBox(height: AppSpace.lg),
        TextField(
          controller: _name,
          autofocus: true,
          maxLength: 40,
          decoration: InputDecoration(labelText: l10n.onbNameHint),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AppSpace.lg),
        Text(l10n.onbSigilTitle, style: text.labelSmall),
        const SizedBox(height: AppSpace.md),
        Wrap(
          spacing: AppSpace.md,
          runSpacing: AppSpace.md,
          children: [
            for (final e in portraitGlyphs.entries)
              Semantics(
                selected: _portrait == e.key,
                button: true,
                label: e.key,
                child: InkResponse(
                  onTap: () => setState(() => _portrait = e.key),
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _portrait == e.key ? context.palette.accentContainer : context.palette.sunken,
                      border: Border.all(color: _portrait == e.key ? AppColors.ember : context.palette.hairline),
                    ),
                    child: Icon(e.value, color: context.palette.ink),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpace.xxl),
        GlowButton(onPressed: _name.text.trim().isEmpty ? null : _saveIdentity, label: l10n.actionContinue),
      ],
    );
  }

  Widget _areasStep(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.onbAreasTitle, style: text.headlineSmall),
        const SizedBox(height: AppSpace.sm),
        Text(l10n.onbAreasHelp, style: text.bodyMedium),
        const SizedBox(height: AppSpace.xl),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            for (final c in _areaChoices)
              FilterChip(
                avatar: AttributeSigil(c.defaultWeights.keys.first, size: 14),
                label: Text(l10n.categoryName(c)),
                selected: _areas.contains(c),
                onSelected: (sel) => setState(() {
                  if (sel && _areas.length < 3) {
                    _areas.add(c);
                  } else {
                    _areas.remove(c);
                  }
                }),
              ),
          ],
        ),
        const SizedBox(height: AppSpace.xxl),
        GlowButton(onPressed: _saveAreas, label: l10n.actionContinue),
        TextButton(onPressed: _next, child: Text(l10n.actionSkip)),
      ],
    );
  }

  Widget _firstQuest(BuildContext context) {
    final l10n = context.l10n;
    final f = ref.fmt(context);
    final text = Theme.of(context).textTheme;
    // Over the limit only while an input method is still composing.
    final tooLong = tooLongError(_quest.text, QuestLimits.titleMax, l10n, f);
    final ready = _quest.text.trim().isNotEmpty && tooLong == null && !_busy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.onbFirstQuestTitle, style: text.headlineSmall),
        const SizedBox(height: AppSpace.sm),
        Text(l10n.onbFirstQuestHelp, style: text.bodyMedium),
        const SizedBox(height: AppSpace.xl),
        TextField(
          controller: _quest,
          inputFormatters: const [StoredLengthLimit(QuestLimits.titleMax)],
          buildCounter: lengthCounter(_quest, QuestLimits.titleMax, f, quiet: true),
          decoration: InputDecoration(labelText: l10n.fieldTitle, hintText: l10n.fieldTitleHint, errorText: tooLong),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AppSpace.md),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            for (final s in _suggestions())
              ActionChip(label: Text(s), onPressed: () => setState(() => _quest.text = s)),
          ],
        ),
        const SizedBox(height: AppSpace.xxl),
        GlowButton(onPressed: ready ? () => _swear(completeNow: true) : null, label: l10n.onbCompleteNow),
        const SizedBox(height: AppSpace.sm),
        OutlinedButton(onPressed: ready ? () => _swear(completeNow: false) : null, child: Text(l10n.onbLater)),
      ],
    );
  }

  Widget _howItWorks(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpace.xl),
        Wrap(spacing: AppSpace.md, children: [for (final a in Attribute.values) AttributeSigil(a, size: 28)]),
        const SizedBox(height: AppSpace.xl),
        Text(l10n.onbHowItWorksTitle, style: text.headlineSmall),
        const SizedBox(height: AppSpace.md),
        Text(l10n.onbHowItWorksBody, style: text.bodyLarge),
        const SizedBox(height: AppSpace.xxl),
        GlowButton(onPressed: _finish, label: l10n.onbBegin),
      ],
    );
  }
}
