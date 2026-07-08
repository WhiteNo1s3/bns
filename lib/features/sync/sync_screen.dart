import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';

import 'package:bns/core/keybinds.dart';
import 'package:bns/providers/app_providers.dart';
import 'package:bns/data/export/bns_exporter.dart';
import 'package:bns/data/local/isar_service.dart';
import 'package:bns/data/sync/lan_sync_service.dart'
    show BnsPeer, LanSyncService;
import 'package:bns/core/models/trusted_device.dart';
import 'package:bns/data/sync/sync_progress.dart';
import 'package:bns/platform/android_widget.dart';
import 'package:bns/ui/widgets/bns_app_bar.dart';

/// Low-maintenance, secure sync screen with:
/// - Clear progress bars (system or relaxing palette colors)
/// - Trusted devices + auto-sync option
/// - Secure first-time pairing with code confirmation + encryption
/// - Very forgiving and encouraging language
class SyncScreen extends ConsumerStatefulWidget {
  const SyncScreen({super.key});

  @override
  ConsumerState<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends ConsumerState<SyncScreen> {
  final LanSyncService _service = LanSyncService();

  List<BnsPeer> _discovered = [];
  List<TrustedDevice> _trusted = [];
  SyncProgress _progress = SyncProgress.idle;
  bool _autoSync = true;
  bool _quietMode = false;
  bool _autoImage = true;
  bool _discovering = false;
  int _retentionDays = 14;
  int _widgetForwardDays = 2;
  String _userType = 'normal';
  String _deviceName = 'My BNS Device';
  String _shareName = '';
  bool _fullCareMode = false;
  // PC robust keybinds (typing #1 on PC)
  Map<String, String> _keybinds = {};
  Map<String, bool> _enabledKeybinds = {};
  // NOTE: the 0.12a "account server" section was cancelled (owner decision,
  // 2026-07-06) — see prototypes/cloud-pivot/. LAN + .bns is the way.

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final settings = await IsarService.getSettings();
    _retentionDays = settings.retentionDays;
    _widgetForwardDays = settings.widgetForwardDays;
    _userType = settings.userType;
    _deviceName = settings.deviceName;
    _shareName = settings.shareName;
    _fullCareMode = settings.fullCareMode;
    _autoSync = true; // default; could persist per device but simple
    _quietMode = settings.quietMode;
    _autoImage = settings.autoImageEnabled;
    _keybinds = Map<String, String>.from(settings.keybinds);
    _enabledKeybinds = Map<String, bool>.from(settings.enabledKeybinds);

    // Receiver side of pairing: another device initiated and shows a code —
    // the user types it here. Declining (or closing) shares nothing.
    _service.onPairRequest = (req) async {
      if (!mounted) return null;
      return showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => _EnterCodeDialog(peerName: req.deviceName),
      );
    };

    await _service.start(
        deviceName: settings.effectiveShareName, autoSync: _autoSync);

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
        _userType = s.userType;
        _deviceName = s.deviceName;
        _quietMode = s.quietMode;
        _autoImage = s.autoImageEnabled;
        _keybinds = Map<String, String>.from(s.keybinds);
        _enabledKeybinds = Map<String, bool>.from(s.enabledKeybinds);
      });
    }
  }

  Future<void> _setRetention(int days) async {
    await IsarService.updateRetentionDays(days);
    await _loadRetention();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(days == 0
              ? 'Unlimited retention (large files possible)'
              : 'Retention set to $days days')),
    );
  }

  Future<void> _resetRetention() async {
    await IsarService.resetRetentionToDefault();
    await _loadRetention();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Back to keeping 15 days of history')),
    );
  }

  Future<void> _setDeviceName(String name) async {
    if (name.trim().isEmpty) return;
    final s = await IsarService.getSettings();
    final updated = s.copyWith(deviceName: name.trim());
    await IsarService.updateSettings(updated);
    await _loadRetention();
    // Restart service so discovery shows the current share identity.
    await _service.stop();
    await _service.start(
        deviceName: updated.effectiveShareName, autoSync: _autoSync);
    setState(() => _deviceName = name.trim());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content:
              Text('Device named "$name". Your other devices will see this.')),
    );
  }

  /// The family-facing share name ("Dad", "Yossi") — what trusted people see
  /// when this person's device asks to pair or sync. Not the phone's name.
  Future<void> _setShareName(String name) async {
    final s = await IsarService.getSettings();
    final updated = s.copyWith(shareName: name.trim());
    await IsarService.updateSettings(updated);
    await _service.stop();
    await _service.start(
        deviceName: updated.effectiveShareName, autoSync: _autoSync);
    setState(() => _shareName = name.trim());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(name.trim().isEmpty
              ? 'Sharing as "${updated.deviceName}" (device name).'
              : 'People you trust will see you as "${name.trim()}".')),
    );
  }

  Future<void> _setAutoImage(bool v) async {
    final s = await IsarService.getSettings();
    await IsarService.updateSettings(s.copyWith(autoImageEnabled: v));
    await _loadRetention();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(v
              ? 'A fresh .bns will quietly stay ready to share.'
              : 'Auto-imaging off. Manual Export still works anytime.')));
    }
  }

  Future<void> _setQuietMode(bool v) async {
    final s = await IsarService.getSettings();
    await IsarService.updateSettings(s.copyWith(quietMode: v));
    await _loadRetention();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(
              v ? 'Quiet mode on — less stimulation.' : 'Quiet mode off.')),
    );
  }

  // PC keybinds: set and forget. Checkbox to activate, press keys to change.
  // Changes apply immediately (the app rebuilds its shortcuts) and travel in .bns.
  Future<void> _updateKeybind(String id, String combo) async {
    await IsarService.setKeybind(id, combo);
    await _loadRetention();
    ref.invalidate(settingsProvider); // shortcuts rebuild live
    AndroidBnsWidget.updateWidget();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                '${Keybinds.labelFor(id)} is now ${Keybinds.pretty(combo)}. Active right away.')),
      );
    }
  }

  Future<void> _toggleKeybind(String id, bool enabled) async {
    await IsarService.toggleKeybindEnabled(id, enabled);
    await _loadRetention();
    ref.invalidate(settingsProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(enabled
              ? 'Keybind enabled.'
              : 'Keybind disabled (still saved).')),
    );
  }

  Future<void> _resetKeybinds() async {
    await IsarService.resetKeybindsToDefault();
    await _loadRetention();
    ref.invalidate(settingsProvider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Keybinds back to the simple default layout.')),
      );
    }
  }

  /// Open the press-to-record dialog for one keybind. No syntax to learn:
  /// press the combination, see it, save it.
  Future<void> _recordCombo(String id) async {
    final combo = await showDialog<String>(
      context: context,
      builder: (ctx) =>
          _ComboRecorderDialog(actionLabel: Keybinds.labelFor(id)),
    );
    if (combo != null && combo.isNotEmpty) {
      await _updateKeybind(id, combo);
    }
  }

  /// Keybind rows: checkbox + pretty combo + "press to change".
  /// Order and labels come from the central registry (lib/core/keybinds.dart).
  List<Widget> _buildKeybindRows() {
    final rows = <Widget>[];
    // Registry actions first (in their friendly order), then any unknown
    // leftovers from older versions so nothing the user set disappears.
    final knownIds = Keybinds.actions.map((a) => a.id).toList();
    final extraIds =
        _keybinds.keys.where((id) => !knownIds.contains(id)).toList()..sort();

    for (final id in [...knownIds, ...extraIds]) {
      final combo = _keybinds[id];
      if (combo == null) continue;
      final isEnabled = _enabledKeybinds[id] ?? true;

      rows.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            SizedBox(
              width: 26,
              child: Checkbox(
                value: isEnabled,
                onChanged: (v) => _toggleKeybind(id, v ?? false),
                activeColor: Theme.of(context).colorScheme.primary,
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(Keybinds.labelFor(id),
                  style: const TextStyle(fontSize: 13)),
            ),
            Tooltip(
              message: 'Click, then press the new keys',
              child: OutlinedButton(
                onPressed: () => _recordCombo(id),
                style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  visualDensity: VisualDensity.compact,
                ),
                child: Text(
                  Keybinds.pretty(combo),
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              isEnabled ? 'active' : 'off',
              style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ));
    }

    rows.add(Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _resetKeybinds,
          icon: const Icon(Icons.restart_alt, size: 18),
          label: const Text('Return to simple default layout'),
        ),
      ),
    ));

    return rows;
  }

  Future<void> _setWidgetForwardDays(int days) async {
    final settings = await IsarService.getSettings();
    final updated = settings.copyWith(widgetForwardDays: days);
    await IsarService.updateSettings(updated);
    await _loadRetention();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(
              'Widget will show next $days days forward (less stress for you)')),
    );
    AndroidBnsWidget.updateWidget();
  }

  Future<void> _sync(BnsPeer peer) async {
    await _service.syncWithPeer(peer);
    await _loadTrusted();
  }

  Future<void> _startPairing(BnsPeer peer) async {
    final code = _service.generatePairingCode();

    // Initiator side: show the code big and clear; the user types it on the
    // other device. The code itself never travels over the network.
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _PairingDialog(
        code: code,
        peerName: peer.deviceName,
        onConfirm: () async {
          final ok = await _service.completePairing(peer, code);
          if (ctx.mounted) Navigator.pop(ctx, ok);
        },
      ),
    );

    if (confirmed == true) {
      await _loadTrusted();
    }
  }

  Future<void> _toggleAutoSync(bool v) async {
    setState(() => _autoSync = v);
    _service.setAutoSync(v);
  }

  Future<void> _forget(TrustedDevice d) async {
    await _service.forgetDevice(d.id);
    await _service.refreshTrustPolicy();
    await _loadTrusted();
  }

  /// Save a per-device change (LAN allowed / auto-sync) and make the running
  /// sync service honor it immediately.
  Future<void> _updateTrustedDevice(TrustedDevice updated) async {
    await IsarService.saveTrustedDevice(updated);
    await _service.refreshTrustPolicy();
    await _loadTrusted();
  }

  Future<void> _manualExport() async {
    final f = await _service.manualExport();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text('Saved: ${f.path.split(Platform.pathSeparator).last}')),
    );
  }

  Future<void> _manualImport() async {
    final res = await FilePicker.platform.pickFiles();
    if (res?.files.single.path == null) return;
    await _service.manualImport(File(res!.files.single.path!));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content:
              Text('Data merged in. Thank you for keeping things together.')),
    );
  }

  /// Family share: chosen events + `family`-tagged moments — or, in full
  /// care mode, everything.
  Future<void> _exportFamilyShare() async {
    final f = await BnsExporter.exportFamilyShare();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(_fullCareMode
              ? 'Family file saved: ${f.path.split(Platform.pathSeparator).last} — '
                  'full care: everything is inside, for the people who care.'
              : 'Family file saved: ${f.path.split(Platform.pathSeparator).last} — '
                  'only what you marked, nothing else.')),
    );
  }

  /// FULL CARE MODE — the last resort for the severely impaired. Turning it
  /// ON is deliberately heavy (typed confirmation); turning it OFF is one
  /// tap — reducing sharing must always be the easy direction.
  Future<void> _setFullCareMode(bool v) async {
    final s = await IsarService.getSettings();
    if (!v) {
      await IsarService.updateSettings(s.copyWith(fullCareMode: false));
      setState(() => _fullCareMode = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Full care is off. Only chosen things are shared.')));
      return;
    }
    final nameCtrl = TextEditingController();
    final expected = s.effectiveShareName.trim();
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Full care — a serious step'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This is for when someone needs the people around them to know '
              'everything — every thought, every voice note, every day. The '
              'family file will contain it all, and trusted devices already '
              'receive it all.\n\n'
              'It exists for the hardest situations, decided together with '
              'the people who care. Turning it off later is one tap.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            Text('To turn it on, type the share name ("$expected"):',
                style: const TextStyle(fontSize: 13)),
            TextField(controller: nameCtrl, autofocus: true),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Not now')),
          FilledButton(
              onPressed: () => Navigator.pop(
                  c, nameCtrl.text.trim().toLowerCase() ==
                      expected.toLowerCase()),
              child: const Text('Turn on full care')),
        ],
      ),
    );
    if (confirmed != true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Nothing changed — full care stays off.')));
      }
      return;
    }
    await IsarService.updateSettings(s.copyWith(fullCareMode: true));
    setState(() => _fullCareMode = true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Full care is on. Everything travels to the people who care.')));
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
      appBar:
          const BnsAppBar(title: 'Sync your devices', hideOnDesktopWide: true),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Encouraging header
          Text(
            'Everything you do is kept safe for you.\nSet up once — then it just happens.',
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
                      Text(_progress.error!,
                          style: const TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 16),

          // Trusted / Known devices
          Text('Your trusted devices',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_trusted.isEmpty)
            const Text(
                'No devices paired yet. Discover one below to start a secure connection.'),
          ..._trusted.map((d) => Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                  child: Column(
                    children: [
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.phone_android),
                        title: Text(d.name),
                        subtitle: Text(
                            'Last synced: ${d.lastSyncedAt.toLocal().toString().substring(0, 16)}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Forget this device (un-pair)',
                          onPressed: () => _forget(d),
                        ),
                      ),
                      SwitchListTile(
                        dense: true,
                        title: const Text('LAN transfers allowed'),
                        subtitle: const Text(
                            'We advise keeping this on for your own devices. Off = still paired, but nothing flows either way.'),
                        value: d.lanSyncAllowed,
                        onChanged: (v) =>
                            _updateTrustedDevice(d.copyWith(lanSyncAllowed: v)),
                      ),
                      SwitchListTile(
                        dense: true,
                        title: const Text('Auto-sync when nearby'),
                        value: d.autoSyncEnabled,
                        onChanged: (v) => _updateTrustedDevice(
                            d.copyWith(autoSyncEnabled: v)),
                      ),
                    ],
                  ),
                ),
              )),

          const SizedBox(height: 24),

          // Auto-sync toggle
          SwitchListTile(
            title: const Text('Auto-sync when trusted devices are nearby'),
            subtitle: const Text(
                'Happens gently in the background when this screen is open'),
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
                  Text('History retention (keeps files small for fast sync)',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                      'Current: ${_retentionDays == 0 ? "Unlimited (10000 years mode)" : "$_retentionDays days (default 14 = 2 weeks)"}'),
                  const SizedBox(height: 8),
                  Text(
                    'Old days auto-delete as time passes. New days open up. Routines stay. You can plan far into the future.',
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
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
                  // User types/roles for adaptation - normal (TBI like regular joe), kid-ADHD, ADHD, custom (penguin - we secure the penguin)
                  // Affects UI (brighter for fog, simpler for kids), fluent for all. Don't check names, care about mind.
                  Text(
                      'Your type (adapts UI brighter/simpler, fluent for kids):',
                      style: TextStyle(fontSize: 11)),
                  DropdownButton<String>(
                    value: _userType,
                    items: ['normal', 'kid-ADHD', 'ADHD', 'custom (penguin)']
                        .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                        .toList(),
                    onChanged: (v) async {
                      if (v != null) {
                        final s = await IsarService.getSettings();
                        await IsarService.updateSettings(
                            s.copyWith(userType: v));
                        await _loadRetention();
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(
                                'Type set to $v - UI adapts (brighter for fog, kid-fluent)')));
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  // Widget forward days - user controls to avoid stress. Default 2 (regular joe preference, no more than 2 days ahead)
                  Text(
                      'Widget forward days (set low to reduce stress - you control what you see):',
                      style: TextStyle(fontSize: 11)),
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
                  const SizedBox(height: 12),
                  // Family-facing share name — what a trusted person (e.g.
                  // dad checking in) sees when this device asks to pair/sync.
                  Text('Your share name (what family sees when you share):',
                      style: TextStyle(fontSize: 11)),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                            _shareName.isEmpty
                                ? '$_deviceName (using device name)'
                                : _shareName,
                            style:
                                const TextStyle(fontWeight: FontWeight.w500)),
                      ),
                      TextButton(
                        onPressed: () async {
                          final ctrl = TextEditingController(text: _shareName);
                          final newName = await showDialog<String>(
                            context: context,
                            builder: (c) => AlertDialog(
                              title: const Text('Your share name'),
                              content: TextField(
                                controller: ctrl,
                                autofocus: true,
                                decoration: const InputDecoration(
                                  labelText: 'Name people see',
                                  hintText: 'e.g. Yossi',
                                ),
                              ),
                              actions: [
                                TextButton(
                                    onPressed: () => Navigator.pop(c),
                                    child: const Text('Cancel')),
                                FilledButton(
                                    onPressed: () =>
                                        Navigator.pop(c, ctrl.text),
                                    child: const Text('Save')),
                              ],
                            ),
                          );
                          if (newName != null) await _setShareName(newName);
                        },
                        child: const Text('Edit'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Device name for friendly discovery
                  Text('This device name (seen by others on Wi-Fi):',
                      style: TextStyle(fontSize: 11)),
                  Row(
                    children: [
                      Expanded(
                        child: Text(_deviceName,
                            style:
                                const TextStyle(fontWeight: FontWeight.w500)),
                      ),
                      TextButton(
                        onPressed: () async {
                          final ctrl = TextEditingController(text: _deviceName);
                          final newName = await showDialog<String>(
                            context: context,
                            builder: (c) => AlertDialog(
                              title: const Text('Name this device'),
                              content: TextField(
                                  controller: ctrl,
                                  decoration: const InputDecoration(
                                      labelText: 'Device name')),
                              actions: [
                                TextButton(
                                    onPressed: () => Navigator.pop(c),
                                    child: const Text('Cancel')),
                                FilledButton(
                                    onPressed: () =>
                                        Navigator.pop(c, ctrl.text),
                                    child: const Text('Save')),
                              ],
                            ),
                          );
                          if (newName != null) await _setDeviceName(newName);
                        },
                        child: const Text('Edit'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    dense: true,
                    title: const Text(
                        'Quiet mode (less animations, confetti, sounds)'),
                    value: _quietMode,
                    onChanged: _setQuietMode,
                  ),
                  SwitchListTile(
                    dense: true,
                    title: const Text('Keep a ready-to-share .bns fresh'),
                    subtitle: const Text(
                        'Silently refreshes BNS_Latest on close/background — a current backup always exists without exporting.'),
                    value: _autoImage,
                    onChanged: _setAutoImage,
                  ),

                  const SizedBox(height: 16),
                  const Divider(),
                  // === PC Keybinds (robust PC primary experience) ===
                  // Set & forget. Tick the ones you want active.
                  // We give you a simple basic layout. Typing is #1 on PC.
                  // Changes saved into your .bns — travels everywhere.
                  Text('PC Keybinds — set & forget (primary on PC)',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    'Tick to activate. Click a combo and press new keys to change it. '
                    'Applies immediately and travels in your .bns. Not forced — use what feels good.',
                    style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  ..._buildKeybindRows(),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Discovered devices
          Text('Devices found on your Wi-Fi',
              style: Theme.of(context).textTheme.titleMedium),
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
          Text('Manual backup (for USB or when Wi-Fi is not available)',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
                child: OutlinedButton.icon(
                    onPressed: _manualExport,
                    icon: const Icon(Icons.save),
                    label: const Text('Export .bns'))),
            const SizedBox(width: 12),
            Expanded(
                child: OutlinedButton.icon(
                    onPressed: _manualImport,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Import .bns'))),
          ]),

          const SizedBox(height: 16),
          Text('Family share',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            _fullCareMode
                ? 'Full care is ON: the family file carries everything — every '
                    'plan, every moment, every voice note — for the people '
                    'easing the path.'
                : 'A small file with ONLY what was chosen: plans marked '
                    '"family can know" and moments tagged "family" (voice '
                    'notes included). Nothing else is inside it, no matter '
                    'how it\'s opened.',
            style: TextStyle(
                fontSize: 12.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
              onPressed: _exportFamilyShare,
              icon: const Icon(Icons.family_restroom),
              label: const Text('Make the family file')),
          const SizedBox(height: 8),
          SwitchListTile(
            dense: true,
            title: const Text('Full care (last resort)'),
            subtitle: const Text(
                'For the hardest situations: everything matters, everything '
                'is shared with the people who care. Guarded to turn on, one '
                'tap to turn off.',
                style: TextStyle(fontSize: 12)),
            value: _fullCareMode,
            onChanged: _setFullCareMode,
          ),

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

/// Press-to-record keybind dialog. No syntax to type or remember:
/// the user presses the keys, sees them written out, and saves.
class _ComboRecorderDialog extends StatefulWidget {
  final String actionLabel;

  const _ComboRecorderDialog({required this.actionLabel});

  @override
  State<_ComboRecorderDialog> createState() => _ComboRecorderDialogState();
}

class _ComboRecorderDialogState extends State<_ComboRecorderDialog> {
  final _focusNode = FocusNode();
  String? _combo;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('New keys for "${widget.actionLabel}"'),
      content: Focus(
        focusNode: _focusNode,
        autofocus: true,
        // Swallow every key so the app's live shortcuts don't fire mid-recording.
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            // Esc always escapes (no keybind should ever be plain Escape).
            if (event.logicalKey == LogicalKeyboardKey.escape &&
                !HardwareKeyboard.instance.isControlPressed &&
                !HardwareKeyboard.instance.isAltPressed &&
                !HardwareKeyboard.instance.isMetaPressed) {
              Navigator.pop(context);
              return KeyEventResult.handled;
            }
            final combo = Keybinds.comboFromEvent(event);
            if (combo != null) setState(() => _combo = combo);
          }
          return KeyEventResult.handled;
        },
        child: SizedBox(
          width: 280,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Press the combination you want. Take your time.'),
              const SizedBox(height: 20),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .primaryContainer
                      .withOpacity(0.4),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _combo == null
                      ? 'Waiting for keys…'
                      : Keybinds.pretty(_combo!),
                  style: const TextStyle(
                      fontSize: 20,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel — keep the old keys'),
        ),
        FilledButton(
          onPressed:
              _combo == null ? null : () => Navigator.pop(context, _combo),
          child: const Text('Use these keys'),
        ),
      ],
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
      title: const Text('Secure Pairing'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Type this code on $peerName (open its Sync screen):'),
          const SizedBox(height: 24),
          Text(
            code,
            style: Theme.of(context).textTheme.displayLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 8,
                ),
          ),
          const SizedBox(height: 16),
          const Text(
              'The code never leaves this screen — only someone who can read it here can pair.'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: onConfirm,
          child: const Text('I typed it there — connect securely'),
        ),
      ],
    );
  }
}

/// Receiver side of pairing: type the 6-digit code shown on the other device.
class _EnterCodeDialog extends StatefulWidget {
  final String peerName;

  const _EnterCodeDialog({required this.peerName});

  @override
  State<_EnterCodeDialog> createState() => _EnterCodeDialogState();
}

class _EnterCodeDialogState extends State<_EnterCodeDialog> {
  final _codeController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('"${widget.peerName}" wants to pair'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
              'Enter the 6-digit code shown on that device. If you didn\'t expect this, just decline — nothing is shared.'),
          const SizedBox(height: 16),
          TextField(
            controller: _codeController,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            style: const TextStyle(fontSize: 28, letterSpacing: 8),
            textAlign: TextAlign.center,
            decoration: const InputDecoration(
                border: OutlineInputBorder(), counterText: ''),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Decline'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _codeController.text.trim()),
          child: const Text('Pair securely'),
        ),
      ],
    );
  }
}
