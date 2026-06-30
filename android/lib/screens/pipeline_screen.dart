import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n/app_localizations.dart';
import '../main.dart';
import '../models/config_source.dart';
import '../services/pipeline_bridge.dart';
import '../theme/app_theme.dart';
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
  ConfigSource _selectedSource = kConfigSources.first;
  final _customUrlCtrl = TextEditingController();
  int _testCount = 200;

  bool _running = false;
  String _statusKey = 'ready'; // semantic key, resolved to text at build time
  Map<String, dynamic>? _statusArgs;
  double _progress = 0;
  int _round = 0;
  int _done = 0;
  int _total = 0;
  String? _warningMessage;

  List<Map<String, dynamic>> _results = [];

  StreamSubscription? _eventSub;

  @override
  void dispose() {
    _eventSub?.cancel();
    _customUrlCtrl.dispose();
    super.dispose();
  }

  String get _effectiveUrl =>
      _selectedSource.isCustom ? _customUrlCtrl.text.trim() : _selectedSource.url!;

  // ── Start ──────────────────────────────────────────────────────────────
  Future<void> _start() async {
    setState(() {
      _running = true;
      _statusKey = 'statusFetching';
      _statusArgs = null;
      _progress = 0;
      _results = [];
      _round = 0;
      _done = 0;
      _total = 0;
      _warningMessage = null;
    });

    await _eventSub?.cancel();
    _eventSub = PipelineBridge.eventChannel.receiveBroadcastStream().listen(
      (event) {
        final e = Map<String, dynamic>.from(event as Map);
        final type = e['type'] as String;
        final data = e['data'];

        if (!mounted) return;

        setState(() {
          switch (type) {
            case 'status':
              // Backend sends free-text dev-facing status; we map known
              // ones to localized keys and ignore the rest for display
              // (they're still useful if the user enables verbose logs).
              final s = data as String;
              if (s.contains('done')) {
                _statusKey = 'statusDone';
                _statusArgs = {'count': _results.length};
              } else if (s == 'stopped') {
                _statusKey = 'statusStopped';
              }
            case 'fetched':
              _total = data as int;
              _statusKey = 'statusFetched';
              _statusArgs = {'count': _total};
            case 'progress':
              final p = Map<String, dynamic>.from(data as Map);
              _round = p['round'] as int;
              _done = p['done'] as int;
              _total = p['total'] as int;
              _statusKey = switch (_round) {
                1 => 'statusRound1',
                2 => 'statusRound2',
                3 => 'statusRound3',
                _ => _statusKey,
              };
              _progress = switch (_round) {
                1 => (_done / _total) * 0.7,
                2 => 0.7 + (_done / _total) * 0.2,
                3 => 0.9 + (_done / _total) * 0.1,
                _ => _progress,
              };
            case 'warning':
              _warningMessage = data as String;
          }
        });
      },
      onError: (error) {
        if (!mounted) return;
        setState(() {
          _statusKey = 'errorGeneric';
          _statusArgs = {'message': error.toString()};
        });
      },
    );

    try {
      final raw = await PipelineBridge.startPipeline(
        subUrl: _effectiveUrl,
        testCount: _testCount,
      );

      if (!mounted) return;

      if (raw != null) {
        final list = (raw as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        setState(() {
          _results = list;
          _progress = 1.0;
          _statusKey = 'statusDone';
          _statusArgs = {'count': list.length};
        });
      } else {
        setState(() => _statusKey = 'statusStopped');
      }
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() {
        switch (e.code) {
          case 'EMPTY_BODY':
            _statusKey = 'errorEmptyBody';
            _statusArgs = null;
          case 'DECODE_FAILURE':
            _statusKey = 'errorDecodeFailure';
            _statusArgs = null;
          case 'NO_VALID_SCHEMES':
            _statusKey = 'errorNoValidSchemes';
            _statusArgs = null;
          case 'NETWORK_ERROR':
            _statusKey = 'errorNetwork';
            _statusArgs = {'message': e.message ?? ''};
          case 'PIPELINE_TIMEOUT':
            _statusKey = 'errorTimeout';
            _statusArgs = {'minutes': 10};
          default:
            _statusKey = 'errorGeneric';
            _statusArgs = {'message': e.message ?? e.code};
        }
      });
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _stop() async {
    await PipelineBridge.stopPipeline();
    if (!mounted) return;
    setState(() {
      _running = false;
      _statusKey = 'statusStopped';
      _statusArgs = null;
    });
  }

  void _copyAll(AppLocalizations l10n) {
    final text = _results.map((r) => r['uri'] as String).join('\n');
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.copiedAll(_results.length))),
    );
  }

  void _copyOne(String uri, int idx, AppLocalizations l10n) {
    Clipboard.setData(ClipboardData(text: uri));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.copiedOne(idx + 1))),
    );
  }

  /// Resolves the current status key + args into localized display text.
  String _statusText(AppLocalizations l10n) {
    final args = _statusArgs;
    switch (_statusKey) {
      case 'statusFetching':
        return l10n.statusFetching;
      case 'statusFetched':
        return l10n.statusFetched(args?['count'] as int? ?? 0);
      case 'statusRound1':
        return '${l10n.statusRound1} · ${l10n.statusProgress(_done, _total)}';
      case 'statusRound2':
        return '${l10n.statusRound2} · ${l10n.statusProgress(_done, _total)}';
      case 'statusRound3':
        return '${l10n.statusRound3} · ${l10n.statusProgress(_done, _total)}';
      case 'statusDone':
        return l10n.statusDone(args?['count'] as int? ?? 0);
      case 'statusStopped':
        return l10n.statusStopped;
      case 'errorEmptyBody':
        return l10n.errorEmptyBody;
      case 'errorDecodeFailure':
        return l10n.errorDecodeFailure;
      case 'errorNoValidSchemes':
        return l10n.errorNoValidSchemes;
      case 'errorNetwork':
        return l10n.errorNetwork(args?['message'] as String? ?? '');
      case 'errorTimeout':
        return l10n.errorTimeout(args?['minutes'] as int? ?? 10);
      case 'errorGeneric':
        return l10n.errorGeneric(args?['message'] as String? ?? '');
      default:
        return l10n.statusReady;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final ext = theme.extension<ProxySmithColors>()!;
    final app = ProxySmithApp.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _topBar(context, l10n, app),
              const SizedBox(height: 16),
              _statusLine(theme, l10n),
              const SizedBox(height: 12),
              _inputsCard(l10n, ext),
              const SizedBox(height: 12),
              if (_running || _total > 0) ...[
                StageProgress(
                  progress: _progress,
                  round: _round,
                  statusText: _statusText(l10n),
                ),
                const SizedBox(height: 12),
              ],
              _runButton(l10n),
              if (_warningMessage != null) ...[
                const SizedBox(height: 8),
                _warningBanner(_warningMessage!, ext),
              ],
              const SizedBox(height: 16),
              _resultsHeader(l10n),
              const SizedBox(height: 8),
              Expanded(child: _resultsList(l10n, ext)),
            ],
          ),
        ),
      ),
    );
  }

  // ── Sections ───────────────────────────────────────────────────────────

  Widget _topBar(BuildContext context, AppLocalizations l10n, ProxySmithAppState app) =>
      Row(
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
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).extension<ProxySmithColors>()!.mutedText,
                      ),
                ),
              ],
            ),
          ),
          _languageToggle(app),
          const SizedBox(width: 6),
          _themeToggle(app),
          const SizedBox(width: 6),
          OptionsMenuButton(currentVersion: '2.0.0'),
        ],
      );

  Widget _languageToggle(ProxySmithAppState app) {
    final isEn = app.locale.languageCode == 'en';
    return _TogglePill(
      leftLabel: 'EN',
      rightLabel: 'فا',
      isLeftActive: isEn,
      onTap: () => app.setLocale(Locale(isEn ? 'fa' : 'en')),
    );
  }

  Widget _themeToggle(ProxySmithAppState app) {
    final isDark = app.themeMode == ThemeMode.dark;
    return _TogglePill(
      leftLabel: '\u2600',
      rightLabel: '\u263E',
      isLeftActive: !isDark,
      onTap: () => app.toggleTheme(!isDark),
    );
  }

  Widget _statusLine(ThemeData theme, AppLocalizations l10n) => Text(
        _statusText(l10n),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.extension<ProxySmithColors>()!.mutedText,
        ),
      );

  Widget _inputsCard(AppLocalizations l10n, ProxySmithColors ext) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.configSourceLabel,
                style: TextStyle(fontSize: 11, color: ext.mutedText, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<ConfigSource>(
                initialValue: _selectedSource,
                isExpanded: true,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: ext.subtleBackground,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: ext.cardBorder, width: 0.5),
                  ),
                ),
                items: kConfigSources
                    .map((s) => DropdownMenuItem(
                          value: s,
                          child: Text(
                            s.isCustom ? l10n.sourceCustomUrl : s.label,
                            style: const TextStyle(fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ))
                    .toList(),
                onChanged: _running
                    ? null
                    : (v) => setState(() => _selectedSource = v!),
              ),
              if (_selectedSource.isCustom) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _customUrlCtrl,
                  enabled: !_running,
                  keyboardType: TextInputType.url,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: l10n.sourceCustomUrlHint,
                    filled: true,
                    fillColor: ext.subtleBackground,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: ext.cardBorder, width: 0.5),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    l10n.testCountLabel,
                    style: TextStyle(fontSize: 13, color: ext.mutedText),
                  ),
                  const Spacer(),
                  _TestCountStepper(
                    value: _testCount,
                    enabled: !_running,
                    onChanged: (v) => setState(() => _testCount = v),
                  ),
                ],
              ),
            ],
          ),
        ),
      );

  Widget _runButton(AppLocalizations l10n) => SizedBox(
        height: 50,
        child: ElevatedButton.icon(
          onPressed: _running ? _stop : _start,
          style: _running
              ? ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                )
              : null,
          icon: Icon(_running ? Icons.stop_rounded : Icons.play_arrow_rounded),
          label: Text(_running ? l10n.stopButton : l10n.runButton),
        ),
      );

  Widget _warningBanner(String message, ProxySmithColors ext) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF3E0),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFF9A6820)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontSize: 11, color: Color(0xFF9A6820)),
              ),
            ),
            InkWell(
              onTap: () => setState(() => _warningMessage = null),
              child: const Icon(Icons.close_rounded, size: 14, color: Color(0xFF9A6820)),
            ),
          ],
        ),
      );

  Widget _resultsHeader(AppLocalizations l10n) => Row(
        children: [
          Expanded(
            child: Text(
              l10n.resultsTitle,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.4,
                color: Theme.of(context).extension<ProxySmithColors>()!.mutedText,
              ),
            ),
          ),
          if (_results.isNotEmpty)
            InkWell(
              onTap: () => _copyAll(l10n),
              child: Text(
                l10n.copyAll,
                style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.primary),
              ),
            ),
        ],
      );

  Widget _resultsList(AppLocalizations l10n, ProxySmithColors ext) {
    if (_results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, size: 36, color: ext.mutedText),
            const SizedBox(height: 8),
            Text(l10n.noResultsYet, style: TextStyle(color: ext.mutedText, fontSize: 13)),
            const SizedBox(height: 2),
            Text(
              l10n.noResultsHint,
              style: TextStyle(color: ext.mutedText, fontSize: 11),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: _results.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (ctx, i) {
        final r = _results[i];
        return ProxyResultCard(
          rank: i + 1,
          ms: r['ms'] as int,
          uri: r['uri'] as String,
          onTap: () => _copyOne(r['uri'] as String, i, l10n),
        );
      },
    );
  }
}

/// Compact two-option pill toggle, used for language and theme switches.
class _TogglePill extends StatelessWidget {
  final String leftLabel;
  final String rightLabel;
  final bool isLeftActive;
  final VoidCallback onTap;

  const _TogglePill({
    required this.leftLabel,
    required this.rightLabel,
    required this.isLeftActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ext = Theme.of(context).extension<ProxySmithColors>()!;
    final activeColor = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: ext.subtleBackground,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _pillSegment(leftLabel, isLeftActive, activeColor),
            _pillSegment(rightLabel, !isLeftActive, activeColor),
          ],
        ),
      ),
    );
  }

  Widget _pillSegment(String label, bool active, Color activeColor) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: active ? activeColor.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: active ? FontWeight.w500 : FontWeight.w400,
            color: active ? activeColor : null,
          ),
        ),
      );
}

/// Stepper for test count: − [value] + with min/max clamping.
class _TestCountStepper extends StatelessWidget {
  final int value;
  final bool enabled;
  final ValueChanged<int> onChanged;

  static const int min = 50;
  static const int max = 500;
  static const int step = 50;

  const _TestCountStepper({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final ext = Theme.of(context).extension<ProxySmithColors>()!;
    return Container(
      decoration: BoxDecoration(
        color: ext.subtleBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: ext.cardBorder, width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            iconSize: 16,
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
            onPressed: enabled && value > min ? () => onChanged(value - step) : null,
            icon: const Icon(Icons.remove),
          ),
          SizedBox(
            width: 40,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
          IconButton(
            iconSize: 16,
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
            onPressed: enabled && value < max ? () => onChanged(value + step) : null,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}
