import 'dart:async';
import 'package:flutter/material.dart';
import 'package:trusted_time/trusted_time.dart';
import 'sync_telemetry.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize the engine with production-grade settings.
  await TrustedTime.initialize(
    config: const TrustedTimeConfig(
      refreshInterval: Duration(hours: 1),
      persistState: true,
    ),
  );

  // Register telemetry after init so the recorder receives every
  // subsequent sync cycle (refreshes, Force Resync, integrity-triggered
  // syncs). The very first bootstrap sync is missed because the engine
  // instance does not exist until initialize() returns.
  final telemetry = TelemetryRecorder();
  TrustedTime.registerObserver(telemetry);

  runApp(MyApp(telemetry: telemetry));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.telemetry});

  final TelemetryRecorder telemetry;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TrustedTime V2 Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: HomePage(telemetry: telemetry),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.telemetry});

  final TelemetryRecorder telemetry;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  DateTime _now = TrustedTime.now();
  Timer? _ticker;
  IntegrityEvent? _lastEvent;
  TrustedTimeEstimate? _estimate;
  bool _bgSyncEnabled = false;

  final TextEditingController _tzController = TextEditingController(
    text: 'America/New_York',
  );
  String _tzResult = 'Enter timezone and press Convert';

  @override
  void initState() {
    super.initState();
    // Section 1: UI clock ticking every second.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        _now = TrustedTime.now();
      });
    });

    // Section 2: Forensics subscription.
    TrustedTime.onIntegrityLost.listen((event) {
      setState(() {
        _lastEvent = event;
      });
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _tzController.dispose();
    super.dispose();
  }

  Future<void> _forceSync() async {
    await TrustedTime.forceResync();
  }

  void _getEstimate() {
    setState(() {
      _estimate = TrustedTime.nowEstimated();
    });
  }

  void _convertTimezone() {
    try {
      final local = TrustedTime.trustedLocalTimeIn(_tzController.text.trim());
      setState(() {
        _tzResult = 'Local Time: ${local.toString()}';
      });
    } catch (e) {
      setState(() {
        _tzResult = 'Error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTrusted = TrustedTime.isTrusted;

    return Scaffold(
      appBar: AppBar(title: const Text('TrustedTime V2 Features')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader('Section 1 — Live Clock'),
            _card(
              child: Column(
                children: [
                  Text(
                    _now.toIso8601String(),
                    style: const TextStyle(
                      fontSize: 20,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.shield,
                        color: isTrusted ? Colors.green : Colors.orange,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isTrusted ? 'TRUSTED' : 'NOT TRUSTED / SYNCING',
                        style: TextStyle(
                          color: isTrusted ? Colors.green : Colors.orange,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton(
                        onPressed: () =>
                            setState(() => _now = TrustedTime.now()),
                        child: const Text('Get Time'),
                      ),
                      ElevatedButton(
                        onPressed: _forceSync,
                        child: const Text('Force Resync'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            _sectionHeader('Section 2 — Tamper Forensics (F1)'),
            _card(
              child: _lastEvent == null
                  ? const Text('No tampering detected')
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Reason: ${_lastEvent!.reason.name}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Drift: ${_lastEvent!.drift?.inMilliseconds ?? 'N/A'} ms',
                        ),
                        Text('Detected At: ${_lastEvent!.detectedAt}'),
                      ],
                    ),
            ),
            _sectionHeader('Section 3 — Offline Estimate (F2)'),
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_estimate != null) ...[
                    Text('Est. Time: ${_estimate!.estimatedTime}'),
                    Text(
                      'Confidence: ${(_estimate!.confidence * 100).toStringAsFixed(1)}%',
                    ),
                    Text('Error: ±${_estimate!.estimatedError.inSeconds}s'),
                  ] else
                    const Text('No anchor persisted yet or currently trusted'),
                  const SizedBox(height: 8),
                  Center(
                    child: ElevatedButton(
                      onPressed: _getEstimate,
                      child: const Text('Get Estimate'),
                    ),
                  ),
                ],
              ),
            ),
            _sectionHeader('Section 4 — Timezone-Proof Local Time (F6)'),
            _card(
              child: Column(
                children: [
                  TextField(
                    controller: _tzController,
                    decoration: const InputDecoration(
                      labelText: 'IANA Timezone (e.g. Asia/Tokyo)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _tzResult,
                    style: const TextStyle(fontStyle: FontStyle.italic),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: _convertTimezone,
                    child: const Text('Convert'),
                  ),
                ],
              ),
            ),
            _sectionHeader('Section 5 — Background Sync (F4)'),
            _card(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _bgSyncEnabled
                        ? 'Background sync enabled (24h)'
                        : 'Background sync off',
                  ),
                  Switch(
                    value: _bgSyncEnabled,
                    onChanged: (val) {
                      setState(() {
                        _bgSyncEnabled = val;
                      });
                      if (val) {
                        TrustedTime.enableBackgroundSync(
                          interval: const Duration(hours: 24),
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
            _sectionHeader('Section 6 — Sync Telemetry'),
            _card(
              child: _SyncTelemetryPanel(recorder: widget.telemetry),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.blueAccent,
        ),
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SizedBox(width: double.infinity, child: child),
      ),
    );
  }
}


class _SyncTelemetryPanel extends StatelessWidget {
  const _SyncTelemetryPanel({required this.recorder});

  final TelemetryRecorder recorder;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: recorder,
      builder: (context, _) {
        final events = recorder.events.reversed.take(15).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Text(
                    'Press Force Resync (Section 1) to capture a sync '
                    'cycle. Warm-phase failures show as "warm: ..." on the '
                    'sourceFailed line.',
                    style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                  ),
                ),
                IconButton(
                  tooltip: 'Clear telemetry',
                  icon: const Icon(Icons.clear_all),
                  onPressed: recorder.reset,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (events.isEmpty)
              const Text(
                'No events recorded yet.',
                style: TextStyle(color: Colors.grey),
              )
            else
              ...events.map((e) => _TelemetryRow(event: e)),
          ],
        );
      },
    );
  }
}

class _TelemetryRow extends StatelessWidget {
  const _TelemetryRow({required this.event});

  final TelemetryEvent event;

  Color _colorFor(TelemetryKind kind) {
    switch (kind) {
      case TelemetryKind.syncStarted:
        return Colors.blueAccent;
      case TelemetryKind.sample:
        return Colors.greenAccent;
      case TelemetryKind.sourceFailed:
        return Colors.orangeAccent;
      case TelemetryKind.consensus:
        return Colors.cyanAccent;
      case TelemetryKind.metrics:
        return Colors.purpleAccent;
      case TelemetryKind.syncFailed:
        return Colors.redAccent;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(
        '${event.elapsedMs.toString().padLeft(7)}ms  '
        '${event.kind.name.padRight(13)}  ${event.detail}',
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 11,
          color: _colorFor(event.kind),
        ),
      ),
    );
  }
}
