import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wyrd_engine/wyrd_engine.dart';

import '../../app/providers.dart';
import '../../data/ai/ai_client.dart';
import '../../data/ai/ai_evaluator.dart';
import '../../data/ai/ai_settings_repository.dart';
import '../../design/components/panel.dart';
import '../../design/tokens.dart';
import '../../l10n/content.dart';
import '../../l10n/generated/app_localizations.dart';
import '../auth/auth_widgets.dart' show asciiDigits;

String aiProviderLabel(AppLocalizations l10n, AiProviderKind k) => switch (k) {
  AiProviderKind.anthropic => l10n.aiProviderAnthropic,
  AiProviderKind.openai => l10n.aiProviderOpenai,
  AiProviderKind.gemini => l10n.aiProviderGemini,
  AiProviderKind.anthropicCompatible => l10n.aiProviderAnthropicCompatible,
  AiProviderKind.openaiCompatible => l10n.aiProviderOpenaiCompatible,
};

String aiErrorText(AppLocalizations l10n, AiException e) => switch (e.kind) {
  AiErrorKind.auth => l10n.aiErrAuth,
  AiErrorKind.rateLimited => l10n.aiErrRate,
  AiErrorKind.network => l10n.aiErrNetwork,
  AiErrorKind.refused => l10n.aiErrRefused,
  AiErrorKind.badResponse => l10n.aiErrBadResponse,
  AiErrorKind.http => l10n.aiErrHttp('${e.status ?? ''}'),
};

/// Connect your own AI provider: Anthropic, OpenAI, Google Gemini or any
/// service speaking the Anthropic or OpenAI protocol.
class AiProviderScreen extends ConsumerStatefulWidget {
  const AiProviderScreen({super.key});

  @override
  ConsumerState<AiProviderScreen> createState() => _AiProviderScreenState();
}

class _AiProviderScreenState extends ConsumerState<AiProviderScreen> {
  final _baseUrl = TextEditingController();
  final _model = TextEditingController();
  final _key = TextEditingController();
  final _baseUrlFocus = FocusNode();
  AiProviderKind _kind = AiProviderKind.anthropic;

  /// The provider as last saved, which the stored key belongs to.
  AiProviderConfig? _saved;

  /// Whether a key is stored; it counts only while [_saved] is the same
  /// service as the form ([AiSettingsRepository.sameService]).
  bool _hasKey = false;

  /// The address (scheme://host:port) a typed key was entered for. A typed
  /// key is only ever sent there; null until the address is complete.
  String? _keyOrigin;
  bool _busy = false;
  bool _loaded = false;
  String? _status;
  bool _statusOk = false;

  /// The provider's model list: null until fetched, or when there is no key
  /// to ask with ([_modelsNeedKey]) or the fetch failed ([_modelsError]).
  List<AiModelInfo>? _models;
  bool _modelsLoading = false;
  bool _modelsNeedKey = false;
  AiException? _modelsError;
  Timer? _modelsDebounce;

  /// Only the latest fetch may update the screen.
  int _modelsRequest = 0;

  static const _defaultModels = {AiProviderKind.anthropic: 'claude-opus-5-5'};

  @override
  void initState() {
    super.initState();
    // An address is finished when its field loses focus (Done, Tab or a tap
    // elsewhere). Asking part-way through typing would reach half-typed hosts.
    _baseUrlFocus.addListener(_onBaseUrlFocus);
    _load();
  }

  Future<void> _load() async {
    final repo = ref.read(aiSettingsRepositoryProvider);
    final config = await repo.config();
    bool hasKey;
    try {
      hasKey = await repo.hasKey();
    } on Object {
      hasKey = false;
    }
    if (!mounted) return;
    setState(() {
      if (config != null) {
        _kind = config.kind;
        _model.text = config.model;
        _baseUrl.text = config.baseUrl;
      } else {
        _model.text = _defaultModels[_kind] ?? '';
      }
      _saved = config;
      _hasKey = hasKey;
      _loaded = true;
    });
    unawaited(_loadModels());
  }

  /// scheme://host:port of the form's address, or null while it isn't a
  /// complete http(s) address.
  String? get _origin {
    final uri = Uri.tryParse(_config.effectiveBaseUrl);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https')) || uri.host.isEmpty) return null;
    return uri.origin;
  }

  /// The stored key belongs to the service in the form.
  bool get _keySaved => _hasKey && AiSettingsRepository.sameService(_saved, _config);

  void _onBaseUrlFocus() {
    // Only the user leaving the field finishes the address. Focus also goes
    // when the screen closes, a menu or sheet opens on top, or the app or
    // browser tab goes to the background, any of them part-way through.
    if (!mounted || _baseUrlFocus.hasFocus) return;
    if (ModalRoute.isCurrentOf(context) == false) return;
    final life = WidgetsBinding.instance.lifecycleState;
    if (life != null && life != AppLifecycleState.resumed) return;
    final origin = _origin;
    if (_key.text.trim().isNotEmpty) {
      if (_keyOrigin == null) {
        // The key was pasted before the address was complete: it is for this one.
        _keyOrigin = origin;
      } else if (origin != _keyOrigin) {
        // Another host: the typed key was meant for the old one.
        _key.clear();
        _keyOrigin = null;
      }
    }
    setState(() {});
    unawaited(_loadModels());
  }

  /// Fetches the model list once typing pauses.
  void _scheduleModels() {
    _modelsDebounce?.cancel();
    _modelsDebounce = Timer(const Duration(milliseconds: 800), () => unawaited(_loadModels()));
  }

  Future<void> _loadModels() async {
    _modelsDebounce?.cancel();
    if (!mounted) return;
    final request = ++_modelsRequest;
    final config = _config;
    if (config.kind.customEndpoint && !config.effectiveBaseUrl.startsWith(RegExp('https?://'))) {
      setState(() {
        _models = null;
        _modelsError = null;
        _modelsNeedKey = false;
        _modelsLoading = false;
      });
      return;
    }
    setState(() {
      _modelsLoading = true;
      _modelsError = null;
      _modelsNeedKey = false;
    });
    final typed = _key.text.trim();
    final origin = _origin;
    final apiKey = typed.isNotEmpty && origin != null && _keyOrigin == origin ? typed : null;
    List<AiModelInfo>? models;
    AiException? error;
    try {
      models = await ref.read(aiSettingsRepositoryProvider).listModels(config, apiKey: apiKey);
    } on AiException catch (e) {
      error = e;
    }
    if (!mounted || request != _modelsRequest) return;
    setState(() {
      _modelsLoading = false;
      _models = models;
      _modelsError = error;
      _modelsNeedKey = error == null && models == null;
    });
  }

  /// The service answered but has no model list to give, so asking again
  /// won't help.
  bool get _modelsUnsupported {
    final e = _modelsError;
    return e != null &&
        (e.kind == AiErrorKind.badResponse || (e.kind == AiErrorKind.http && (e.status == 404 || e.status == 405)));
  }

  /// What the model field says about the list.
  String _modelHelp(AppLocalizations l10n) {
    final models = _models;
    final error = _modelsError;
    if (_modelsLoading) return l10n.aiModelsLoading;
    if (error != null) {
      if (!_modelsUnsupported) return l10n.aiModelsFailed(aiErrorText(l10n, error));
      // A custom address that answers without a list is usually the wrong address.
      return _kind.customEndpoint ? l10n.aiModelsNoListAtAddress : l10n.aiModelsNoList;
    }
    if (_modelsNeedKey) return l10n.aiModelsNeedKey;
    if (models == null) return l10n.aiModelHint;
    if (models.isEmpty) return l10n.aiModelsEmpty;
    final current = bareModelId(_model.text);
    if (current.isNotEmpty && !models.any((m) => bareModelId(m.id) == current)) return l10n.aiModelNotListed;
    return l10n.aiModelsCount(models.length, ref.fmt(context).number(models.length));
  }

  /// One IconButton in every state, so keyboard and screen-reader focus
  /// survives a reload.
  Widget? _modelButton(AppLocalizations l10n) {
    if (_modelsLoading) {
      return IconButton(
        tooltip: l10n.aiModelsLoading,
        onPressed: () {},
        icon: const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_models?.isNotEmpty ?? false) {
      return IconButton(tooltip: l10n.aiModelChoose, icon: const Icon(Icons.arrow_drop_down), onPressed: _pickModel);
    }
    final canReload = (_modelsError != null && !_modelsUnsupported) || (_models?.isEmpty ?? false);
    if (!canReload) return null;
    return IconButton(tooltip: l10n.aiModelsReload, icon: const Icon(Icons.refresh), onPressed: _loadModels);
  }

  Future<void> _pickModel() async {
    final models = _models;
    if (models == null || models.isEmpty) return;
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _ModelPicker(models: models, current: _model.text.trim()),
    );
    if (picked == null || !mounted) return;
    setState(() => _model.text = picked);
  }

  @override
  void dispose() {
    _modelsDebounce?.cancel();
    _baseUrlFocus.dispose();
    _baseUrl.dispose();
    _model.dispose();
    _key.dispose();
    super.dispose();
  }

  AiProviderConfig get _config =>
      AiProviderConfig(kind: _kind, model: _model.text.trim(), baseUrl: _baseUrl.text.trim());

  Future<void> _save() async {
    setState(() => _busy = true);
    final repo = ref.read(aiSettingsRepositoryProvider);
    final config = _config;
    final typed = _key.text.trim();
    // A key typed for another address isn't saved with this one.
    final keyFits = typed.isNotEmpty && (_keyOrigin == null || _keyOrigin == _origin);
    await repo.save(config, apiKey: keyFits ? typed : null);
    bool hasKey;
    try {
      hasKey = await repo.hasKey();
    } on Object {
      hasKey = false;
    }
    _key.clear();
    _keyOrigin = null;
    if (!mounted) return;
    setState(() {
      _busy = false;
      _saved = config;
      _hasKey = hasKey;
      _status = context.l10n.aiSaved;
      _statusOk = true;
    });
  }

  /// Saves, then evaluates a sample quest end to end with the real provider.
  Future<void> _test() async {
    final l10n = context.l10n;
    await _save();
    setState(() => _busy = true);
    final repo = ref.read(aiSettingsRepositoryProvider);
    try {
      final client = await repo.client();
      if (client == null) {
        _status = l10n.aiTestFailed(l10n.aiErrNoKey);
        _statusOk = false;
        return;
      }
      final p = await AiEvaluator(client).evaluate(
        AiEvaluationInput(
          title: l10n.suggestStudy,
          tier: QuestTier.daily,
          declaredMinutes: 30,
          outputLanguage: ref.read(regionalProvider).locale.languageCode,
        ),
      );
      _status = l10n.aiTestOk(l10n.categoryName(p.category));
      _statusOk = true;
    } on AiException catch (e) {
      // A keyless custom service that wants a key: say so, not "rejected".
      _status = l10n.aiTestFailed(e.kind == AiErrorKind.auth && !_keySaved ? l10n.aiErrNoKey : aiErrorText(l10n, e));
      _statusOk = false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    await ref.read(aiSettingsRepositoryProvider).clear();
    if (mounted) context.canPop() ? context.pop() : context.go('/settings');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    // The same rule as the saved client: a model, and an http(s):// address.
    final ready = _config.isComplete;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.aiProvider),
        leading: context.canPop()
            ? null
            : IconButton(
                tooltip: l10n.actionClose,
                icon: const Icon(Icons.close),
                onPressed: () => context.go('/settings'),
              ),
      ),
      body: !_loaded
          ? const SizedBox.shrink()
          : Align(
              alignment: AlignmentDirectional.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: ListView(
                  padding: const EdgeInsetsDirectional.all(AppSpace.lg),
                  children: [
                    Text(l10n.aiProviderHelp, style: text.bodyMedium),
                    const SizedBox(height: AppSpace.lg),
                    Panel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          DropdownButtonFormField<AiProviderKind>(
                            initialValue: _kind,
                            isExpanded: true,
                            decoration: InputDecoration(labelText: l10n.aiProviderKind),
                            items: [
                              for (final k in AiProviderKind.values)
                                DropdownMenuItem(value: k, child: Text(aiProviderLabel(l10n, k))),
                            ],
                            onChanged: (k) {
                              if (k == null || k == _kind) return;
                              setState(() {
                                if (_model.text.trim().isEmpty || _model.text == _defaultModels[_kind]) {
                                  _model.text = _defaultModels[k] ?? '';
                                }
                                _kind = k;
                                // A key belongs to one service; never send it to another.
                                _key.clear();
                                _keyOrigin = null;
                                _models = null;
                              });
                              unawaited(_loadModels());
                            },
                          ),
                          if (_kind.customEndpoint) ...[
                            const SizedBox(height: AppSpace.md),
                            TextField(
                              controller: _baseUrl,
                              focusNode: _baseUrlFocus,
                              keyboardType: TextInputType.url,
                              textDirection: TextDirection.ltr,
                              onChanged: (_) {
                                // The list loads when the field is left; a pending
                                // key-field timer must not fire with a half-typed host,
                                // and the old address's list (or a late reply for it)
                                // no longer applies.
                                _modelsDebounce?.cancel();
                                _modelsRequest++;
                                setState(() {
                                  _models = null;
                                  _modelsError = null;
                                  _modelsNeedKey = false;
                                  _modelsLoading = false;
                                });
                              },
                              decoration: InputDecoration(labelText: l10n.aiBaseUrl, hintText: l10n.aiBaseUrlHint),
                            ),
                          ],
                          const SizedBox(height: AppSpace.md),
                          TextField(
                            controller: _model,
                            textDirection: TextDirection.ltr,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              labelText: l10n.aiModel,
                              helperText: _modelHelp(l10n),
                              helperMaxLines: 5,
                              suffixIcon: _modelButton(l10n),
                            ),
                          ),
                          const SizedBox(height: AppSpace.md),
                          TextField(
                            controller: _key,
                            obscureText: true,
                            autocorrect: false,
                            enableSuggestions: false,
                            textDirection: TextDirection.ltr,
                            onChanged: (_) {
                              _keyOrigin = _key.text.trim().isEmpty ? null : _origin;
                              setState(() {});
                              _scheduleModels();
                            },
                            decoration: InputDecoration(
                              labelText: l10n.aiApiKey,
                              helperText: _keySaved ? l10n.aiApiKeySaved : null,
                            ),
                          ),
                          if (kIsWeb) ...[
                            const SizedBox(height: AppSpace.sm),
                            Text(l10n.aiWebKeyNote, style: text.bodySmall),
                          ],
                          const SizedBox(height: AppSpace.lg),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _busy || !ready ? null : _test,
                                  child: Text(l10n.aiTest),
                                ),
                              ),
                              const SizedBox(width: AppSpace.md),
                              Expanded(
                                child: FilledButton(
                                  onPressed: _busy || !ready ? null : _save,
                                  child: Text(l10n.actionSave),
                                ),
                              ),
                            ],
                          ),
                          if (_busy) ...[const SizedBox(height: AppSpace.md), const LinearProgressIndicator()],
                          if (_status != null) ...[
                            const SizedBox(height: AppSpace.md),
                            Text(
                              _status!,
                              style: text.bodyMedium?.copyWith(
                                color: _statusOk ? context.palette.success : context.palette.accent,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpace.lg),
                    TextButton(onPressed: _remove, child: Text(l10n.aiRemove)),
                  ],
                ),
              ),
            ),
    );
  }
}

/// A searchable list of the provider's models; pops the chosen id.
class _ModelPicker extends StatefulWidget {
  const _ModelPicker({required this.models, required this.current});

  final List<AiModelInfo> models;
  final String current;

  @override
  State<_ModelPicker> createState() => _ModelPickerState();
}

class _ModelPickerState extends State<_ModelPicker> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // Persian keyboards type ۰–۹; model names use 0–9.
    final query = asciiDigits(_search.text).trim().toLowerCase();
    final shown = query.isEmpty
        ? widget.models
        : [
            for (final m in widget.models)
              if (m.id.toLowerCase().contains(query) || m.label.toLowerCase().contains(query)) m,
          ];
    final current = bareModelId(widget.current);
    // Latin names are laid out left to right but line up with the sheet's
    // start edge: for left-to-right text, that edge is its end in RTL.
    final align = Directionality.of(context) == TextDirection.rtl ? TextAlign.end : TextAlign.start;
    return Padding(
      padding: EdgeInsetsDirectional.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.lg, 0, AppSpace.lg, AppSpace.sm),
              child: Text(l10n.aiModelChoose, style: Theme.of(context).textTheme.titleMedium),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.symmetric(horizontal: AppSpace.lg),
              child: TextField(
                controller: _search,
                autocorrect: false,
                enableSuggestions: false,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: l10n.aiModelSearch),
              ),
            ),
            const SizedBox(height: AppSpace.sm),
            Expanded(
              child: shown.isEmpty
                  ? Center(child: Text(l10n.aiModelNoMatch))
                  : ListView.builder(
                      itemCount: shown.length,
                      itemBuilder: (context, i) {
                        final m = shown[i];
                        final selected = bareModelId(m.id) == current;
                        return ListTile(
                          selected: selected,
                          // The theme's default selected colour is too dark on the dark sheet.
                          selectedColor: context.palette.accent,
                          title: Text(m.label, textDirection: TextDirection.ltr, textAlign: align),
                          subtitle: m.label == m.id
                              ? null
                              : Text(m.id, textDirection: TextDirection.ltr, textAlign: align),
                          trailing: selected ? const Icon(Icons.check) : null,
                          onTap: () => Navigator.of(context).pop(m.id),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
