import 'dart:async';

import 'package:flutter/material.dart';
import 'package:trusted_time/trusted_time.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // the UI builds with untrusted system time before the engine is ready.
  await TrustedTime.initialize(
    config: const TrustedTimeConfig(
      refreshInterval: Duration(hours: 1), // Standard drift correction window.
      persistState: true, // Enables instant offline trust via disk cache.
    ),
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // We use this local variable to drive the UI, refreshed by timers or streams.
  late DateTime _now;

  // Stream subscriptions for real-time engine events.
  StreamSubscription? _resyncSubscription;
  StreamSubscription? _integrityLostSubscription;

  @override
  void initState() {
    super.initState();
    // to return a mathematically correct time, not a placeholder.
    _now = TrustedTime.now(); 

    // Instead of polling or guessing when drift happens, we subscribe to the
    // source of truth. The engine notifies us exactly when the network consensus 
    // shifts the anchor, keeping our UI strictly consistent with the server.
    _resyncSubscription = TrustedTime.onResync.listen((_) => _refreshTime());


    // If the user manually changes the system clock, we want to know immediately.
    // This allows the UI to show a "Security Alert" or disable sensitive buttons 
    // without waiting for the next network sync.
    _integrityLostSubscription =
        TrustedTime.onIntegrityLost.listen((_) => _refreshTime());
  }

  @override
  void dispose() {
    _resyncSubscription?.cancel();
    _integrityLostSubscription?.cancel();
    super.dispose();
  }

  void _refreshTime() {
    if (mounted) {
      setState(() {
        _now = TrustedTime.now();
      });
    }
  }

  Future<void> _forceSync() async {
    // This triggers network I/O and server load. Use only for critical checkpoints 
    // (e.g., just before a payment or license validation).
    await TrustedTime.forceResync();
  }

  @override
  Widget build(BuildContext context) {
    final isTrusted = TrustedTime.isTrusted;
    final lastSync = TrustedTime.lastSyncTime;
    final drift = TrustedTime.estimatedDrift;

    return Scaffold(
      appBar: AppBar(title: const Text('TrustedTime Example')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Current Trusted Time',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            // In a real stopwatch/countdown UI, you would wrap this Text widget 
            // in a `Ticker` or `StreamBuilder.periodic` to update every second.
            Text(_now.toString(),
                style: const TextStyle(fontFamily: 'monospace')),
            const SizedBox(height: 24),
            Row(
              children: [
                ElevatedButton(
                  onPressed: _refreshTime,
                  child: const Text('Get Time'),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _forceSync,
                  child: const Text('Force Resync'),
                ),
              ],
            ),
            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 16),
            const Text(
              'Trust Details',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text.rich(
              TextSpan(
                style: const TextStyle(height: 1.5),
                children: [
                  TextSpan(
                    text: isTrusted
                        ? 'Status: Time is trusted\n'
                        : 'Status: Waiting for sync\n',
                    style: TextStyle(
                      color: isTrusted ? Colors.green : Colors.orange,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (isTrusted) ...[
                    TextSpan(text: 'Last Sync: ${lastSync.toLocal()}\n'),
                    TextSpan(text: 'Est. Drift: ±${drift.inMilliseconds}ms'),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
