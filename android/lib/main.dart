import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const ProxySmithApp());

class ProxySmithApp extends StatelessWidget {
  const ProxySmithApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ProxySmith',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0D1117),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF58A6FF),
          surface: Color(0xFF161B22),
        ),
      ),
      home: const PipelineScreen(),
    );
  }
}

// ── Bridge ─────────────────────────────────────────────────────────────────
const _methodChannel = MethodChannel('ir.proxysmith/pipeline');
const _eventChannel  = EventChannel('ir.proxysmith/progress');

// ── Screen ─────────────────────────────────────────────────────────────────
class PipelineScreen extends StatefulWidget {
  const PipelineScreen({super.key});

  @override
  State<PipelineScreen> createState() => _PipelineScreenState();
}

class _PipelineScreenState extends State<PipelineScreen> {
  final _subUrlCtrl = TextEditingController(
    text: 'https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/All_Configs_Sub.txt',
  );
  final _sampleCtrl  = TextEditingController(text: '5');
  final _maxPingCtrl = TextEditingController(text: '8000');

  bool   _running  = false;
  String _status   = 'ready';
  double _progress = 0;
  int    _round    = 0;
  int    _done     = 0;
  int    _total    = 0;

  List<Map<String, dynamic>> _results = [];

  // FIX: Store the stream subscription so we can cancel it properly.
  // Previously a new listener was stacked on every Run tap — after 3 runs
  // you'd have 3 listeners all firing setState simultaneously.
  StreamSubscription? _eventSub;

  // ── Lifecycle ──────────────────────────────────────────────────────────
  // FIX: dispose() was completely missing. TextEditingControllers and the
  // stream subscription would leak on every screen rebuild / navigator pop.
  @override
  void dispose() {
    _eventSub?.cancel();
    _subUrlCtrl.dispose();
    _sampleCtrl.dispose();
    _maxPingCtrl.dispose();
    super.dispose();
  }

  // ── Start ──────────────────────────────────────────────────────────────
  Future<void> _start() async {
    setState(() {
      _running  = true;
      _status   = 'starting...';
      _progress = 0;
      _results  = [];
      _round    = 0;
      _done     = 0;
      _total    = 0;
    });

    // FIX: Cancel any existing subscription before creating a new one.
    await _eventSub?.cancel();
    _eventSub = _eventChannel.receiveBroadcastStream().listen(
      (event) {
        final e    = Map<String, dynamic>.from(event as Map);
        final type = e['type'] as String;
        final data = e['data'];

        // Guard: widget might be unmounted before all events arrive
        if (!mounted) return;

        setState(() {
          switch (type) {
            case 'status':
              _status = data as String;
            case 'fetched':
              _total  = data as int;
              _status = 'fetched $_total URIs';
            case 'progress':
              final p = Map<String, dynamic>.from(data as Map);
              _round  = p['round'] as int;
              _done   = p['done']  as int;
              _total  = p['total'] as int;
              _status = 'R$_round  $_done / $_total';
              _progress = switch (_round) {
                1 => (_done / _total) * 0.7,
                2 => 0.7 + (_done / _total) * 0.2,
                3 => 0.9 + (_done / _total) * 0.1,
                _ => _progress,
              };
          }
        });
      },
      onError: (error) {
        if (!mounted) return;
        setState(() => _status = 'stream error: $error');
      },
    );

    try {
      final raw = await _methodChannel.invokeMethod('startPipeline', {
        'subUrl'   : _subUrlCtrl.text.trim(),
        'sampleN'  : int.tryParse(_sampleCtrl.text)  ?? 5,
        'maxPingMs': int.tryParse(_maxPingCtrl.text) ?? 8000,
      });

      if (!mounted) return;

      if (raw != null) {
        final list = (raw as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        setState(() {
          _results  = list;
          _progress = 1.0;
          _status   = 'done — ${list.length} results';
        });
      } else {
        // null means the pipeline was stopped by the user
        setState(() => _status = 'stopped');
      }
    } on PlatformException catch (e) {
      if (!mounted) return;
      // FIX: e.message can be null; fall back to e.code so the user always
      // sees a meaningful error string instead of "error: null"
      setState(() => _status = 'error: ${e.message ?? e.code}');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _stop() async {
    await _methodChannel.invokeMethod('stopPipeline');
    if (!mounted) return;
    setState(() { _running = false; _status = 'stopped'; });
  }

  void _copyAll() {
    final text = _results.map((r) => r['uri'] as String).join('\n');
    Clipboard.setData(ClipboardData(text: text));
    setState(() => _status = 'copied ${_results.length} URIs');
  }

  void _copyOne(String uri, int idx) {
    Clipboard.setData(ClipboardData(text: uri));
    setState(() => _status = 'copied #${idx + 1}');
  }

  // ── Build ──────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(),
              const SizedBox(height: 16),
              _inputCard(),
              const SizedBox(height: 12),
              _progressRow(),
              const SizedBox(height: 12),
              _runButton(),
              const SizedBox(height: 16),
              _resultsHeader(),
              const SizedBox(height: 8),
              Expanded(child: _resultsList()),
            ],
          ),
        ),
      ),
    );
  }

  // ── Widgets ────────────────────────────────────────────────────────────
  Widget _header() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('PROXYSMITH',
        style: TextStyle(
          color: Color(0xFF58A6FF),
          fontSize: 22,
          fontFamily: 'monospace',
          letterSpacing: 2,
          fontWeight: FontWeight.bold,
        ),
      ),
      Text(_status,
        style: const TextStyle(
          color: Color(0xFF8B949E),
          fontSize: 12,
          fontFamily: 'monospace',
        ),
      ),
    ],
  );

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(text,
      style: const TextStyle(
        color: Color(0xFF58A6FF),
        fontSize: 10,
        fontFamily: 'monospace',
        letterSpacing: 1,
      ),
    ),
  );

  Widget _field(TextEditingController ctrl, {TextInputType? keyboard}) =>
    Container(
      color: const Color(0xFF161B22),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: TextField(
        controller: ctrl,
        keyboardType: keyboard,
        style: const TextStyle(
          color: Color(0xFFE6EDF3),
          fontSize: 11,
          fontFamily: 'monospace',
        ),
        decoration: const InputDecoration.collapsed(hintText: ''),
        enabled: !_running,
      ),
    );

  Widget _inputCard() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _label('SUBSCRIPTION URL'),
      _field(_subUrlCtrl, keyboard: TextInputType.url),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label('SAMPLE RATE'),
            _field(_sampleCtrl, keyboard: TextInputType.number),
          ],
        )),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label('MAX PING MS'),
            _field(_maxPingCtrl, keyboard: TextInputType.number),
          ],
        )),
      ]),
    ],
  );

  Widget _progressRow() => Column(
    children: [
      LinearProgressIndicator(
        value: _progress,
        backgroundColor: const Color(0xFF21262D),
        valueColor: AlwaysStoppedAnimation<Color>(
          _running ? const Color(0xFF58A6FF) : const Color(0xFF3FB950),
        ),
        minHeight: 4,
      ),
    ],
  );

  Widget _runButton() => SizedBox(
    width: double.infinity,
    height: 48,
    child: ElevatedButton(
      onPressed: _running ? _stop : _start,
      style: ElevatedButton.styleFrom(
        backgroundColor: _running
            ? const Color(0xFFDA3633)
            : const Color(0xFF58A6FF),
        foregroundColor: const Color(0xFF0D1117),
        shape: const RoundedRectangleBorder(),
        textStyle: const TextStyle(
          fontFamily: 'monospace',
          letterSpacing: 1.5,
          fontWeight: FontWeight.bold,
        ),
      ),
      child: Text(_running ? 'STOP' : 'RUN PIPELINE'),
    ),
  );

  Widget _resultsHeader() => Row(
    children: [
      const Expanded(
        child: Text('RESULTS',
          style: TextStyle(
            color: Color(0xFF58A6FF),
            fontSize: 10,
            fontFamily: 'monospace',
            letterSpacing: 1,
          ),
        ),
      ),
      if (_results.isNotEmpty)
        GestureDetector(
          onTap: _copyAll,
          child: const Text('COPY ALL',
            style: TextStyle(
              color: Color(0xFF3FB950),
              fontSize: 10,
              fontFamily: 'monospace',
            ),
          ),
        ),
    ],
  );

  Widget _resultsList() => Container(
    color: const Color(0xFF161B22),
    child: _results.isEmpty
        ? const Center(
            child: Text('no results yet',
              style: TextStyle(color: Color(0xFF484F58), fontFamily: 'monospace'),
            ),
          )
        : ListView.separated(
            itemCount: _results.length,
            separatorBuilder: (_, __) => const Divider(
              height: 1, color: Color(0xFF21262D)),
            itemBuilder: (ctx, i) {
              final r   = _results[i];
              final ms  = r['ms'] as int;
              final uri = r['uri'] as String;
              final color = ms < 150
                  ? const Color(0xFF3FB950)
                  : ms < 400
                      ? const Color(0xFFD29922)
                      : const Color(0xFFDA3633);
              return InkWell(
                onTap: () => _copyOne(uri, i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('#${i + 1}  ${ms}ms',
                        style: TextStyle(
                          color: color,
                          fontSize: 13,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(uri,
                        style: const TextStyle(
                          color: Color(0xFF8B949E),
                          fontSize: 10,
                          fontFamily: 'monospace',
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
  );
}
