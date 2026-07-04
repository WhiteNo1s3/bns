import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';

import 'package:bns/data/local/isar_service.dart';
import 'package:bns/data/sync/lan_sync_service.dart' show BnsPeer, LanSyncService;
import 'package:bns/core/models/trusted_device.dart';
import 'package:bns/data/sync/sync_progress.dart';
import 'package:bns/platform/android_widget.dart';

/// Low-maintenance, secure sync screen with:
/// - Clear progress bars (system or relaxing palette colors)
/// - Trusted devices + auto-sync option
/// - Secure first-time pairing with code confirmation + encryption
/// - Very forgiving and encouraging language
class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  final LanSyncService _service = LanSyncService();

  List<BnsPeer> _discovered = [];
  List<TrustedDevice> _trusted = [];
  SyncProgress _progress = SyncProgress.idle;
  bool _autoSync = true;
  bool _discovering = false;
  int _retentionDays = 14;
  int _widgetForwardDays = 2;

  String? _pendingPairCode;
  BnsPeer? _pendingPeer;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final settings = await IsarService.getSettings();
    _retentionDays = settings.retentionDays;
    _widgetForwardDays = settings.widgetForwardDays;
    await _service.start(deviceName: settings.deviceName, autoSync: _autoSync);

    _service.peersStream.listen((p) {
      if (mounted) setState(() => _discovered = p);
    });

    _service.progressStream.listen((p) {
      if (mounted) setState(() => _progress = p);
    });

    _loadTrusted();
    setState(() => _discovering = true);
  }

  Future<void> _loadTrusted() async {
    final t = await _service.getTrustedDevices();
    if (mounted) setState(() => _trusted = t);
  }

  Future<void> _loadRetention() async {
    final s = await IsarService.getSettings();
    if (mounted) {
      setState(() {
        _retentionDays = s.retentionDays;
        _widgetForwardDays = s.widgetForwardDays;
      });
    }
  }

  Future<void> _setRetention(int days) async {
    await IsarService.updateRetentionDays(days);
    await _loadRetention();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(days == 0 ? 'Unlimited retention (large files possible)' : 'Retention set to $days days')),
    );
  }

  Future<void> _resetRetention() async {
    await IsarService.resetRetentionToDefault();
    await _loadRetention();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Reset to default 2-week retention')),
    );
  }

  Future<void> _setWidgetForwardDays(int days) async {
    final settings = await IsarService.getSettings();
    final updated = settings.copyWith(widgetForwardDays: days);
    await IsarService.updateSettings(updated);
    await _loadRetention();
    // Refresh widget with new forward view
    // (call the helper if imported, or via service)
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Widget will show next $days days forward (less stress for you)')),
    );
    AndroidBnsWidget.updateWidget();
  }

  Future<void> _setWidgetForwardDays(int days) async {
    final settings = await IsarService.getSettings();
    final updated = settings.copyWith(widgetForwardDays: days);
    await IsarService.updateSettings(updated);
    await _loadRetention();
    // Update widget immediately
    // (import if needed, but call via service or direct)
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Widget will show next $days days forward (less stress)')),
    );
  }

  Future<void> _sync(BnsPeer peer) async {
    await _service.syncWithPeer(peer);
    await _loadTrusted();
  }

  Future<void> _startPairing(BnsPeer peer) async {
    final code = _service.generatePairingCode();

    setState(() {
      _pendingPeer = peer;
      _pendingPairCode = code;
    });

    // Show pairing dialog with big friendly UI
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _PairingDialog(
        code: code,
        peerName: peer.deviceName,
        onConfirm: () async {
          final ok = await _service.completePairing(peer, code, 'local');
          Navigator.pop(ctx, ok);
        },
      ),
    );

    setState(() {
      _pendingPeer = null;
      _pendingPairCode = null;
    });

    if (confirmed == true) {
      await _loadTrusted();
      await _sync(peer);
    }
  }

  Future<void> _toggleAutoSync(bool v) async {
    setState(() => _autoSync = v);
    _service.setAutoSync(v);
  }

  Future<void> _forget(TrustedDevice d) async {
    await _service.forgetDevice(d.id);
    await _loadTrusted();
  }

  Future<void> _manualExport() async {
    final f = await _service.manualExport();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Saved: ${f.path.split(Platform.pathSeparator).last}')),
    );
  }

  Future<void> _manualImport() async {
    final res = await FilePicker.platform.pickFiles();
    if (res?.files.single.path == null) return;
    await _service.manualImport(File(res!.files.single.path!));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Data merged in. Thank you for keeping things together.')),
    );
  }

  Color _progressColor(BuildContext context) {
    // Prefer system / relaxing palette primary
    return Theme.of(context).colorScheme.primary;
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = _progressColor(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Sync your devices')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Encouraging header
          Text(
            'Your devices talk only to each other.\nKeep them in sync with almost no effort.',
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          // Progress - always visible when active
          if (_progress.progress > 0 || _progress.isComplete)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    LinearProgressIndicator(
                      value: _progress.progress.clamp(0.0, 1.0),
                      color: color,
                      backgroundColor: color.withOpacity(0.15),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _progress.message,
                      style: const TextStyle(fontSize: 15),
                      textAlign: TextAlign.center,
                    ),
                    if (_progress.error != null)
                      Text(_progress.error!, style: const TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 16),

          // Trusted / Known devices
          Text('Your trusted devices', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_trusted.isEmpty)
            const Text('No devices paired yet. Discover one below to start a secure connection.'),
          ..._trusted.map((d) => ListTile(
                leading: const Icon(Icons.phone_android),
                title: Text(d.name),
                subtitle: Text('Last synced: ${d.lastSyncedAt.toLocal().toString().substring(0, 16)}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Switch(
                      value: d.autoSyncEnabled,
                      onChanged: (v) {}, // could update later
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _forget(d),
                    ),
                  ],
                ),
              )),

          const SizedBox(height: 24),

          // Auto-sync toggle
          SwitchListTile(
            title: const Text('Auto-sync when trusted devices are nearby'),
            subtitle: const Text('Happens gently in the background when this screen is open'),
            value: _autoSync,
            onChanged: _toggleAutoSync,
            activeColor: color,
          ),

          const SizedBox(height: 16),

          // Data retention to keep files small (2 weeks default)
          // Prevents huge .bns and slow sync. Future planning always allowed.
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('History retention (keeps files small for fast sync)', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text('Current: ${_retentionDays == 0 ? "Unlimited (10000 years mode)" : "$_retentionDays days (default 14 = 2 weeks)"}'),
                  const SizedBox(height: 8),
                  Text(
                    'Old days auto-delete as time passes. New days open up. Routines stay. You can plan far into the future.',
                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: () => _setRetention(14),
                        child: const Text('Default (2 weeks)'),
                      ),
                      OutlinedButton(
                        onPressed: () => _setRetention(90),
                        child: const Text('Expand to 90 days'),
                      ),
                      OutlinedButton(
                        onPressed: () => _setRetention(0),
                        child: const Text('Unlimited (redundant files ok)'),
                      ),
                      TextButton(
                        onPressed: _resetRetention,
                        child: const Text('Return to default'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Warning: larger retention = bigger .bns files = slower LAN sync.',
                    style: TextStyle(fontSize: 11, color: Colors.orange),
                  ),
                  const SizedBox(height: 12),
                  // Widget forward days - user controls to avoid stress. Default 2 (regular joe preference, no more than 2 days ahead)
                  Text('Widget forward days (set low to reduce stress - you control what you see):', style: TextStyle(fontSize: 11)),
                  Wrap(
                    spacing: 4,
                    children: [
                      for (int d in [0, 1, 2, 3, 7])
                        ChoiceChip(
                          label: Text('$d days'),
                          selected: _widgetForwardDays == d,
                          onSelected: (_) => _setWidgetForwardDays(d),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Discovered devices
          Text('Devices found on your Wi-Fi', style: Theme.of(context).textTheme.titleMedium),
          if (_discovering && _discovered.isEmpty)
            const LinearProgressIndicator(),

          ..._discovered.map((p) {
            final isTrusted = _trusted.any((t) => t.id == p.deviceId);
            return Card(
              child: ListTile(
                title: Text(p.deviceName),
                subtitle: Text(p.address),
                trailing: FilledButton(
                  onPressed: () => isTrusted ? _sync(p) : _startPairing(p),
                  child: Text(isTrusted ? 'Sync now' : 'Pair & Sync (secure)'),
                ),
              ),
            );
          }),

          const SizedBox(height: 32),

          // Manual - still easy
          Text('Manual backup (for USB or when Wi-Fi is not available)', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: OutlinedButton.icon(onPressed: _manualExport, icon: const Icon(Icons.save), label: const Text('Export .bns'))),
            const SizedBox(width: 12),
            Expanded(child: OutlinedButton.icon(onPressed: _manualImport, icon: const Icon(Icons.folder_open), label: const Text('Import .bns'))),
          ]),

          const SizedBox(height: 40),
          const Text(
            'Everything stays private. Only devices you explicitly accept can exchange data.',
            style: TextStyle(fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Big, clear, low-stress pairing confirmation dialog.
/// Shows the code on both devices so the user can visually verify.
class _PairingDialog extends StatelessWidget {
  final String code;
  final String peerName;
  final VoidCallback onConfirm;

  const _PairingDialog({
    required this.code,
    required this.peerName,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Secure Pairing Required'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('To protect your information, confirm this code is shown on $peerName:'),
          const SizedBox(height: 24),
          Text(
            code,
            style: Theme.of(context).textTheme.displayLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 8,
                ),
          ),
          const SizedBox(height: 16),
          const Text('Does the other device show the exact same numbers?'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel - something looks wrong'),
        ),
        FilledButton(
          onPressed: onConfirm,
          child: const Text('Yes, codes match. Connect securely'),
        ),
      ],
    );
  }
}
