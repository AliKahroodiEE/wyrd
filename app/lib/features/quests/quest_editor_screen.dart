import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wyrd_engine/wyrd_engine.dart';

import '../../app/providers.dart';
import '../../data/db/database.dart';
import '../../data/models.dart';
import '../../design/components/date_picker.dart';
import '../../design/components/motion.dart';
import '../../design/components/panel.dart';
import '../../design/tokens.dart';
import '../../l10n/content.dart';
import '../reminders/reminder_coordinator.dart';
import 'complete_flow.dart';
import 'quest_limits.dart';
import 'quest_timer.dart';

/// Create or edit a quest with progressive disclosure (ux-spec §3).
class QuestEditorScreen extends ConsumerStatefulWidget {
  const QuestEditorScreen({super.key, this.questId, this.initialTier, this.parentId});

  final String? questId;
  final QuestTier? initialTier;
  final String? parentId;

  @override
  ConsumerState<QuestEditorScreen> createState() => _QuestEditorScreenState();
}

class _QuestEditorScreenState extends ConsumerState<QuestEditorScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _notes = TextEditingController();
  final _intention = TextEditingController();
  final _estimate = TextEditingController();
  final _more = ExpansibleController();
  late QuestTier _tier = widget.initialTier ?? QuestTier.daily;
  QuestCategory? _category;
  int _priority = 1;
  DateTime? _due;
  Recurrence _recurrence = Recurrence.none;
  ShareLevel _share = ShareLevel.private;
  int? _remindAt;
  late String? _parentId = widget.parentId;
  bool _loaded = false;
  bool _saving = false;
  Quest? _existing;

  bool get _editing => widget.questId != null;

  @override
  void initState() {
    super.initState();
    if (_editing) {
      unawaited(_load());
    } else {
      _loaded = true;
    }
  }

  Future<void> _load() async {
    final q = await ref.read(questRepositoryProvider).byId(widget.questId!);
    if (!mounted) return;
    if (q != null) {
      _existing = q;
      _title.text = q.title;
      _notes.text = q.notes;
      _intention.text = q.intention ?? '';
      _estimate.text = q.estimatedMinutes?.toString() ?? '';
      _tier = q.tier;
      _category = q.category;
      _priority = q.priority;
      _due = q.dueAt;
      _recurrence = q.recurrence;
      _share = q.shareLevel;
      _parentId = q.parentId;
      _remindAt = q.remindAt;
    }
    setState(() => _loaded = true);
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    _intention.dispose();
    _estimate.dispose();
    _more.dispose();
    super.dispose();
  }

  QuestDraft _draft() => QuestDraft(
    title: _title.text,
    tier: _tier,
    notes: _notes.text,
    category: _category,
    priority: _priority,
    dueAt: _due,
    estimatedMinutes: parseMinutes(_estimate.text),
    recurrence: _tier == QuestTier.objective ? Recurrence.none : _recurrence,
    intention: _intention.text,
    shareLevel: _share,
    parentId: _tier == QuestTier.objective ? null : _parentId,
    remindAt: _tier == QuestTier.objective ? null : _remindAt,
  );

  Future<void> _save() async {
    if (_saving) return;
    final invalid = _form.currentState!.validateGranularly();
    if (invalid.isNotEmpty) {
      unawaited(_reveal(invalid.first));
      return;
    }
    setState(() => _saving = true);
    final repo = ref.read(questRepositoryProvider);
    if (_editing) {
      await repo.update(widget.questId!, _draft());
    } else {
      await repo.create(_draft());
    }
    if (!mounted) return;
    context.canPop() ? context.pop() : context.go('/quests');
  }

  /// How long "More options" takes to open or close.
  Duration _unfolding(BuildContext context) => motion(context, AppMotion.base);

  /// Shows why a save was refused: opens "More options" when the field is
  /// folded away in it, then scrolls the field into view.
  Future<void> _reveal(FormFieldState<Object?> field) async {
    if (!_more.isExpanded && field.context.findAncestorWidgetOfExactType<ExpansionTile>() != null) {
      _more.expand();
      // Scrolling before the section has opened would stop short of it.
      await Future<void>.delayed(_unfolding(context));
    }
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !field.mounted) return;
    await Scrollable.ensureVisible(
      field.context,
      alignment: 0.2,
      duration: motion(context, AppMotion.settle),
      curve: AppMotion.standard,
    );
  }

  Future<void> _delete() async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l10n.deleteQuestTitle),
        content: Text(l10n.deleteQuestBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(l10n.actionCancel)),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(l10n.actionDelete)),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(questRepositoryProvider).delete(widget.questId!);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.questDeleted)));
    context.pop();
  }

  Future<void> _pickDate() async {
    final d = await showCalendarDatePicker(context, initial: _due);
    if (d != null) setState(() => _due = d);
  }

  Future<void> _pickReminder() async {
    final initial = _remindAt ?? 18 * 60;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initial ~/ 60, minute: initial % 60),
    );
    if (t == null) return;
    setState(() => _remindAt = t.hour * 60 + t.minute);
    // Ask for notification permission only when it is first needed.
    await ref.read(reminderSchedulerProvider).requestPermission();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final f = ref.fmt(context);
    final text = Theme.of(context).textTheme;
    if (!_loaded) return const Scaffold(body: SizedBox.shrink());
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final objectives = ref.watch(questsByTierProvider(QuestTier.objective)).value ?? const [];
    final timerRunning = _editing && ref.watch(questTimerProvider).containsKey(widget.questId);

    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? l10n.editQuest : l10n.newQuest),
        leading: context.canPop()
            ? null
            : IconButton(
                tooltip: l10n.actionClose,
                icon: const Icon(Icons.close),
                onPressed: () => context.go('/quests'),
              ),
        actions: [
          if (_editing)
            IconButton(tooltip: l10n.actionDelete, icon: const Icon(Icons.delete_outline), onPressed: _delete),
        ],
      ),
      body: Form(
        key: _form,
        child: Align(
          alignment: AlignmentDirectional.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            // A Column rather than a lazy list: every field stays built, so
            // saving checks the ones scrolled out of view too.
            child: SingleChildScrollView(
              padding: const EdgeInsetsDirectional.all(AppSpace.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _title,
                    autofocus: !_editing,
                    inputFormatters: const [StoredLengthLimit(QuestLimits.titleMax)],
                    buildCounter: lengthCounter(_title, QuestLimits.titleMax, f),
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _save(),
                    decoration: InputDecoration(labelText: l10n.fieldTitle, hintText: l10n.fieldTitleHint),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? l10n.fieldTitleRequired
                        : tooLongError(v, QuestLimits.titleMax, l10n, f),
                  ),
                  const SizedBox(height: AppSpace.md),
                  Text(l10n.fieldTier, style: text.labelMedium),
                  const SizedBox(height: AppSpace.sm),
                  SegmentedButton<QuestTier>(
                    showSelectedIcon: false,
                    segments: [
                      for (final t in QuestTier.values)
                        ButtonSegment(
                          value: t,
                          label: Text(l10n.tierName(t), textAlign: TextAlign.center),
                        ),
                    ],
                    selected: {_tier},
                    onSelectionChanged: (s) => setState(() => _tier = s.first),
                  ),
                  const SizedBox(height: AppSpace.xs),
                  Text(l10n.tierHelp(_tier), style: text.bodySmall),
                  const SizedBox(height: AppSpace.lg),
                  Text(l10n.fieldDue, style: text.labelMedium),
                  const SizedBox(height: AppSpace.sm),
                  Wrap(
                    spacing: AppSpace.sm,
                    runSpacing: AppSpace.sm,
                    children: [
                      ChoiceChip(
                        label: Text(l10n.fieldDueNone),
                        selected: _due == null,
                        onSelected: (_) => setState(() => _due = null),
                      ),
                      ChoiceChip(
                        label: Text(l10n.dueToday),
                        selected: _due != null && DateUtils.isSameDay(_due, today),
                        onSelected: (_) => setState(() => _due = today),
                      ),
                      ChoiceChip(
                        label: Text(l10n.dueTomorrow),
                        selected: _due != null && DateUtils.isSameDay(_due, today.add(const Duration(days: 1))),
                        onSelected: (_) => setState(() => _due = today.add(const Duration(days: 1))),
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.calendar_month_outlined, size: 16),
                        label: Text(
                          _due != null &&
                                  !DateUtils.isSameDay(_due, today) &&
                                  !DateUtils.isSameDay(_due, today.add(const Duration(days: 1)))
                              ? f.date(_due!)
                              : l10n.fieldDue,
                        ),
                        onPressed: _pickDate,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpace.lg),
                  TextFormField(
                    controller: _intention,
                    inputFormatters: const [StoredLengthLimit(QuestLimits.intentionMax)],
                    buildCounter: lengthCounter(_intention, QuestLimits.intentionMax, f, quiet: true),
                    // Always, so an intention saved before the limit says so when opened.
                    autovalidateMode: AutovalidateMode.always,
                    validator: (v) => tooLongError(v ?? '', QuestLimits.intentionMax, l10n, f),
                    decoration: InputDecoration(
                      labelText: l10n.fieldIntention,
                      hintText: l10n.fieldIntentionHint,
                      helperText: l10n.fieldIntentionHelp,
                    ),
                  ),
                  if (_tier != QuestTier.objective)
                    ListTile(
                      contentPadding: EdgeInsetsDirectional.zero,
                      leading: const Icon(Icons.notifications_none_outlined),
                      title: Text(l10n.fieldReminder),
                      subtitle: Text(
                        _remindAt == null
                            ? l10n.reminderNone
                            : f.digits(
                                '${(_remindAt! ~/ 60).toString().padLeft(2, '0')}:'
                                '${(_remindAt! % 60).toString().padLeft(2, '0')}',
                              ),
                      ),
                      trailing: _remindAt == null
                          ? null
                          : IconButton(
                              tooltip: l10n.reminderClear,
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () => setState(() => _remindAt = null),
                            ),
                      onTap: _pickReminder,
                    ),
                  const SizedBox(height: AppSpace.md),
                  Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      controller: _more,
                      tilePadding: EdgeInsetsDirectional.zero,
                      initiallyExpanded: _editing,
                      // Folded fields stay in the form, so saving still checks them.
                      maintainState: true,
                      expansionAnimationStyle: AnimationStyle(duration: _unfolding(context)),
                      title: Text(l10n.moreOptions, style: text.labelLarge),
                      childrenPadding: const EdgeInsetsDirectional.only(bottom: AppSpace.md),
                      children: [
                        TextFormField(
                          controller: _estimate,
                          keyboardType: TextInputType.number,
                          autovalidateMode: AutovalidateMode.always,
                          validator: (v) => estimateError(v ?? '', l10n, f),
                          decoration: InputDecoration(labelText: l10n.fieldEstimate),
                        ),
                        const SizedBox(height: AppSpace.md),
                        if (_tier != QuestTier.objective) ...[
                          DropdownButtonFormField<Recurrence>(
                            initialValue: _recurrence,
                            decoration: InputDecoration(labelText: l10n.fieldRecurrence),
                            items: [
                              DropdownMenuItem(value: Recurrence.none, child: Text(l10n.recurrenceNone)),
                              DropdownMenuItem(value: Recurrence.daily, child: Text(l10n.recurrenceDaily)),
                              DropdownMenuItem(value: Recurrence.weekdays, child: Text(l10n.recurrenceWeekdays)),
                              DropdownMenuItem(value: Recurrence.weekly, child: Text(l10n.recurrenceWeekly)),
                            ],
                            onChanged: (v) => setState(() => _recurrence = v ?? Recurrence.none),
                          ),
                          const SizedBox(height: AppSpace.md),
                        ],
                        DropdownButtonFormField<QuestCategory?>(
                          initialValue: _category,
                          decoration: InputDecoration(labelText: l10n.fieldCategory),
                          items: [
                            DropdownMenuItem(value: null, child: Text(l10n.categoryAuto)),
                            for (final c in QuestCategory.values)
                              DropdownMenuItem(value: c, child: Text(l10n.categoryName(c))),
                          ],
                          onChanged: (v) => setState(() => _category = v),
                        ),
                        const SizedBox(height: AppSpace.md),
                        Text(l10n.fieldPriority, style: text.labelMedium),
                        const SizedBox(height: AppSpace.sm),
                        SegmentedButton<int>(
                          showSelectedIcon: false,
                          segments: [
                            ButtonSegment(value: 0, label: Text(l10n.priorityLow)),
                            ButtonSegment(value: 1, label: Text(l10n.priorityNormal)),
                            ButtonSegment(value: 2, label: Text(l10n.priorityHigh)),
                          ],
                          selected: {_priority},
                          onSelectionChanged: (s) => setState(() => _priority = s.first),
                        ),
                        const SizedBox(height: AppSpace.md),
                        if (_tier != QuestTier.objective && objectives.isNotEmpty) ...[
                          DropdownButtonFormField<String?>(
                            initialValue: objectives.any((o) => o.quest.id == _parentId) ? _parentId : null,
                            decoration: InputDecoration(labelText: l10n.fieldParent),
                            items: [
                              DropdownMenuItem(value: null, child: Text(l10n.parentNone)),
                              for (final o in objectives)
                                DropdownMenuItem(
                                  value: o.quest.id,
                                  child: Text(o.quest.title, overflow: TextOverflow.ellipsis),
                                ),
                            ],
                            onChanged: (v) => setState(() => _parentId = v),
                          ),
                          const SizedBox(height: AppSpace.md),
                        ],
                        DropdownButtonFormField<ShareLevel>(
                          initialValue: _share,
                          decoration: InputDecoration(labelText: l10n.fieldSharing),
                          items: [
                            DropdownMenuItem(value: ShareLevel.private, child: Text(l10n.share_private)),
                            DropdownMenuItem(value: ShareLevel.completionOnly, child: Text(l10n.share_completionOnly)),
                            DropdownMenuItem(value: ShareLevel.titleOnly, child: Text(l10n.share_titleOnly)),
                            DropdownMenuItem(value: ShareLevel.full, child: Text(l10n.share_full)),
                          ],
                          onChanged: (v) => setState(() => _share = v ?? ShareLevel.private),
                        ),
                        const SizedBox(height: AppSpace.md),
                        TextFormField(
                          controller: _notes,
                          minLines: 2,
                          maxLines: 6,
                          inputFormatters: const [StoredLengthLimit(QuestLimits.notesMax)],
                          buildCounter: lengthCounter(_notes, QuestLimits.notesMax, f),
                          autovalidateMode: AutovalidateMode.always,
                          validator: (v) => tooLongError(v ?? '', QuestLimits.notesMax, l10n, f),
                          decoration: InputDecoration(labelText: l10n.fieldNotes),
                        ),
                      ],
                    ),
                  ),
                  if (_editing && _existing != null && _existing!.tier != QuestTier.objective) ...[
                    _SubtasksPanel(questId: widget.questId!),
                    const SizedBox(height: AppSpace.lg),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          icon: Icon(timerRunning ? Icons.stop_circle_outlined : Icons.timer_outlined, size: 18),
                          label: Text(timerRunning ? l10n.timerStop : l10n.timerStart),
                          onPressed: () {
                            final timers = ref.read(questTimerProvider.notifier);
                            timerRunning ? timers.cancel(widget.questId!) : timers.start(widget.questId!);
                          },
                        ),
                        const Spacer(),
                        if (_existing!.status == QuestStatus.active)
                          TextButton.icon(
                            icon: const Icon(Icons.check_circle_outline, size: 18),
                            label: Text(l10n.completeQuest),
                            onPressed: () async {
                              final outcome = await completeQuest(context, ref, _existing!);
                              if (outcome != null && context.mounted && !_existing!.isRecurring) {
                                context.pop();
                              }
                            },
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: AppSpace.xl),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: Text(_editing ? l10n.saveChanges : l10n.swearQuest),
                  ),
                  const SizedBox(height: AppSpace.xl),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SubtasksPanel extends ConsumerStatefulWidget {
  const _SubtasksPanel({required this.questId});
  final String questId;

  @override
  ConsumerState<_SubtasksPanel> createState() => _SubtasksPanelState();
}

class _SubtasksPanelState extends ConsumerState<_SubtasksPanel> {
  final _controller = TextEditingController();
  late final Stream<List<SubtaskRow>> _stream = ref.read(questRepositoryProvider).watchSubtasks(widget.questId);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final t = _controller.text.trim();
    // Over the limit only while an input method is still composing; the
    // field says so, and the step waits until it fits.
    if (t.isEmpty || t.length > QuestLimits.titleMax) return;
    _controller.clear();
    await ref.read(questRepositoryProvider).addSubtask(widget.questId, t);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final f = ref.fmt(context);
    final repo = ref.read(questRepositoryProvider);
    return Panel(
      title: l10n.subtasks,
      padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.lg, AppSpace.md, AppSpace.md),
      child: StreamBuilder<List<SubtaskRow>>(
        stream: _stream,
        builder: (context, snapshot) {
          final items = snapshot.data ?? const [];
          return Column(
            children: [
              for (final s in items)
                CheckboxListTile(
                  value: s.done,
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsetsDirectional.zero,
                  title: Text(s.title),
                  onChanged: (v) => repo.setSubtaskDone(s.id, v ?? false),
                  secondary: IconButton(
                    tooltip: l10n.actionDelete,
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => repo.deleteSubtask(s.id),
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: ListenableBuilder(
                      listenable: _controller,
                      builder: (context, _) => TextField(
                        controller: _controller,
                        inputFormatters: const [StoredLengthLimit(QuestLimits.titleMax)],
                        buildCounter: lengthCounter(_controller, QuestLimits.titleMax, f, quiet: true),
                        onSubmitted: (_) => _add(),
                        decoration: InputDecoration(
                          hintText: l10n.subtaskHint,
                          isDense: true,
                          errorText: tooLongError(_controller.text, QuestLimits.titleMax, l10n, f),
                        ),
                      ),
                    ),
                  ),
                  IconButton(tooltip: l10n.addSubtask, icon: const Icon(Icons.add), onPressed: _add),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
