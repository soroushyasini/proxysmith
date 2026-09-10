import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:qr_flutter/qr_flutter.dart';

import '../app_version.dart';
import '../l10n/app_localizations.dart';
import '../main.dart';
import '../models/app_settings.dart';
import '../models/config_source.dart';
import '../models/pipeline_options.dart';
import '../services/pipeline_event.dart';
import '../services/pipeline_service.dart';
import '../services/source_storage.dart';
import '../theme/app_theme.dart';
import '../widgets/labeled_switch.dart';
import '../widgets/legionary_logo.dart';
import '../widgets/options_menu.dart';
import '../widgets/proxy_result_card.dart';
import '../widgets/stage_progress.dart';

class PipelineScreen extends StatefulWidget {
  const PipelineScreen({super.key});

  @override
  State<PipelineScreen> createState() => _PipelineScreenState();
}

class _PipelineScreenState extends State<PipelineScreen> {
  List<ConfigSource> _sources = [...kBuiltInSources, kCustomUrlSource];
  ConfigSource _source = kBuiltInSources.first;
  final _customUrlController = TextEditingController();
  final _testUrlController = TextEditingController(
    text: AppSettings.defaults.testUrl,
  );
  late final PipelineService _pipeline;
  StreamSubscription<PipelineEvent>? _events;
  bool _initialized = false;
  bool _showValidationErrors = false;

  int _testCount = AppSettings.defaults.testCount;
  int _maxPingMs = AppSettings.defaults.maxPingMs;
  int _concurrency = AppSettings.defaults.concurrency;
  String _testUrl = AppSettings.defaults.testUrl;

  bool _running = false;
  String _statusKey = 'ready';
  Map<String, Object?> _statusArgs = const {};
  double _progress = 0;
  int _round = 0;
  int _done = 0;
  int _total = 0;
  int _fetched = 0;
  String? _warning;
  final List<Map<String, Object>> _results = [];
  bool _selecting = false;
  final Set<int> _selected = {};

  @override
  void initState() {
    super.initState();
    _pipeline = PipelineService.create();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final settings = ProxySmithApp.of(context).settings;
    _testCount = settings.testCount;
    _maxPingMs = settings.maxPingMs;
    _concurrency = settings.concurrency;
    _testUrl = settings.testUrl;
    _testUrlController.text = settings.testUrl;
    unawaited(_loadSources(preferredId: settings.selectedSourceId));
  }

  Future<void> _loadSources({String? preferredId}) async {
    final custom = await SourceStorage.loadUserSources();
    if (!mounted) return;
    final all = [...kBuiltInSources, ...custom, kCustomUrlSource];
    final wanted = preferredId ?? _source.storageId;
    final selected = all.firstWhere(
      (item) => item.storageId == wanted,
      orElse: () => all.first,
    );
    setState(() {
      _sources = all;
      _source = selected;
    });
  }

  @override
  void dispose() {
    _events?.cancel();
    _customUrlController.dispose();
    _testUrlController.dispose();
    super.dispose();
  }

  String get _subscriptionUrl =>
      _source.isCustom ? _customUrlController.text.trim() : _source.url!;

  PipelineOptions get _options => PipelineOptions(
    subUrl: _subscriptionUrl,
    testCount: _testCount,
    maxPingMs: _maxPingMs,
    concurrency: _concurrency,
    testUrl: _testUrl.trim(),
  );

  void _persistRunSettings() {
    final app = ProxySmithApp.of(context);
    app.updateSettings(
      app.settings.copyWith(
        selectedSourceId: _source.storageId,
        testCount: _testCount,
        maxPingMs: _maxPingMs,
        concurrency: _concurrency,
        testUrl: _testUrl.trim(),
      ),
    );
  }

  Future<void> _start() async {
    if (_options.validationError != null) {
      setState(() {
        _showValidationErrors = true;
        _statusKey = 'invalidOptions';
        _statusArgs = const {};
      });
      return;
    }
    _persistRunSettings();
    setState(() {
      _showValidationErrors = false;
      _running = true;
      _statusKey = 'statusFetching';
      _statusArgs = const {};
      _progress = 0;
      _round = _done = _total = _fetched = 0;
      _warning = null;
      _results.clear();
      _selecting = false;
      _selected.clear();
    });
    final maxDoneByRound = <int, int>{};
    await _events?.cancel();
    _events = _pipeline
        .start(_options)
        .listen(
          (event) {
            if (!mounted) return;
            setState(() {
              switch (event) {
                case StatusEvent(:final message):
                  if (message == 'stopped') _statusKey = 'statusStopped';
                case FetchedEvent(:final count):
                  _fetched = count;
                  _statusKey = 'statusFetched';
                  _statusArgs = {'count': count};
                case ProgressEvent(:final round, :final done, :final total):
                  _round = round;
                  _done = maxDoneByRound.update(
                    round,
                    (old) => done > old ? done : old,
                    ifAbsent: () => done,
                  );
                  _total = total;
                  _statusKey = 'statusRound$round';
                  final fraction = total == 0 ? 0.0 : _done / total;
                  _progress = switch (round) {
                    1 => fraction * .7,
                    2 => .7 + fraction * .2,
                    3 => .9 + fraction * .1,
                    _ => _progress,
                  };
                case WarningEvent(:final message):
                  _warning = message;
                case ResultEvent(
                  :final rank,
                  :final ms,
                  :final jitterMs,
                  :final successes,
                  :final attempts,
                  :final uri,
                ):
                  final result = <String, Object>{
                    'uri': uri,
                    'ms': ms,
                    'jitterMs': jitterMs,
                    'successes': successes,
                    'attempts': attempts,
                  };
                  if (_results.length < rank) {
                    _results.add(result);
                  } else {
                    _results[rank - 1] = result;
                  }
                case DoneEvent(:final count, :final elapsedMs):
                  _progress = 1;
                  _running = false;
                  _statusKey = 'statusDone';
                  _statusArgs = {'count': count, 'elapsedMs': elapsedMs};
                case ErrorEvent(:final message, :final code):
                  _running = false;
                  _statusKey = switch (code) {
                    'EMPTY_BODY' => 'errorEmptyBody',
                    'DECODE_FAILURE' => 'errorDecodeFailure',
                    'NO_VALID_SCHEMES' => 'errorNoValidSchemes',
                    'SUBSCRIPTION_TOO_LARGE' => 'errorSubscriptionTooLarge',
                    'NO_RESULTS' => 'errorNoResults',
                    'NETWORK_ERROR' => 'errorNetwork',
                    'PIPELINE_TIMEOUT' => 'errorTimeout',
                    'INVALID_OPTIONS' => 'invalidOptions',
                    _ => 'errorGeneric',
                  };
                  _statusArgs = {'message': message, 'minutes': 10};
              }
            });
          },
          onError: (Object error) {
            if (!mounted) return;
            setState(() {
              _running = false;
              _statusKey = 'errorGeneric';
              _statusArgs = {'message': error.toString()};
            });
          },
          onDone: () {
            if (mounted && _running) setState(() => _running = false);
          },
        );
  }

  Future<void> _stop() async {
    await _pipeline.stop();
    if (!mounted) return;
    setState(() {
      _running = false;
      _statusKey = 'statusStopped';
      _statusArgs = const {};
    });
  }

  String _status(AppLocalizations l10n) {
    switch (_statusKey) {
      case 'statusFetching':
        return l10n.statusFetching;
      case 'statusFetched':
        return l10n.statusFetched(_statusArgs['count'] as int? ?? 0);
      case 'statusRound1':
        return '${l10n.statusRound1} · ${l10n.statusProgress(_done, _total)}';
      case 'statusRound2':
        return '${l10n.statusRound2} · ${l10n.statusProgress(_done, _total)}';
      case 'statusRound3':
        return '${l10n.statusRound3} · ${l10n.statusProgress(_done, _total)}';
      case 'statusDone':
        final count = _statusArgs['count'] as int? ?? 0;
        final elapsed = _statusArgs['elapsedMs'] as int?;
        return elapsed == null
            ? l10n.statusDone(count)
            : l10n.statusDoneTimed(count, (elapsed / 1000).round());
      case 'statusStopped':
        return l10n.statusStopped;
      case 'errorEmptyBody':
        return l10n.errorEmptyBody;
      case 'errorDecodeFailure':
        return l10n.errorDecodeFailure;
      case 'errorNoValidSchemes':
        return l10n.errorNoValidSchemes;
      case 'errorSubscriptionTooLarge':
        return l10n.errorSubscriptionTooLarge;
      case 'errorNoResults':
        return l10n.errorNoResults;
      case 'errorNetwork':
        return l10n.errorNetwork(_statusArgs['message'] as String? ?? '');
      case 'errorTimeout':
        return l10n.errorTimeout(_statusArgs['minutes'] as int? ?? 10);
      case 'invalidOptions':
        return l10n.errorInvalidOptions;
      case 'errorGeneric':
        return l10n.errorGeneric(_statusArgs['message'] as String? ?? '');
      default:
        return l10n.statusReady;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).extension<ProxySmithColors>()!;
    final app = ProxySmithApp.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _topBar(l10n, app),
              const SizedBox(height: 12),
              _inputs(l10n, colors, app),
              const SizedBox(height: 10),
              if (_running || _fetched > 0)
                StageProgress(
                  progress: _progress,
                  round: _round,
                  statusText: _status(l10n),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 8,
                  ),
                  child: Text(
                    _status(l10n),
                    style: TextStyle(color: colors.mutedText),
                  ),
                ),
              const SizedBox(height: 8),
              SizedBox(
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _running ? _stop : _start,
                  style: _running
                      ? ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.error,
                        )
                      : null,
                  icon: Icon(
                    _running ? Icons.stop_rounded : Icons.play_arrow_rounded,
                  ),
                  label: Text(_running ? l10n.stopButton : l10n.runButton),
                ),
              ),
              if (_warning != null) ...[
                const SizedBox(height: 8),
                _warningBanner(l10n, colors),
              ],
              const SizedBox(height: 12),
              _resultsHeader(l10n),
              const SizedBox(height: 6),
              Expanded(child: _resultsList(l10n, colors)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar(AppLocalizations l10n, ProxySmithAppState app) => Row(
    children: [
      const LegionaryLogo(size: 34),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.appName, style: Theme.of(context).textTheme.titleMedium),
            Text(
              l10n.appTagline,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      OptionsMenuButton(
        currentVersion: kAppVersion,
        onSourcesChanged: _loadSources,
      ),
    ],
  );

  Widget _inputs(
    AppLocalizations l10n,
    ProxySmithColors colors,
    ProxySmithAppState app,
  ) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              LabeledSwitch(
                leftLabel: 'EN',
                rightLabel: 'FA',
                value: app.locale.languageCode == 'fa',
                onChanged: (value) =>
                    app.setLocale(Locale(value ? 'fa' : 'en')),
              ),
              LabeledSwitch(
                leftLabel: l10n.themeLight,
                rightLabel: l10n.themeDark,
                leftIcon: Icons.light_mode_rounded,
                rightIcon: Icons.dark_mode_rounded,
                value: app.themeMode == ThemeMode.dark,
                onChanged: app.toggleTheme,
              ),
            ],
          ),
          const Divider(height: 22),
          LayoutBuilder(
            builder: (context, constraints) {
              final source = _sourceField(l10n, colors);
              final count = _numberField(
                l10n.testCountLabel,
                _testCount,
                50,
                5000,
                (value) => setState(() => _testCount = value),
                colors,
              );
              if (constraints.maxWidth < 390) {
                return Column(
                  children: [source, const SizedBox(height: 10), count],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: source),
                  const SizedBox(width: 10),
                  Expanded(flex: 2, child: count),
                ],
              );
            },
          ),
          if (_source.isCustom) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _customUrlController,
              enabled: !_running,
              keyboardType: TextInputType.url,
              autocorrect: false,
              onChanged: (_) {
                if (_showValidationErrors) setState(() {});
              },
              decoration: InputDecoration(
                labelText: l10n.sourceCustomUrl,
                hintText: l10n.sourceCustomUrlHint,
                errorText:
                    _showValidationErrors && !_isHttpUrl(_subscriptionUrl)
                    ? l10n.sourcesUrlInvalid
                    : null,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
          const SizedBox(height: 4),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            title: Text(
              l10n.advancedSettings,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            children: [
              _numberField(
                l10n.maxLatencyLabel,
                _maxPingMs,
                500,
                60000,
                (value) => setState(() => _maxPingMs = value),
                colors,
              ),
              const SizedBox(height: 10),
              _numberField(
                l10n.concurrencyLabel,
                _concurrency,
                1,
                60,
                (value) => setState(() => _concurrency = value),
                colors,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _testUrlController,
                enabled: !_running,
                keyboardType: TextInputType.url,
                autocorrect: false,
                onChanged: (value) => setState(() => _testUrl = value),
                decoration: InputDecoration(
                  labelText: l10n.testEndpointLabel,
                  hintText: 'https://example.com/generate_204',
                  errorText: _showValidationErrors && !_isHttpUrl(_testUrl)
                      ? l10n.sourcesUrlInvalid
                      : null,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  bool _isHttpUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    return uri != null &&
        uri.host.isNotEmpty &&
        (uri.scheme == 'http' || uri.scheme == 'https');
  }

  Widget _sourceField(AppLocalizations l10n, ProxySmithColors colors) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        l10n.configSourceLabel,
        style: TextStyle(fontSize: 11, color: colors.mutedText),
      ),
      const SizedBox(height: 6),
      DropdownButtonFormField<ConfigSource>(
        initialValue: _source,
        isExpanded: true,
        menuMaxHeight: 320,
        decoration: const InputDecoration(border: OutlineInputBorder()),
        items: _sources
            .map(
              (source) => DropdownMenuItem(
                value: source,
                child: Text(
                  source.isCustom ? l10n.sourceCustomUrl : source.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
            .toList(),
        onChanged: _running
            ? null
            : (source) {
                if (source == null) return;
                setState(() => _source = source);
                _persistRunSettings();
              },
      ),
    ],
  );

  Widget _numberField(
    String label,
    int value,
    int step,
    int max,
    ValueChanged<int> changed,
    ProxySmithColors colors,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(label, style: TextStyle(fontSize: 11, color: colors.mutedText)),
      const SizedBox(height: 6),
      Container(
        height: 50,
        decoration: BoxDecoration(
          border: Border.all(color: colors.cardBorder),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            IconButton(
              tooltip: '-',
              onPressed: !_running && value - step >= (step == 500 ? 0 : 1)
                  ? () => changed(value - step)
                  : null,
              icon: const Icon(Icons.remove_rounded),
            ),
            Expanded(
              child: Text(
                '$value',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(
              tooltip: '+',
              onPressed: !_running && value + step <= max
                  ? () => changed(value + step)
                  : null,
              icon: const Icon(Icons.add_rounded),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _warningBanner(AppLocalizations l10n, ProxySmithColors colors) =>
      Material(
        color: const Color(0xFFFEF3E0),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsetsDirectional.only(start: 12),
          child: Row(
            children: [
              const Icon(Icons.info_outline_rounded, color: Color(0xFF9A6820)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.warningPartialResults(_warning!),
                  style: const TextStyle(color: Color(0xFF755018)),
                ),
              ),
              IconButton(
                tooltip: l10n.dismissButton,
                onPressed: () => setState(() => _warning = null),
                icon: const Icon(Icons.close_rounded, color: Color(0xFF9A6820)),
              ),
            ],
          ),
        ),
      );

  Widget _resultsHeader(AppLocalizations l10n) => Row(
    children: [
      Expanded(
        child: Text(
          _selecting ? l10n.selectedCount(_selected.length) : l10n.resultsTitle,
          style: Theme.of(context).textTheme.titleSmall,
        ),
      ),
      if (_results.isNotEmpty && !_selecting)
        TextButton(
          onPressed: () => setState(() => _selecting = true),
          child: Text(l10n.selectButton),
        ),
      if (_results.isNotEmpty)
        TextButton.icon(
          onPressed: _selecting
              ? (_selected.isEmpty ? null : () => _copySelected(l10n))
              : () => _copyAll(l10n),
          icon: const Icon(Icons.copy_all_rounded),
          label: Text(_selecting ? l10n.copySelected : l10n.copyAll),
        ),
      if (_selecting)
        IconButton(
          tooltip: l10n.cancelSelection,
          onPressed: () => setState(() {
            _selecting = false;
            _selected.clear();
          }),
          icon: const Icon(Icons.close_rounded),
        ),
    ],
  );

  Widget _resultsList(AppLocalizations l10n, ProxySmithColors colors) {
    if (_results.isEmpty) {
      return LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.speed_rounded, size: 42, color: colors.mutedText),
                  const SizedBox(height: 8),
                  Text(l10n.noResultsYet),
                  Text(
                    l10n.noResultsHint,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.mutedText),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return ListView.builder(
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final result = _results[index];
        return ProxyResultCard(
          rank: index + 1,
          ms: result['ms']! as int,
          jitterMs: result['jitterMs']! as int,
          successes: result['successes']! as int,
          attempts: result['attempts']! as int,
          uri: result['uri']! as String,
          selectionMode: _selecting,
          selected: _selected.contains(index),
          onSelectedChanged: (_) => setState(
            () => _selected.contains(index)
                ? _selected.remove(index)
                : _selected.add(index),
          ),
          onTap: () => _copyOne(result['uri']! as String, index, l10n),
          onShowQr: () => _showQr(result['uri']! as String, index, l10n),
          qrTooltip: l10n.qrButton,
        );
      },
    );
  }

  void _copyAll(AppLocalizations l10n) => _copy(
    _results.map((item) => item['uri']! as String).join('\n'),
    l10n.copiedAll(_results.length),
  );

  void _copySelected(AppLocalizations l10n) {
    final ordered = _selected.toList()..sort();
    _copy(
      ordered.map((index) => _results[index]['uri']! as String).join('\n'),
      l10n.copiedAll(ordered.length),
    );
  }

  void _copyOne(String uri, int index, AppLocalizations l10n) =>
      _copy(uri, l10n.copiedOne(index + 1));

  void _copy(String text, String confirmation) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(confirmation)));
  }

  void _showQr(String uri, int index, AppLocalizations l10n) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.resultQrTitle(index + 1)),
        content: SizedBox.square(
          dimension: 240,
          child: QrImageView(data: uri, backgroundColor: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.closeButton),
          ),
        ],
      ),
    );
  }
}
