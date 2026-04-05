import 'dart:async';
import 'package:flutter/material.dart';
import 'package:trusted_time/trusted_time.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize the engine with production-grade settings.
  await TrustedTime.initialize(
    config: const TrustedTimeConfig(
      refreshInterval: Duration(hours: 1),
      persistState: true,
    ),
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

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
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

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
