import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n/app_localizations.dart';
import '../main.dart';
import '../models/config_source.dart';
import '../services/pipeline_bridge.dart';
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
  List<ConfigSource> _allSources = [...kBuiltInSources, kCustomUrlSource];
  ConfigSource _selectedSource = kBuiltInSources.first;
  final _customUrlCtrl = TextEditingController();
  int _testCount = 200;

  bool _running = false;
  String _statusKey = 'ready'; // semantic key, resolved to text at build time
  Map<String, dynamic>? _statusArgs;
  double _progress = 0;
  int _round = 0;
  int _done = 0;
  int _total = 0;
  int _fetchedCount = 0;
  String? _warningMessage;

  List<Map<String, dynamic>> _results = [];
  bool _selectionMode = false;
  final Set<int> _selectedIndices = {};

  StreamSubscription? _eventSub;

  @override
  void initState() {
    super.initState();
    _loadUserSources();
  }

  Future<void> _loadUserSources() async {
    final userSources = await SourceStorage.loadUserSources();
    if (!mounted) return;
    setState(() {
      _allSources = [...kBuiltInSources, ...userSources, kCustomUrlSource];
    });
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _customUrlCtrl.dispose();
    super.dispose();
  }

  String get _effectiveUrl =>
      _selectedSource.isCustom ? _customUrlCtrl.text.trim() : _selectedSource.url!;

  // -- Start --
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
      _fetchedCount = 0;
      _warningMessage = null;
      _selectionMode = false;
      _selectedIndices.clear();
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
              // Backend sends free-text dev-facing status; only used as a
              // fallback when no richer event (fetched/progress) has fired.
              final s = data as String;
              if (s == 'stopped') {
                _statusKey = 'statusStopped';
              }
            case 'fetched':
              _fetchedCount = data as int;
              _statusKey = 'statusFetched';
              _statusArgs = {'count': _fetchedCount};
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
              // Real continuous progress across all 3 rounds, weighted by
              // how much work each round typically represents.
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
  /// This is the SINGLE source of status text shown to the user — it only
  /// renders inside the progress card now, not duplicated above it.
  String _statusText(AppLocalizations l10n) {
    final args = _statusArgs;
    switch (_statusKey) {
      case 'statusFetching':
        return l10n.statusFetching;
      case 'statusFetched':
        return l10n.statusFetched(args?['count'] as int? ?? 0);
      case 'statusRound1':
        return '${l10n.statusRound1} (${l10n.statusFetched(_fetchedCount)}) \u00b7 ${l10n.statusProgress(_done, _total)}';
      case 'statusRound2':
        return '${l10n.statusRound2} \u00b7 ${l10n.statusProgress(_done, _total)}';
      case 'statusRound3':
        return '${l10n.statusRound3} \u00b7 ${l10n.statusProgress(_done, _total)}';
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
              _inputsCard(l10n, ext),
              const SizedBox(height: 12),
              if (_running || _total > 0 || _fetchedCount > 0) ...[
                StageProgress(
                  progress: _progress,
                  round: _round,
                  statusText: _statusText(l10n),
                ),
                const SizedBox(height: 12),
              ] else ...[
                // Idle state: still show the status line (e.g. "Ready")
                // exactly once, here, instead of duplicating it above.
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    _statusText(l10n),
                    style: TextStyle(fontSize: 12, color: ext.mutedText),
                  ),
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

  // -- Sections --

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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          OptionsMenuButton(currentVersion: '2.0.0'),
        ],
      );

  /// Theme + language switches, shown as a compact settings row beneath
  /// the inputs card rather than crammed into the top bar (where the pill
  /// toggles previously caused overflow on narrow screens / long app names).
  Widget _settingsRow(BuildContext context, ProxySmithAppState app, ProxySmithColors ext) {
    final isDark = app.themeMode == ThemeMode.dark;
    final isFa = app.locale.languageCode == 'fa';
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        LabeledSwitch(
          leftLabel: 'EN',
          rightLabel: 'FA',
          value: isFa,
          onChanged: (v) => app.setLocale(Locale(v ? 'fa' : 'en')),
        ),
        LabeledSwitch(
          leftLabel: 'Light',
          rightLabel: 'Dark',
          leftIcon: Icons.light_mode_rounded,
          rightIcon: Icons.dark_mode_rounded,
          value: isDark,
          onChanged: (v) => app.toggleTheme(v),
        ),
      ],
    );
  }

  Widget _inputsCard(AppLocalizations l10n, ProxySmithColors ext) {
    final app = ProxySmithApp.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Settings (language / theme) now lead the card, saving the
            // vertical space a separate divider+row used to take below.
            _settingsRow(context, app, ext),
            const Divider(height: 24),

            // Source picker and test-count stepper share one row instead
            // of stacking — the dropdown takes the flexible remaining
            // space, the stepper keeps its compact fixed width.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.configSourceLabel,
                        style: TextStyle(
                          fontSize: 11,
                          color: ext.mutedText,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 6),
                      // FIX (overflow bug): DropdownButtonFormField's popup
                      // menu previously matched the *content* width of
                      // whichever item happened to be selected, which let
                      // long URLs/labels push it past the card's bounds.
                      // isExpanded forces the popup to match the field's
                      // own width every time, regardless of item content.
                      DropdownButtonFormField<ConfigSource>(
                        initialValue: _selectedSource,
                        isExpanded: true,
                        menuMaxHeight: 320,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: ext.subtleBackground,
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: ext.cardBorder, width: 0.5),
                          ),
                        ),
                        items: _allSources
                            .map((s) => DropdownMenuItem(
                                  value: s,
                                  child: Text(
                                    s.isCustom ? l10n.sourceCustomUrl : s.label,
                                    style: const TextStyle(fontSize: 12),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ))
                            .toList(),
                        onChanged: _running
                            ? null
                            : (v) => setState(() => _selectedSource = v!),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.testCountLabel,
                        style: TextStyle(
                          fontSize: 11,
                          color: ext.mutedText,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 6),
                      _TestCountStepper(
                        value: _testCount,
                        enabled: !_running,
                        onChanged: (v) => setState(() => _testCount = v),
                        expand: true,
                      ),
                    ],
                  ),
                ),
              ],
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
          ],
        ),
      ),
    );
  }

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

  Widget _resultsHeader(AppLocalizations l10n) {
    final ext = Theme.of(context).extension<ProxySmithColors>()!;
    final primary = Theme.of(context).colorScheme.primary;

    if (_selectionMode) {
      // Selection-mode header: shows count + Copy Selected + Cancel,
      // replacing the normal title/Copy-All row entirely.
      return Row(
        children: [
          Expanded(
            child: Text(
              l10n.selectedCount(_selectedIndices.length),
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: primary),
            ),
          ),
          TextButton(
            onPressed: _selectedIndices.isEmpty ? null : () => _copySelected(l10n),
            style: TextButton.styleFrom(
              backgroundColor: ext.subtleBackground,
              foregroundColor: primary,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(l10n.copySelected, style: const TextStyle(fontSize: 11)),
          ),
          const SizedBox(width: 6),
          TextButton(
            onPressed: () => setState(() {
              _selectionMode = false;
              _selectedIndices.clear();
            }),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(l10n.cancelSelection, style: TextStyle(fontSize: 11, color: ext.mutedText)),
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: Text(
            l10n.resultsTitle,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.4,
              color: ext.mutedText,
            ),
          ),
        ),
        if (_results.isNotEmpty) ...[
          // "Select" enters selection mode so the user can pick a subset
          // of configs (e.g. just the top 3) instead of all-or-nothing.
          TextButton.icon(
            onPressed: () => setState(() => _selectionMode = true),
            style: TextButton.styleFrom(
              foregroundColor: ext.mutedText,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: const Icon(Icons.checklist_rounded, size: 14),
            label: Text(l10n.selectButton, style: const TextStyle(fontSize: 11)),
          ),
          const SizedBox(width: 6),
          // FIX: Copy All was a bare clickable Text, easy to miss as
          // interactive. Now a real small filled button with an icon.
          TextButton.icon(
            onPressed: () => _copyAll(l10n),
            style: TextButton.styleFrom(
              backgroundColor: ext.subtleBackground,
              foregroundColor: primary,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: const Icon(Icons.copy_all_rounded, size: 14),
            label: Text(l10n.copyAll, style: const TextStyle(fontSize: 11)),
          ),
        ],
      ],
    );
  }

  void _copySelected(AppLocalizations l10n) {
    final uris = _selectedIndices.map((i) => _results[i]['uri'] as String).join('\n');
    Clipboard.setData(ClipboardData(text: uris));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.copiedAll(_selectedIndices.length))),
    );
    setState(() {
      _selectionMode = false;
      _selectedIndices.clear();
    });
  }

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

    // FIX (scroll affordance): a thin always-visible Scrollbar makes it
    // obvious there's more content below the fold — without it, a list
    // that exactly fills the viewport gives no visual hint that scrolling
    // would reveal more results.
    return Scrollbar(
      thumbVisibility: true,
      radius: const Radius.circular(8),
      thickness: 4,
      child: ListView.separated(
        padding: const EdgeInsets.only(right: 6), // room for the scrollbar
        itemCount: _results.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (ctx, i) {
          final r = _results[i];
          return ProxyResultCard(
            rank: i + 1,
            ms: r['ms'] as int,
            uri: r['uri'] as String,
            onTap: () => _copyOne(r['uri'] as String, i, l10n),
            selectionMode: _selectionMode,
            selected: _selectedIndices.contains(i),
            onSelectedChanged: (checked) => setState(() {
              if (checked == true) {
                _selectedIndices.add(i);
              } else {
                _selectedIndices.remove(i);
              }
            }),
          );
        },
      ),
    );
  }
}

/// Stepper for test count: minus [value] plus, with min/max clamping.
class _TestCountStepper extends StatelessWidget {
  final int value;
  final bool enabled;
  final ValueChanged<int> onChanged;
  final bool expand;

  static const int min = 50;
  static const int max = 500;
  static const int step = 50;

  const _TestCountStepper({
    required this.value,
    required this.enabled,
    required this.onChanged,
    this.expand = false,
  });

  @override
  Widget build(BuildContext context) {
    final ext = Theme.of(context).extension<ProxySmithColors>()!;
    final row = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      children: [
        IconButton(
          iconSize: 16,
          padding: const EdgeInsets.all(4),
          constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
          onPressed: enabled && value > min ? () => onChanged(value - step) : null,
          icon: const Icon(Icons.remove),
        ),
        if (expand)
          Expanded(
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          )
        else
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
    );

    return Container(
      decoration: BoxDecoration(
        color: ext.subtleBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: ext.cardBorder, width: 0.5),
      ),
      child: row,
    );
  }
}
