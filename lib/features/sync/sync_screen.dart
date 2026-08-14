import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:async';
import 'dart:io';

import 'package:bns/core/i18n/l.dart';
import 'package:bns/core/keybinds.dart';
import 'package:bns/core/sync_policy.dart';
import 'package:bns/data/local/bns_home.dart';
import 'package:bns/features/sync/pairing_dialogs.dart';
import 'package:bns/providers/app_providers.dart';
import 'package:bns/data/export/bns_exporter.dart';
import 'package:bns/data/export/bns_save_out.dart';
import 'package:bns/data/local/isar_service.dart';
import 'package:bns/data/sync/lan_sync_service.dart'
    show BnsPeer, LanSyncService;
import 'package:bns/core/models/trusted_device.dart';
import 'package:bns/data/sync/sync_progress.dart';
import 'package:bns/platform/android_widget.dart';
import 'package:bns/services/notifications_service.dart';
import 'package:bns/services/vosk_service.dart';
import 'package:bns/services/whisper_service.dart';
import 'package:bns/ui/theme.dart';
import 'package:bns/ui/widgets/bns_app_bar.dart';
import 'package:path/path.dart' as path_util;
import 'package:path_provider/path_provider.dart';

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
  // The app's one running service — the screen looks in on it, never
  // owns it (discovery must not stop when this screen closes).
  final LanSyncService _service = LanSyncService.instance;

  List<BnsPeer> _discovered = [];
  List<TrustedDevice> _trusted = [];
  SyncProgress _progress = SyncProgress.idle;
  StreamSubscription<List<BnsPeer>>? _peersSub;
  StreamSubscription<SyncProgress>? _progressSub;
  bool _seekBusy = false;
  bool _autoSync = true;
  bool _quietMode = false;
  // Reminders — the person's own knobs (level 1-2 wave, 2026-08-08).
  bool _notificationsEnabled = true;
  String _reminderStyle = 'gentle';
  String _notificationColor = 'auto';
  int _eventReminderMinutes = 30;
  // How long an untouched reminder waits in the shade (0 = until seen).
  int _reminderTimeoutMinutes = 120;
  // Owl time: the hour the person's day ends (0 = midnight).
  int _dayRolloverHour = 0;
  bool _sttEnabled = true;
  bool _autoImage = true;
  String _homePath = '';
  int _retentionDays = 20;
  int _widgetForwardDays = 2;
  String _userType = 'normal';
  String _deviceName = 'My BNS Device';
  String _shareName = '';
  bool _fullCareMode = false;
  bool _guidedMode = false;
  // The care spectrum as ONE visible choice (1..4) — the card is the story,
  // the two switches below stay as the fine-grained controls.
  int _careLevel = 1;
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
    _guidedMode = settings.guidedMode;
    _careLevel = settings.careLevel;
    _autoSync = true; // default; could persist per device but simple
    _quietMode = settings.quietMode;
    _notificationsEnabled = settings.notificationsEnabled;
    _reminderStyle = settings.reminderStyle;
    _notificationColor = settings.notificationColor;
    _eventReminderMinutes = settings.eventReminderMinutes;
    _reminderTimeoutMinutes = settings.reminderTimeoutMinutes;
    _dayRolloverHour = settings.dayRolloverHour;
    _sttEnabled = settings.sttEnabled;
    _autoImage = settings.autoImageEnabled;
    _keybinds = Map<String, String>.from(settings.keybinds);
    _enabledKeybinds = Map<String, bool>.from(settings.enabledKeybinds);
    _appLanguage = settings.appLanguage;
    _caregiverDevice = settings.caregiverDevice;
    _homePath = await BnsHome.currentPath();
    _refreshVoskStatus();

    // (Receiver-side pairing prompts are app-wide now — main.dart installs
    // the handler, so a request lands even when this screen is closed.)

    await _service.start(
        deviceName: settings.effectiveShareName, autoSync: _autoSync);

    // Discovery has been running since launch — show what it already knows,
    // and knock right now so known devices light up without the 5s wait.
    _discovered = _service.currentPeers;
    _service.pokeDiscovery();

    _peersSub = _service.peersStream.listen((p) {
      if (mounted) setState(() => _discovered = p);
    });

    _progressSub = _service.progressStream.listen((p) {
      if (!mounted) return;
      setState(() => _progress = p);
      // A finished sync refreshes "last synced" on the device cards.
      if (p.isComplete) _loadTrusted();
    });

    _loadTrusted();
    if (mounted) setState(() {});
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
        _notificationsEnabled = s.notificationsEnabled;
        _reminderStyle = s.reminderStyle;
        _notificationColor = s.notificationColor;
        _eventReminderMinutes = s.eventReminderMinutes;
        _reminderTimeoutMinutes = s.reminderTimeoutMinutes;
        _dayRolloverHour = s.dayRolloverHour;
        _sttEnabled = s.sttEnabled;
        _autoImage = s.autoImageEnabled;
        _fullCareMode = s.fullCareMode;
        _guidedMode = s.guidedMode;
        _careLevel = s.careLevel;
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
              ? L.t('Unlimited retention (large files possible)',
                  'שמירה ללא הגבלה (ייתכנו קבצים גדולים)')
              : L.t('Retention set to $days days',
                  'ההיסטוריה תישמר $days ימים'))),
    );
  }

  Future<void> _resetRetention() async {
    await IsarService.resetRetentionToDefault();
    await _loadRetention();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(L.t('Back to keeping 15 days of history',
              'חזרנו לשמירת 15 ימי היסטוריה'))),
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
          content: Text(L.t(
              'Device named "$name". Your other devices will see this.',
              'המכשיר נקרא עכשיו "$name". המכשירים האחרים שלך יראו את זה.'))),
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
              ? L.t('Sharing as "${updated.deviceName}" (device name).',
                  'משתפים בשם "${updated.deviceName}" (שם המכשיר).')
              : L.t('People you trust will see you as "${name.trim()}".',
                  'אנשים שאתה סומך עליהם יראו אותך בתור "${name.trim()}".'))),
    );
  }

  Future<void> _setAutoImage(bool v) async {
    final s = await IsarService.getSettings();
    await IsarService.updateSettings(s.copyWith(autoImageEnabled: v));
    await _loadRetention();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(v
              ? L.t('A fresh .bns will quietly stay ready to share.',
                  'קובץ .bns טרי יישאר מוכן לשיתוף, בשקט.')
              : L.t('Auto-imaging off. Manual Export still works anytime.',
                  'גיבוי אוטומטי כבוי. ייצוא ידני עדיין עובד בכל רגע.'))));
    }
  }

  Future<void> _setQuietMode(bool v) async {
    final s = await IsarService.getSettings();
    await IsarService.updateSettings(s.copyWith(quietMode: v));
    await _loadRetention();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(v
              ? L.t('Quiet mode on — less stimulation.',
                  'מצב שקט פועל — פחות גירויים.')
              : L.t('Quiet mode off.', 'מצב שקט כבוי.'))),
    );
  }

  // ---- Reminders: the person's own knobs ----

  Future<void> _setNotificationsEnabled(bool v) async {
    final s = await IsarService.getSettings();
    await IsarService.updateSettings(s.copyWith(notificationsEnabled: v));
    // Right now, not in two seconds — flipping the switch should be felt.
    await NotificationsService.rescheduleAll(force: true);
    await _loadRetention();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(v
            ? L.t('Reminders are on — a soft nudge at the times you chose.',
                'התזכורות פועלות — נגיעה רכה בזמנים שבחרת.')
            : L.t('Reminders are off. Everything still waits for you inside.',
                'התזכורות כבויות. הכול עדיין מחכה לך בפנים.'))));
  }

  Future<void> _setReminderStyle(String v) async {
    final s = await IsarService.getSettings();
    await IsarService.updateSettings(s.copyWith(reminderStyle: v));
    await NotificationsService.rescheduleAll(force: true);
    await _loadRetention();
  }

  Future<void> _setNotificationColor(String v) async {
    final s = await IsarService.getSettings();
    await IsarService.updateSettings(s.copyWith(notificationColor: v));
    await NotificationsService.rescheduleAll(force: true);
    await _loadRetention();
  }

  Future<void> _setEventReminderMinutes(int v) async {
    final s = await IsarService.getSettings();
    await IsarService.updateSettings(s.copyWith(eventReminderMinutes: v));
    await NotificationsService.rescheduleAll(force: true);
    await _loadRetention();
  }

  Future<void> _setReminderTimeoutMinutes(int v) async {
    final s = await IsarService.getSettings();
    await IsarService.updateSettings(s.copyWith(reminderTimeoutMinutes: v));
    await NotificationsService.rescheduleAll(force: true);
    await _loadRetention();
  }

  /// Owl time: move the border of the day. Reminders reschedule (weekly
  /// small-hour ones shift to the right calendar night) and the widget
  /// redraws with the right "today".
  Future<void> _setDayRolloverHour(int v) async {
    final s = await IsarService.getSettings();
    await IsarService.updateSettings(s.copyWith(dayRolloverHour: v));
    await NotificationsService.rescheduleAll(force: true);
    AndroidBnsWidget.updateWidget();
    await _loadRetention();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(v == 0
            ? L.t('Your day ends at midnight — the classic way.',
                'היום שלך נגמר בחצות — הדרך הקלאסית.')
            : L.t(
                'Your day now ends at 0$v:00. The night hours stay part '
                'of tonight — owls are normal here.',
                'היום שלך נגמר עכשיו ב-0$v:00. שעות הלילה נשארות חלק '
                'מהלילה הזה — ינשופים הם הנורמלים כאן.'))));
  }

  /// Person-facing names for the user types (values stay identifiers).
  static String _userTypeName(String key) => switch (key) {
        'normal' => L.t('Regular', 'רגיל'),
        'kid-ADHD' => L.t('Kid (ADHD)', 'ילד/ה (קשב)'),
        'ADHD' => L.t('ADHD', 'קשב וריכוז'),
        'custom (penguin)' => L.t('Custom (penguin)', 'מותאם (פינגווין)'),
        _ => key,
      };

  /// The person-facing names of the reminder colors (keys stay English —
  /// they are identifiers that travel in the .bns).
  static String _colorName(String key) => switch (key) {
        'teal' => L.t('Teal', 'טורקיז'),
        'lavender' => L.t('Lavender', 'לבנדר'),
        'green' => L.t('Green', 'ירוק'),
        'amber' => L.t('Amber', 'ענבר'),
        'rose' => L.t('Rose', 'ורוד'),
        'sky' => L.t('Sky', 'תכלת'),
        _ => key,
      };

  // The open-source ear on this PC (Vosk): '' = not checked yet.
  String _voskStatus = '';
  bool _voskBusy = false;

  // The app's language — Hebrew first, the whole tree re-skins live.
  String _appLanguage = 'he';

  // Is THIS device the helper's? (Never shown on the other person's screen.)
  bool _caregiverDevice = false;

  Future<void> _setCaregiverDevice(bool v) async {
    final s = await IsarService.getSettings();
    await IsarService.updateSettings(s.copyWith(caregiverDevice: v));
    // Reminders belong to the person being helped, not the helper.
    await NotificationsService.rescheduleAll();
    if (mounted) setState(() => _caregiverDevice = v);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(v
            ? L.t(
                'This device is set up as a helper\'s. Reminders here are '
                'off — they belong to the person you help. Nothing changed '
                'on their device.',
                'המכשיר הזה מוגדר כמכשיר של מלווה. התזכורות כאן כבויות — '
                'הן שייכות למי שאתה מלווה. שום דבר לא השתנה אצלו.')
            : L.t('This device is your own again — reminders are back on.',
                'המכשיר הזה שוב שלך — התזכורות חזרו.'))));
  }

  Future<void> _setAppLanguage(String lang) async {
    final s = await IsarService.getSettings();
    await IsarService.updateSettings(s.copyWith(appLanguage: lang));
    ref.invalidate(settingsProvider); // BnsApp watches — RTL flips on the spot
    if (mounted) setState(() => _appLanguage = lang);
  }

  Future<String> _voskDir() async =>
      path_util.join((await getApplicationSupportDirectory()).path, 'vosk');

  Future<String> _whisperDir() async =>
      path_util.join((await getApplicationSupportDirectory()).path, 'whisper');

  Future<void> _refreshVoskStatus() async {
    if (!Platform.isWindows) return;
    // Whisper is the ear that knows Hebrew; Vosk (English-only) still
    // counts as installed for anyone who set it up earlier.
    final hasWhisper = WhisperService.isInstalled(await _whisperDir());
    final hasVosk = VoskService.isInstalled(await _voskDir());
    if (mounted) {
      setState(() => _voskStatus = hasWhisper
          ? L.t(
              'Installed — recordings on this PC become words by themselves, '
              'in Hebrew and in English.',
              'מותקן — הקלטות במחשב הזה הופכות למילים מעצמן, בעברית ובאנגלית.')
          : hasVosk
              ? L.t(
                  'English ears installed. Install again to add Hebrew.',
                  'מותקנות אוזניים לאנגלית. אפשר להתקין שוב כדי להוסיף עברית.')
              : L.t('Not installed yet.', 'עוד לא מותקן.'));
    }
  }

  Future<void> _installVosk() async {
    if (_voskBusy) return;
    setState(() => _voskBusy = true);
    try {
      await WhisperService.install(await _whisperDir(), onStatus: (s) {
        if (mounted) setState(() => _voskStatus = s);
      });
    } catch (e) {
      if (mounted) {
        setState(() => _voskStatus = L.t(
            'Could not fetch it right now — try again later.',
            'לא הצלחנו להוריד כרגע — אפשר לנסות שוב מאוחר יותר.'));
      }
    } finally {
      if (mounted) setState(() => _voskBusy = false);
      await _refreshVoskStatus();
    }
  }

  Future<void> _setSttEnabled(bool v) async {
    final s = await IsarService.getSettings();
    await IsarService.updateSettings(s.copyWith(sttEnabled: v));
    await _loadRetention();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(v
              ? L.t('Speech-to-text on — your voice becomes text everywhere.',
                  'דיבור-לטקסט פועל — הקול שלך הופך לטקסט בכל מקום.')
              : L.t('Speech-to-text off. Voice notes still record as audio.',
                  'דיבור-לטקסט כבוי. הקלטות קול עדיין נשמרות כאודיו.'))),
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
            content: Text(L.t(
                '${Keybinds.labelFor(id)} is now ${Keybinds.pretty(combo)}. Active right away.',
                '${Keybinds.labelFor(id)} הוגדר עכשיו ל-${Keybinds.pretty(combo)}. פעיל מיד.'))),
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
              ? L.t('Keybind enabled.', 'קיצור המקשים הופעל.')
              : L.t('Keybind disabled (still saved).',
                  'קיצור המקשים כבוי (עדיין שמור).'))),
    );
  }

  Future<void> _resetKeybinds() async {
    await IsarService.resetKeybindsToDefault();
    await _loadRetention();
    ref.invalidate(settingsProvider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(L.t('Keybinds back to the simple default layout.',
                'קיצורי המקשים חזרו לברירת המחדל הפשוטה.'))),
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
              message: L.t('Click, then press the new keys',
                  'לחץ, ואז הקש את המקשים החדשים'),
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
              isEnabled ? L.t('active', 'פעיל') : L.t('off', 'כבוי'),
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
          label: Text(L.t('Return to simple default layout',
              'חזרה לפריסה הפשוטה')),
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
          content: Text(L.t(
              'Widget will show next $days days forward (less stress for you)',
              'הווידג׳ט יציג $days ימים קדימה (פחות עומס בשבילך)'))),
    );
    AndroidBnsWidget.updateWidget();
  }

  /// Sync with a trusted device even when discovery hasn't spotted it yet —
  /// knock directly on its last known address. Syncing must never wait for
  /// "seeking" (owner, 2026-08-09: "why are we seeking for new ones and not
  /// syncing the devices — that is what important").
  Future<void> _syncTrusted(TrustedDevice d) async {
    final peer = _peerFor(d) ??
        BnsPeer(
          deviceName: d.name,
          address: d.lastAddress,
          port: LanSyncService.transferPort,
          lastSeen: DateTime.now(),
          deviceId: d.id,
        );
    await _service.syncWithPeer(peer);
    await _loadTrusted();
  }

  BnsPeer? _peerFor(TrustedDevice d) {
    for (final p in _discovered) {
      if (p.deviceId == d.id) return p;
    }
    return null;
  }

  bool _isOnline(TrustedDevice d) {
    final p = _peerFor(d);
    return p != null && peerLooksOnline(p.lastSeen, DateTime.now());
  }

  /// One step: the dialog opens with the code AND the request already on
  /// its way — the other device asks for the code right now, while the
  /// person reads it here. The first sync afterwards doubles as the code
  /// check, so a mistyped code is caught and said out loud, not silently
  /// broken forever.
  Future<void> _startPairing(BnsPeer peer) async {
    final paired = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ShowCodeDialog(
        peerName: peer.deviceName,
        generateCode: _service.generatePairingCode,
        sendRequest: (code) => _service.requestPairing(peer, code),
      ),
    );
    if (paired != true) return;
    await _loadTrusted();
    await _service.verifyNewPairing(peer);
    await _loadTrusted();
  }

  Future<void> _seekAgain() async {
    setState(() => _seekBusy = true);
    _service.pokeDiscovery();
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _seekBusy = false);
  }

  /// One paired device: always visible (online or not), status at a glance,
  /// one big Sync button. The fiddly switches live behind "More".
  Widget _trustedCard(TrustedDevice d) {
    final theme = Theme.of(context);
    final online = _isOnline(d);
    final syncing = _service.isSyncingWith(d.id);
    final when = d.lastSyncedAt.toLocal().toString().substring(0, 16);
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: Icon(Icons.circle,
                size: 14,
                color: online
                    ? const Color(0xFF22C55E)
                    : theme.colorScheme.outlineVariant),
            title: Text(d.name,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(
              online
                  ? L.t('On the network now · synced $when',
                      'ברשת עכשיו · סונכרן $when')
                  : L.t(
                      'Not nearby right now · synced $when — syncs the '
                      'moment it returns',
                      'לא בסביבה כרגע · סונכרן $when — יסתנכרן ברגע שיחזור'),
              style: const TextStyle(fontSize: 12),
            ),
            trailing: FilledButton.icon(
              // Mid-sync the button becomes a spinner and stops taking
              // presses — six taps must not mean six syncs and six toasts.
              onPressed: syncing ? null : () => _syncTrusted(d),
              icon: syncing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.sync, size: 18),
              label: Text(syncing
                  ? L.t('Syncing…', 'מסנכרן…')
                  : L.t('Sync now', 'סנכרן עכשיו')),
            ),
          ),
          ExpansionTile(
            shape: const Border(),
            collapsedShape: const Border(),
            tilePadding: const EdgeInsets.symmetric(horizontal: 16),
            title: Text(L.t('More', 'עוד'),
                style: TextStyle(
                    fontSize: 13, color: theme.colorScheme.onSurfaceVariant)),
            children: [
              SwitchListTile(
                dense: true,
                title: Text(
                    L.t('LAN transfers allowed', 'העברות ברשת הביתית מותרות')),
                subtitle: Text(L.t(
                    'Off = still paired, but nothing flows either way.',
                    'כבוי = עדיין מצומד, אבל שום דבר לא עובר לשום כיוון.')),
                value: d.lanSyncAllowed,
                onChanged: (v) =>
                    _updateTrustedDevice(d.copyWith(lanSyncAllowed: v)),
              ),
              SwitchListTile(
                dense: true,
                title: Text(L.t('Sync by itself with this device',
                    'סנכרון מעצמו עם המכשיר הזה')),
                value: d.autoSyncEnabled,
                onChanged: (v) =>
                    _updateTrustedDevice(d.copyWith(autoSyncEnabled: v)),
              ),
              ListTile(
                dense: true,
                leading: Icon(Icons.link_off, color: theme.colorScheme.error),
                title: Text(L.t('End the connection (un-pair)',
                    'ניתוק החיבור (ביטול צימוד)')),
                onTap: () => _forget(d),
              ),
              const SizedBox(height: 4),
            ],
          ),
        ],
      ),
    );
  }

  /// Seeking a NEW device is a deliberate, separate act with its own corner —
  /// it never stands between the person and everyday syncing.
  Widget _addDeviceCard() {
    final theme = Theme.of(context);
    final unknown = _discovered
        .where((p) => !_trusted.any((t) => t.id == p.deviceId))
        .toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.add_link),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(L.t('Add a new device', 'הוספת מכשיר חדש'),
                      style: theme.textTheme.titleSmall),
                ),
                _seekBusy
                    ? const Padding(
                        padding: EdgeInsets.all(8),
                        child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : TextButton.icon(
                        onPressed: _seekAgain,
                        icon: const Icon(Icons.refresh, size: 18),
                        label: Text(L.t('Look again', 'חפש שוב')),
                      ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              L.t(
                  'Open BNS on the other device and it will appear here. '
                  'Pairing asks for a code once — after that, the two sync '
                  'by themselves.',
                  'פתח את BNS במכשיר השני והוא יופיע כאן. הצימוד מבקש קוד '
                  'פעם אחת — ומשם, השניים מסתנכרנים מעצמם.'),
              style: TextStyle(
                  fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
            ),
            if (unknown.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  L.t('No new devices in sight right now.',
                      'אין מכשירים חדשים באופק כרגע.'),
                  style: TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ...unknown.map((p) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.devices_other),
                  title: Text(p.deviceName),
                  subtitle:
                      Text(p.address, textDirection: TextDirection.ltr),
                  trailing: FilledButton.tonal(
                    onPressed: () => _startPairing(p),
                    child: Text(L.t('Pair', 'צימוד')),
                  ),
                )),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleAutoSync(bool v) async {
    setState(() => _autoSync = v);
    _service.setAutoSync(v);
  }

  /// Un-pairing is a real decision — it must be asked, never slipped
  /// (owner QA, 2026-07-27: "there is no warning, it's a bummer").
  Future<void> _forget(TrustedDevice d) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(L.t('End the connection with ${d.name}?',
            'לנתק את החיבור עם ${d.name}?')),
        content: Text(L.t(
            'That device will no longer receive anything from here, and '
            'this one stops accepting from it. Both sides are told. '
            'Nothing already saved is deleted — you can pair again anytime.',
            'המכשיר הזה לא יקבל יותר שום דבר מכאן, וגם לא נקבל ממנו. '
            'שני הצדדים יידעו על כך. שום דבר ששמור כבר לא נמחק — '
            'תמיד אפשר לצמד מחדש.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(L.t('Keep the connection', 'להשאיר את החיבור'))),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(c).colorScheme.error),
            child: Text(L.t('End it', 'לנתק')),
          ),
        ],
      ),
    );
    if (sure != true) return;
    await _service.forgetDevice(d.id);
    await _service.refreshTrustPolicy();
    await _loadTrusted();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(L.t(
            'Connection with ${d.name} ended. The other device was told.',
            'החיבור עם ${d.name} נותק. המכשיר השני יודע על כך.'))));
  }

  /// Save a per-device change (LAN allowed / auto-sync) and make the running
  /// sync service honor it immediately.
  Future<void> _updateTrustedDevice(TrustedDevice updated) async {
    await IsarService.saveTrustedDevice(updated);
    await _service.refreshTrustPolicy();
    await _loadTrusted();
  }

  /// Move the BNS home — data file, audio, exports — to a folder the
  /// person chooses. Copy-then-switch: the old folder stays as a backup.
  Future<void> _chooseHome() async {
    final picked = await FilePicker.platform.getDirectoryPath(
        dialogTitle: L.t('Choose where BNS keeps your data',
            'בחר איפה BNS ישמור את המידע שלך'));
    if (picked == null || picked.trim().isEmpty) return;
    if (!mounted) return;
    final sure = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(L.t('Move your BNS home?', 'להעביר את הבית של BNS?')),
        content: Text(L.t(
            'Everything — your data file, voice notes, and exports — will '
            'be copied to:\n\n$picked\n\nand live there from now on. The '
            'old copy stays where it is as a quiet backup. Nothing is '
            'deleted.',
            'הכול — קובץ המידע, הקלטות הקול והייצוא — יועתק אל:\n\n$picked'
            '\n\nויגור שם מעכשיו. העותק הישן נשאר במקומו כגיבוי שקט. '
            'שום דבר לא נמחק.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(L.t('Stay here', 'להישאר כאן'))),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(L.t('Move home', 'להעביר את הבית'))),
        ],
      ),
    );
    if (sure != true) return;
    try {
      final newPath = await IsarService.moveHome(picked);
      if (!mounted) return;
      setState(() => _homePath = newPath);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(L.t(
              'BNS moved home. Everything now lives in $newPath — the old '
              'copy stays as a backup.',
              'BNS עבר דירה. הכול גר עכשיו ב-$newPath — העותק הישן נשאר '
              'כגיבוי.'))));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(L.t('The move didn\'t complete: $e',
              'ההעברה לא הושלמה: $e'))));
    }
  }

  Future<void> _manualExport() async {
    final f = await _service.manualExport();
    if (!mounted) return;
    // A backup the person cannot find is not a backup: the phone gets the
    // system save sheet so the file lands in a real folder they chose
    // (owner QA, 2026-08-15 — it "saved" into app-private storage, which
    // no file manager can open and an uninstall erases).
    final out = await BnsSaveOut.saveCopy(
      f,
      dialogTitle: L.t('Where should the backup go?', 'לאן לשמור את הגיבוי?'),
    );
    if (!mounted) return;
    _tellWhereItWent(out, f);
  }

  /// Say plainly where a .bns ended up — folder and all. "Saved: name.bns"
  /// told the person nothing they could act on.
  void _tellWhereItWent(SavedOut out, File internal) {
    final String msg;
    if (out.cancelled) {
      msg = L.t(
          'Not saved out. The backup is still kept inside BNS — you can '
              'export it again any time.',
          'לא נשמר החוצה. הגיבוי עדיין שמור בתוך BNS — אפשר לייצא שוב מתי שרוצים.');
    } else if (out.reachable && BnsSaveOut.needsSystemSheet) {
      msg = L.t('Backup saved where you chose. ✓',
          'הגיבוי נשמר איפה שבחרת. ✓');
    } else if (out.reachable) {
      msg = L.t('Backup saved in: ${BnsSaveOut.folderOf(out.path!)}',
          'הגיבוי נשמר בתיקייה: ${BnsSaveOut.folderOf(out.path!)}');
    } else {
      msg = L.t(
          'The backup is kept inside BNS, but this device would not let it '
              'be saved out. Sync to another device to keep a copy safe.',
          'הגיבוי שמור בתוך BNS, אבל המכשיר הזה לא אפשר לשמור אותו החוצה. '
              'אפשר לסנכרן למכשיר אחר כדי לשמור עותק בטוח.');
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      duration: const Duration(seconds: 6),
    ));
  }

  Future<void> _manualImport() async {
    final res = await FilePicker.platform.pickFiles();
    if (res?.files.single.path == null) return;
    await _service.manualImport(File(res!.files.single.path!));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(L.t(
              'Data merged in. Thank you for keeping things together.',
              'המידע מוזג פנימה. תודה שאתה שומר שהכול יישאר יחד.'))),
    );
  }

  /// Family share: chosen events + `family`-tagged moments — or, in full
  /// care mode, everything.
  Future<void> _exportFamilyShare() async {
    final f = await BnsExporter.exportFamilyShare();
    if (!mounted) return;
    // This file exists to be HANDED to someone — it has to be able to
    // leave the phone, or the family sharing spectrum stops at level 1.
    final out = await BnsSaveOut.saveCopy(
      f,
      dialogTitle:
          L.t('Where should the family file go?', 'לאן לשמור את קובץ המשפחה?'),
    );
    if (!mounted) return;
    if (out.cancelled) {
      _tellWhereItWent(out, f);
      return;
    }
    final where = out.reachable && !BnsSaveOut.needsSystemSheet
        ? L.t(' — in: ${BnsSaveOut.folderOf(out.path!)}',
            ' — בתיקייה: ${BnsSaveOut.folderOf(out.path!)}')
        : '';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          duration: const Duration(seconds: 6),
          content: Text(_fullCareMode
              ? L.t(
                  'Family file saved$where — full care: everything is inside, '
                      'for the people who care.',
                  'קובץ המשפחה נשמר$where — טיפול מלא: הכול בפנים, '
                      'בשביל האנשים שאכפת להם.')
              : L.t(
                  'Family file saved$where — only what you marked, nothing else.',
                  'קובץ המשפחה נשמר$where — רק מה שסימנת, שום דבר מעבר.'))),
    );
  }

  /// FULL CARE MODE — the last resort for the severely impaired. Turning it
  /// ON is deliberately heavy (typed confirmation); turning it OFF is one
  /// tap — reducing sharing must always be the easy direction.
  /// Returns true when the change was applied, false when the person
  /// cancelled — so the care-level selector can snap back untouched.
  Future<bool> _setFullCareMode(bool v) async {
    final s = await IsarService.getSettings();
    if (!v) {
      await IsarService.updateSettings(s.copyWith(fullCareMode: false));
      setState(() => _fullCareMode = false);
      if (!mounted) return true;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(L.t(
              'Full care is off. Only chosen things are shared.',
              'טיפול מלא כבוי. רק דברים שבחרת משותפים.'))));
      return true;
    }
    final nameCtrl = TextEditingController();
    final expected = s.effectiveShareName.trim();
    if (!mounted) return false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(L.t('Full care — a serious step',
            'טיפול מלא — צעד רציני')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              L.t(
                  'This is for when someone needs the people around them to know '
                  'everything — every thought, every voice note, every day. The '
                  'family file will contain it all, and trusted devices already '
                  'receive it all.\n\n'
                  'It exists for the hardest situations, decided together with '
                  'the people who care. Turning it off later is one tap.',
                  'זה מיועד למצב שבו מישהו צריך שהאנשים סביבו יידעו הכול — '
                  'כל מחשבה, כל הקלטת קול, כל יום. קובץ המשפחה יכיל את הכול, '
                  'ומכשירים מהימנים כבר מקבלים את הכול.\n\n'
                  'זה קיים למצבים הקשים ביותר, בהחלטה משותפת עם האנשים '
                  'שאכפת להם. לכבות את זה אחר כך — נגיעה אחת.'),
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            Text(
                L.t('To turn it on, type the share name ("$expected"):',
                    'כדי להפעיל, הקלד את שם השיתוף ("$expected"):'),
                style: const TextStyle(fontSize: 13)),
            TextField(controller: nameCtrl, autofocus: true),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(L.t('Not now', 'לא עכשיו'))),
          FilledButton(
              onPressed: () => Navigator.pop(
                  c, nameCtrl.text.trim().toLowerCase() ==
                      expected.toLowerCase()),
              child: Text(L.t('Turn on full care', 'הפעל טיפול מלא'))),
        ],
      ),
    );
    if (confirmed != true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(L.t('Nothing changed — full care stays off.',
                'שום דבר לא השתנה — טיפול מלא נשאר כבוי.'))));
      }
      return false;
    }
    await IsarService.updateSettings(s.copyWith(fullCareMode: true));
    setState(() => _fullCareMode = true);
    if (!mounted) return true;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(L.t(
            'Full care is on. Everything travels to the people who care.',
            'טיפול מלא פועל. הכול מגיע לאנשים שאכפת להם.'))));
    return true;
  }

  /// GUIDED MODE — level 4. The person gets only the list: tick a task
  /// (with their acceptance) and tell about problems. The inspector builds
  /// the day from their own paired device. Heavy to turn on, one tap off.
  /// Returns true when the change was applied, false when cancelled — so
  /// the care-level selector can snap back untouched.
  Future<bool> _setGuidedMode(bool v) async {
    final s = await IsarService.getSettings();
    if (!v) {
      await IsarService.updateSettings(s.copyWith(guidedMode: false));
      setState(() => _guidedMode = false);
      if (!mounted) return true;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(L.t('Guided mode is off. Full control is back here.',
              'מצב מונחה כבוי. השליטה המלאה חזרה לכאן.'))));
      return true;
    }
    final nameCtrl = TextEditingController();
    final expected = s.effectiveShareName.trim();
    if (!mounted) return false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(L.t('Guided mode — only the list',
            'מצב מונחה — רק הרשימה')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              L.t(
                  'For when routines are what remains. This device shows the '
                  'list — big and clear. The person can tick what\'s done and '
                  'tell about problems (voice or writing). Everything else — '
                  'building the day, changing tasks — happens from YOUR device '
                  'and arrives here over Wi-Fi.\n\n'
                  'Full care turns on with it, so you see everything. '
                  'Turning it off later is one tap, right here.',
                  'למצב שבו השגרה היא מה שנשאר. המכשיר הזה מציג את הרשימה — '
                  'גדולה וברורה. אפשר לסמן מה בוצע ולספר על בעיות (בקול או '
                  'בכתיבה). כל השאר — בניית היום, שינוי משימות — נעשה '
                  'מהמכשיר שלך ומגיע לכאן דרך ה-Wi-Fi.\n\n'
                  'טיפול מלא נדלק יחד איתו, כך שאתה רואה הכול. '
                  'לכבות אחר כך — נגיעה אחת, ממש כאן.'),
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            Text(
                L.t('To turn it on, type the share name ("$expected"):',
                    'כדי להפעיל, הקלד את שם השיתוף ("$expected"):'),
                style: const TextStyle(fontSize: 13)),
            TextField(controller: nameCtrl, autofocus: true),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(L.t('Not now', 'לא עכשיו'))),
          FilledButton(
              onPressed: () => Navigator.pop(
                  c, nameCtrl.text.trim().toLowerCase() ==
                      expected.toLowerCase()),
              child: Text(L.t('Turn on guided mode', 'הפעל מצב מונחה'))),
        ],
      ),
    );
    if (confirmed != true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(L.t('Nothing changed — guided mode stays off.',
                'שום דבר לא השתנה — מצב מונחה נשאר כבוי.'))));
      }
      return false;
    }
    await IsarService.updateSettings(
        s.copyWith(guidedMode: true, fullCareMode: true));
    setState(() {
      _guidedMode = true;
      _fullCareMode = true;
    });
    if (!mounted) return true;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(L.t(
            'Guided mode is on. This device shows the list, with love.',
            'מצב מונחה פועל. המכשיר הזה מציג את הרשימה, באהבה.'))));
    return true;
  }

  /// THE CARE SPECTRUM AS ONE CHOICE — selecting a level sets the flags
  /// coherently: 1–2 → nothing heavy; 3 → full care; 4 → guided (which
  /// brings full care with it). Raising to 3 or 4 rides the existing
  /// typed-confirmation flows; cancelling there means the selector snaps
  /// back untouched. Lowering is always instant — reducing sharing must
  /// stay the easy direction.
  Future<void> _setCareLevel(int level) async {
    if (level == _careLevel) return;
    if (level >= 4) {
      // The heavy door: guided mode's own guarded flow (turns full care on).
      if (!_guidedMode) {
        final ok = await _setGuidedMode(true);
        if (!ok) return; // cancelled — level stays where it was
      }
    } else if (level == 3) {
      // Any cancellable step comes FIRST — a cancel must leave everything
      // exactly as it was, so nothing is lowered before the door is passed.
      if (!_fullCareMode) {
        final ok = await _setFullCareMode(true); // typed confirmation
        if (!ok) return; // cancelled — nothing changed, level stays put
      }
      if (_guidedMode) await _setGuidedMode(false); // lowering: one tap
    } else {
      // Levels 1–2: only chosen things ever leave this device.
      if (_guidedMode) await _setGuidedMode(false);
      if (_fullCareMode) await _setFullCareMode(false);
    }
    await _persistCareLevel(level);
  }

  /// Save the chosen level and let the whole app re-read settings.
  Future<void> _persistCareLevel(int level) async {
    final s = await IsarService.getSettings();
    if (s.careLevel != level) {
      await IsarService.updateSettings(s.copyWith(careLevel: level));
    }
    if (mounted) setState(() => _careLevel = level);
    ref.invalidate(settingsProvider);
  }

  /// The level the flags tell right now: guided → 4, full care → 3,
  /// otherwise keep the light level the person chose (2 stays 2, else 1).
  int _deriveCareLevel() {
    if (_guidedMode) return 4;
    if (_fullCareMode) return 3;
    return _careLevel == 2 ? 2 : 1;
  }

  /// The fine-grained switches below the card keep working — and after any
  /// switch change the card's level follows, so the story stays honest.
  Future<void> _onFullCareSwitch(bool v) async {
    final ok = await _setFullCareMode(v);
    if (ok) await _persistCareLevel(_deriveCareLevel());
  }

  Future<void> _onGuidedSwitch(bool v) async {
    final ok = await _setGuidedMode(v);
    if (ok) await _persistCareLevel(_deriveCareLevel());
  }

  /// One selectable row of the care-level card — a large, honest target.
  /// Radio-style visuals without motion: the mark simply is, or isn't.
  Widget _careLevelOption(int level, String text) {
    final selected = _careLevel == level;
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      onTap: () => _setCareLevel(level),
      selected: selected,
      minVerticalPadding: 10,
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_off,
        size: 28,
        color: selected ? scheme.primary : scheme.onSurfaceVariant,
      ),
      title: Text(
        L.t('Level $level', 'רמה $level'),
        style:
            TextStyle(fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
      ),
      subtitle: Text(text, style: const TextStyle(fontSize: 13)),
    );
  }

  Color _progressColor(BuildContext context) {
    // Prefer system / relaxing palette primary
    return Theme.of(context).colorScheme.primary;
  }

  @override
  void dispose() {
    // NEVER stop or dispose the service here — it is the app's lifelong
    // resident. Its old dispose() call killed discovery + transfers
    // app-wide the first time anyone LEFT this screen, which is why "the
    // pc couldn't see the device anymore" (owner QA, 2026-08-09). Only the
    // screen's own listeners go.
    _peersSub?.cancel();
    _progressSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = _progressColor(context);

    return Scaffold(
      appBar: BnsAppBar(
          title: L.t('Sync your devices', 'סנכרון המכשירים שלך'),
          hideOnDesktopWide: true),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Encouraging header
          Text(
            L.t(
                'Everything you do is kept safe for you.\nSet up once — then it just happens.',
                'כל מה שאתה עושה נשמר בשבילך.\nמגדירים פעם אחת — ומשם זה פשוט קורה.'),
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

          // Your devices — every paired device, always visible, online or
          // not. Syncing lives HERE, with the devices that matter; seeking
          // new ones is a separate corner below.
          Text(L.t('Your devices', 'המכשירים שלך'),
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_trusted.isEmpty)
            Text(L.t(
                'No devices connected yet. Use "Add a new device" below — '
                'once is enough, then syncing happens by itself.',
                'עוד אין מכשירים מחוברים. השתמש ב"הוספת מכשיר חדש" למטה — '
                'פעם אחת מספיקה, ומשם הסנכרון קורה מעצמו.')),
          ..._trusted.map(_trustedCard),

          const SizedBox(height: 8),
          SwitchListTile(
            dense: true,
            title: Text(L.t('Sync by itself', 'סנכרון מעצמו')),
            subtitle: Text(L.t(
                'Whenever the app is open and a device you trust is around — '
                'quietly, both ways, nothing to press.',
                'בכל פעם שהאפליקציה פתוחה ומכשיר שאתה סומך עליו בסביבה — '
                'בשקט, לשני הכיוונים, בלי ללחוץ על כלום.')),
            value: _autoSync,
            onChanged: _toggleAutoSync,
            activeColor: color,
          ),

          const SizedBox(height: 24),

          _addDeviceCard(),

          const SizedBox(height: 16),

          // === CARE LEVEL — the whole care spectrum in one glance ===
          // Four levels, one selected. 1–2 share nothing sensitive; 3 opens
          // everything to the people who care; 4 hands the day to the
          // caregiver. Raising to 3/4 goes through the guarded flows below;
          // lowering is always one tap.
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                    child: Text(L.t('Care level', 'רמת ליווי'),
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                  _careLevelOption(
                      1,
                      L.t(
                          'Independent — everything in your hands, nothing leaves this device unless you choose.',
                          'עצמאי — הכול בידיים שלך, שום דבר לא יוצא מהמכשיר אלא אם תבחר.')),
                  _careLevelOption(
                      2,
                      L.t(
                          'Family knows the important things — chosen plans go into the family file.',
                          'המשפחה בעניינים — תוכניות שבחרת נכנסות לקובץ המשפחה.')),
                  _careLevelOption(
                      3,
                      L.t(
                          'Full care — the people who care see everything, including the hard moments.',
                          'ליווי מלא — האנשים שאכפת להם רואים הכול, כולל הרגעים הקשים.')),
                  _careLevelOption(
                      4,
                      L.t(
                          'Guided — only the list. The day is built by the caregiver.',
                          'מונחה — רק הרשימה. את היום בונה המלווה.')),
                ],
              ),
            ),
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
                  Text(
                      L.t('History retention (keeps files small for fast sync)',
                          'שמירת היסטוריה (שומרת על קבצים קטנים לסנכרון מהיר)'),
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(_retentionDays == 0
                      ? L.t('Current: Unlimited (10000 years mode)',
                          'כרגע: ללא הגבלה (מצב 10000 שנים)')
                      : L.t('Current: $_retentionDays days (default 20)',
                          'כרגע: $_retentionDays ימים (ברירת מחדל 20)')),
                  const SizedBox(height: 8),
                  Text(
                    L.t(
                        'Old days auto-delete as time passes. New days open up. Routines stay. You can plan far into the future.',
                        'ימים ישנים נמחקים מעצמם עם הזמן. ימים חדשים נפתחים. שגרות נשארות. אפשר לתכנן רחוק אל העתיד.'),
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: () => _setRetention(20),
                        child: Text(
                            L.t('Default (20 days)', 'ברירת מחדל (20 ימים)')),
                      ),
                      OutlinedButton(
                        onPressed: () => _setRetention(90),
                        child: Text(
                            L.t('Expand to 90 days', 'הרחבה ל-90 ימים')),
                      ),
                      OutlinedButton(
                        onPressed: () => _setRetention(0),
                        child: Text(L.t('Unlimited (redundant files ok)',
                            'ללא הגבלה (קבצים גדולים זה בסדר)')),
                      ),
                      TextButton(
                        onPressed: _resetRetention,
                        child: Text(
                            L.t('Return to default', 'חזרה לברירת המחדל')),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    L.t(
                        'Warning: larger retention = bigger .bns files = slower LAN sync.',
                        'שים לב: שמירה ארוכה יותר = קובצי .bns גדולים יותר = סנכרון איטי יותר.'),
                    style: TextStyle(fontSize: 11, color: Colors.orange),
                  ),
                  const SizedBox(height: 12),
                  // User types/roles for adaptation - normal (TBI like regular joe), kid-ADHD, ADHD, custom (penguin - we secure the penguin)
                  // Affects UI (brighter for fog, simpler for kids), fluent for all. Don't check names, care about mind.
                  Text(
                      L.t(
                          'Your type (adapts UI brighter/simpler, fluent for kids):',
                          'הסוג שלך (מתאים את המסך — בהיר ופשוט יותר, זורם לילדים):'),
                      style: TextStyle(fontSize: 11)),
                  DropdownButton<String>(
                    value: _userType,
                    // Stored values stay English identifiers (they travel
                    // in the .bns); only the shown words translate.
                    items: ['normal', 'kid-ADHD', 'ADHD', 'custom (penguin)']
                        .map((t) => DropdownMenuItem(
                            value: t, child: Text(_userTypeName(t))))
                        .toList(),
                    onChanged: (v) async {
                      if (v != null) {
                        final s = await IsarService.getSettings();
                        await IsarService.updateSettings(
                            s.copyWith(userType: v));
                        await _loadRetention();
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(L.t(
                                'Set to ${_userTypeName(v)} — the screen adapts itself',
                                'הוגדר ל${_userTypeName(v)} — המסך מתאים את עצמו'))));
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  // Widget forward days - user controls to avoid stress. Default 2 (regular joe preference, no more than 2 days ahead)
                  Text(
                      L.t(
                          'Widget forward days (set low to reduce stress - you control what you see):',
                          'ימים קדימה בווידג׳ט (נמוך = פחות עומס — אתה שולט במה שאתה רואה):'),
                      style: TextStyle(fontSize: 11)),
                  Wrap(
                    spacing: 4,
                    children: [
                      for (int d in [0, 1, 2, 3, 7])
                        ChoiceChip(
                          label: Text(L.t('$d days', '$d ימים')),
                          selected: _widgetForwardDays == d,
                          onSelected: (_) => _setWidgetForwardDays(d),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Family-facing share name — what a trusted person (e.g.
                  // dad checking in) sees when this device asks to pair/sync.
                  Text(
                      L.t('Your share name (what family sees when you share):',
                          'שם השיתוף שלך (מה שהמשפחה רואה כשאתה משתף):'),
                      style: TextStyle(fontSize: 11)),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                            _shareName.isEmpty
                                ? L.t('$_deviceName (using device name)',
                                    '$_deviceName (לפי שם המכשיר)')
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
                              title: Text(L.t('Your share name',
                                  'שם השיתוף שלך')),
                              content: TextField(
                                controller: ctrl,
                                autofocus: true,
                                decoration: InputDecoration(
                                  labelText: L.t('Name people see',
                                      'השם שאנשים רואים'),
                                  hintText: L.t('e.g. Yossi', 'למשל: יוסי'),
                                ),
                              ),
                              actions: [
                                TextButton(
                                    onPressed: () => Navigator.pop(c),
                                    child: Text(L.t('Cancel', 'ביטול'))),
                                FilledButton(
                                    onPressed: () =>
                                        Navigator.pop(c, ctrl.text),
                                    child: Text(L.t('Save', 'שמירה'))),
                              ],
                            ),
                          );
                          if (newName != null) await _setShareName(newName);
                        },
                        child: Text(L.t('Edit', 'עריכה')),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Device name for friendly discovery
                  Text(
                      L.t('This device name (seen by others on Wi-Fi):',
                          'שם המכשיר הזה (מה שאחרים רואים ב-Wi-Fi):'),
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
                              title: Text(
                                  L.t('Name this device', 'תן שם למכשיר')),
                              content: TextField(
                                  controller: ctrl,
                                  decoration: InputDecoration(
                                      labelText:
                                          L.t('Device name', 'שם המכשיר'))),
                              actions: [
                                TextButton(
                                    onPressed: () => Navigator.pop(c),
                                    child: Text(L.t('Cancel', 'ביטול'))),
                                FilledButton(
                                    onPressed: () =>
                                        Navigator.pop(c, ctrl.text),
                                    child: Text(L.t('Save', 'שמירה'))),
                              ],
                            ),
                          );
                          if (newName != null) await _setDeviceName(newName);
                        },
                        child: Text(L.t('Edit', 'עריכה')),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    dense: true,
                    title: Text(L.t(
                        'Quiet mode (less animations, confetti, sounds)',
                        'מצב שקט (פחות אנימציות, קונפטי וצלילים)')),
                    value: _quietMode,
                    onChanged: _setQuietMode,
                  ),
                  const Divider(height: 24),
                  // ---- OWL TIME: the day border is chosen, not assumed
                  // (owner, 2026-08-10: "my day isn't done in 00:00...
                  // I cannot set pills at 2:00 and be normal like
                  // everyone" — now they can, and they are). ----
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.bedtime_outlined),
                    title: Text(
                        L.t('When does your day end?',
                            'מתי היום שלך נגמר?'),
                        style: Theme.of(context).textTheme.titleSmall),
                    subtitle: Text(
                        L.t(
                            'For night owls: pick 04:00 and everything '
                            'until then still belongs to tonight — pills '
                            'at 02:00 sit at the END of today\'s list, '
                            'and the day flips while you sleep.',
                            'לינשופים: בחרו 04:00 וכל מה שעד אז עדיין '
                            'שייך להלילה — כדורים ב-02:00 יושבים בסוף '
                            'הרשימה של היום, והיום מתחלף בזמן שאתם '
                            'ישנים.'),
                        style: const TextStyle(fontSize: 12)),
                  ),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (final h in const [0, 1, 2, 3, 4, 5, 6])
                        ChoiceChip(
                          label: Text(h == 0
                              ? L.t('Midnight', 'חצות')
                              : '0$h:00'),
                          selected: _dayRolloverHour == h,
                          onSelected: (_) => _setDayRolloverHour(h),
                        ),
                    ],
                  ),
                  const Divider(height: 24),
                  // ---- Reminders: when, how loud, and in what color ----
                  SwitchListTile(
                    dense: true,
                    secondary: const Icon(Icons.notifications_none),
                    title: Text(
                        L.t('Remind me at the times I chose',
                            'להזכיר לי בזמנים שבחרתי'),
                        style: Theme.of(context).textTheme.titleSmall),
                    subtitle: Text(
                        Platform.isWindows
                            ? L.t(
                                'A soft nudge when a routine or a plan has '
                                'its moment. On this computer it appears '
                                'inside BNS while it\'s open.',
                                'נגיעה רכה כשמגיע הזמן של שגרה או תוכנית. '
                                'במחשב הזה זה מופיע בתוך BNS כשהיא פתוחה.')
                            : L.t(
                                'A soft nudge when a routine or a plan has '
                                'its moment.',
                                'נגיעה רכה כשמגיע הזמן של שגרה או תוכנית.'),
                        style: const TextStyle(fontSize: 12)),
                    value: _notificationsEnabled,
                    onChanged: _setNotificationsEnabled,
                  ),
                  if (_notificationsEnabled) ...[
                    const SizedBox(height: 4),
                    Text(L.t('How a reminder arrives:', 'איך תזכורת מגיעה:'),
                        style: const TextStyle(fontSize: 11)),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        ChoiceChip(
                          label: Text(L.t('Quietly — waits in the list',
                              'בשקט — מחכה ברשימה')),
                          selected: _reminderStyle == 'quiet',
                          onSelected: (_) => _setReminderStyle('quiet'),
                        ),
                        ChoiceChip(
                          label: Text(L.t('Gently — with a soft sound',
                              'בעדינות — עם צליל רך')),
                          selected: _reminderStyle == 'gentle',
                          onSelected: (_) => _setReminderStyle('gentle'),
                        ),
                        ChoiceChip(
                          label: Text(L.t('Clearly — hard to miss',
                              'ברור — קשה לפספס')),
                          selected: _reminderStyle == 'bright',
                          onSelected: (_) => _setReminderStyle('bright'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                        L.t('Reminder color — whatever feels good to you:',
                            'צבע התזכורות — מה שנעים לך:'),
                        style: const TextStyle(fontSize: 11)),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        ChoiceChip(
                          avatar: CircleAvatar(
                              backgroundColor:
                                  Theme.of(context).colorScheme.primary),
                          label: Text(L.t('My app colors', 'צבעי האפליקציה')),
                          selected: _notificationColor == 'auto',
                          onSelected: (_) => _setNotificationColor('auto'),
                        ),
                        for (final entry in BnsTheme.reminderColors.entries)
                          ChoiceChip(
                            avatar:
                                CircleAvatar(backgroundColor: entry.value),
                            label: Text(_colorName(entry.key)),
                            selected: _notificationColor == entry.key,
                            onSelected: (_) =>
                                _setNotificationColor(entry.key),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                        L.t('A heads-up before plans on the calendar:',
                            'התראה מראש לפני תוכניות בלוח השנה:'),
                        style: const TextStyle(fontSize: 11)),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        ChoiceChip(
                          label: Text(L.t('No heads-up', 'בלי התראה')),
                          selected: _eventReminderMinutes == -1,
                          onSelected: (_) => _setEventReminderMinutes(-1),
                        ),
                        ChoiceChip(
                          label: Text(L.t('Right on time', 'בזמן עצמו')),
                          selected: _eventReminderMinutes == 0,
                          onSelected: (_) => _setEventReminderMinutes(0),
                        ),
                        ChoiceChip(
                          label: Text(
                              L.t('10 min before', '10 דקות לפני')),
                          selected: _eventReminderMinutes == 10,
                          onSelected: (_) => _setEventReminderMinutes(10),
                        ),
                        ChoiceChip(
                          label: Text(
                              L.t('30 min before', '30 דקות לפני')),
                          selected: _eventReminderMinutes == 30,
                          onSelected: (_) => _setEventReminderMinutes(30),
                        ),
                        ChoiceChip(
                          label: Text(L.t('An hour before', 'שעה לפני')),
                          selected: _eventReminderMinutes == 60,
                          onSelected: (_) => _setEventReminderMinutes(60),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Stale reminders bow out by themselves (owner QA,
                    // 2026-08-14: waking at 15:30 to the whole morning
                    // stacked in the shade "ruins the flow"). The person
                    // decides how long a nudge politely waits.
                    Text(
                        L.t('A reminder nobody touched waits, then leaves quietly:',
                            'תזכורת שלא נגעו בה מחכה, ואז יוצאת בשקט:'),
                        style: const TextStyle(fontSize: 11)),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        ChoiceChip(
                          label: Text(L.t('Half an hour', 'חצי שעה')),
                          selected: _reminderTimeoutMinutes == 30,
                          onSelected: (_) => _setReminderTimeoutMinutes(30),
                        ),
                        ChoiceChip(
                          label: Text(L.t('Two hours', 'שעתיים')),
                          selected: _reminderTimeoutMinutes == 120,
                          onSelected: (_) => _setReminderTimeoutMinutes(120),
                        ),
                        ChoiceChip(
                          label: Text(L.t('Six hours', 'שש שעות')),
                          selected: _reminderTimeoutMinutes == 360,
                          onSelected: (_) => _setReminderTimeoutMinutes(360),
                        ),
                        ChoiceChip(
                          label: Text(L.t('Stays until I see it',
                              'נשארת עד שאני רואה')),
                          selected: _reminderTimeoutMinutes == 0,
                          onSelected: (_) => _setReminderTimeoutMinutes(0),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                        L.t(
                            'And opening BNS always tidies the shade — the day '
                                'on the screen is the plan from there.',
                            'ופתיחת BNS תמיד מסדרת את מגירת ההתראות — משם, '
                                'היום שעל המסך הוא התוכנית.'),
                        style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant)),
                  ],
                  const Divider(height: 24),
                  // Hebrew first (owner, 2026-07-26): the first users are
                  // Israeli. One tap here and the whole app — words and
                  // direction — follows, instantly.
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.translate),
                    title: const Text('שפה / Language'),
                    trailing: SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'he', label: Text('עברית')),
                        ButtonSegment(value: 'en', label: Text('English')),
                      ],
                      selected: {_appLanguage},
                      onSelectionChanged: (s) => _setAppLanguage(s.first),
                    ),
                  ),
                  // WHOSE DEVICE IS THIS? Set on the HELPER'S own device,
                  // never on the person's — and never announced to them.
                  // Being helped already costs privacy; the app will not add
                  // a badge saying "you are watched".
                  SwitchListTile(
                    dense: true,
                    secondary: const Icon(Icons.volunteer_activism_outlined),
                    title: Text(L.t('This device belongs to a caregiver',
                        'המכשיר הזה שייך למלווה')),
                    subtitle: Text(
                        L.t(
                            'For the person who HELPS: their day is carried '
                            'here to build and to watch over, and reminders '
                            'on this device stay quiet — they belong to the '
                            'person being helped.',
                            'למי שמלווה: היום של האדם נמצא כאן כדי לבנות '
                            'ולהשגיח, והתזכורות במכשיר הזה שותקות — הן '
                            'שייכות למי שמלווים.'),
                        style: const TextStyle(fontSize: 12)),
                    value: _caregiverDevice,
                    onChanged: _setCaregiverDevice,
                  ),
                  SwitchListTile(
                    dense: true,
                    title: Text(L.t('Speech-to-text everywhere',
                        'דיבור-לטקסט בכל מקום')),
                    subtitle: Text(L.t(
                        'Voice notes become readable text as you speak, and every '
                        'text field gets a small dictation mic. Device engine only '
                        '— free, private, no cloud.',
                        'הקלטות קול הופכות לטקסט קריא תוך כדי דיבור, ולכל שדה '
                        'טקסט מתווסף מיקרופון הכתבה קטן. מנוע במכשיר בלבד — '
                        'חינם, פרטי, בלי ענן.')),
                    value: _sttEnabled,
                    onChanged: _setSttEnabled,
                  ),
                  // Windows itself is deaf to Hebrew (checked, 2026-07-27:
                  // WinRT + legacy engines list en-GB/en-US only; Voice
                  // typing knows Hebrew but no app may call it). whisper.cpp
                  // is the offline ear that does — MIT, free, no cloud.
                  if (Platform.isWindows)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.hearing),
                      title: Text(L.t(
                          'Offline ears for this PC — Hebrew & English '
                          '(whisper.cpp, open source)',
                          'אוזניים לא-מקוונות למחשב הזה — עברית ואנגלית '
                          '(whisper.cpp, קוד פתוח)')),
                      subtitle: Text(_voskStatus.isEmpty
                          ? L.t(
                              'Turns recordings into readable words — offline, '
                              'free, no cloud. About 473 MB, one time.',
                              'הופך הקלטות למילים קריאות — לא מקוון, חינם, בלי '
                              'ענן. בערך 473 MB, פעם אחת.')
                          : _voskStatus),
                      trailing: _voskBusy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : TextButton(
                              onPressed: _installVosk,
                              child: Text(_voskStatus.startsWith('Installed') ||
                                      _voskStatus.startsWith('מותקן')
                                  ? L.t('Reinstall', 'התקנה מחדש')
                                  : L.t('Install', 'התקנה')),
                            ),
                    ),
                  SwitchListTile(
                    dense: true,
                    title: Text(L.t('Keep a ready-to-share .bns fresh',
                        'לשמור קובץ .bns טרי ומוכן לשיתוף')),
                    subtitle: Text(L.t(
                        'Silently refreshes BNS_Latest on close/background — a current backup always exists without exporting.',
                        'מרענן בשקט את BNS_Latest בסגירה או ברקע — תמיד יש גיבוי עדכני בלי לייצא.')),
                    value: _autoImage,
                    onChanged: _setAutoImage,
                  ),
                  // Where the data ACTUALLY lives — chosen, not hardcoded
                  // (owner, 2026-08-09: "we have to make it not hardcoded
                  // to save the bns file"). Desktop only: phones keep
                  // their app storage.
                  if (!Platform.isAndroid && !Platform.isIOS)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.home_outlined),
                      title: Text(L.t('Where your BNS lives',
                          'איפה ה-BNS שלך גר')),
                      subtitle: Text(
                        _homePath.isEmpty ? '…' : _homePath,
                        textDirection: TextDirection.ltr,
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: TextButton.icon(
                        onPressed: _chooseHome,
                        icon: const Icon(Icons.drive_file_move_outline,
                            size: 18),
                        label: Text(
                            L.t('Choose folder', 'בחירת תיקייה')),
                      ),
                    ),

                  const SizedBox(height: 16),
                  const Divider(),
                  // === PC Keybinds (robust PC primary experience) ===
                  // Set & forget. Tick the ones you want active.
                  // We give you a simple basic layout. Typing is #1 on PC.
                  // Changes saved into your .bns — travels everywhere.
                  Text(
                      L.t('PC Keybinds — set & forget (primary on PC)',
                          'קיצורי מקשים למחשב — מגדירים ושוכחים'),
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    L.t(
                        'Tick to activate. Click a combo and press new keys to change it. '
                        'Applies immediately and travels in your .bns. Not forced — use what feels good.',
                        'סמן כדי להפעיל. לחץ על צירוף והקש מקשים חדשים כדי לשנות. '
                        'חל מיד ונוסע עם קובץ ה-.bns שלך. שום דבר לא כפוי — השתמש במה שנעים לך.'),
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

          const SizedBox(height: 32),

          // Manual - still easy
          Text(
              L.t('Manual backup (for USB or when Wi-Fi is not available)',
                  'גיבוי ידני (ל-USB או כשאין Wi-Fi)'),
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
                child: OutlinedButton.icon(
                    onPressed: _manualExport,
                    icon: const Icon(Icons.save),
                    label: Text(L.t('Export .bns', 'ייצוא .bns')))),
            const SizedBox(width: 12),
            Expanded(
                child: OutlinedButton.icon(
                    onPressed: _manualImport,
                    icon: const Icon(Icons.folder_open),
                    label: Text(L.t('Import .bns', 'ייבוא .bns')))),
          ]),

          const SizedBox(height: 16),
          Text(L.t('Family share', 'שיתוף משפחה'),
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            _fullCareMode
                ? L.t(
                    'Full care is ON: the family file carries everything — every '
                    'plan, every moment, every voice note — for the people '
                    'easing the path.',
                    'טיפול מלא פועל: קובץ המשפחה נושא הכול — כל תוכנית, כל '
                    'רגע, כל הקלטת קול — לאנשים שמקילים את הדרך.')
                : L.t(
                    'A small file with ONLY what was chosen: plans marked '
                    '"family can know" and moments tagged "family" (voice '
                    'notes included). Nothing else is inside it, no matter '
                    'how it\'s opened.',
                    'קובץ קטן עם מה שנבחר בלבד: תוכניות שסומנו "המשפחה יכולה '
                    'לדעת" ורגעים שתויגו "משפחה" (כולל הקלטות קול). שום דבר '
                    'אחר לא נמצא בו, לא משנה איך פותחים אותו.'),
            style: TextStyle(
                fontSize: 12.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
              onPressed: _exportFamilyShare,
              icon: const Icon(Icons.family_restroom),
              label: Text(L.t('Make the family file', 'צור את קובץ המשפחה'))),
          const SizedBox(height: 8),
          SwitchListTile(
            dense: true,
            title: Text(L.t('Full care (level 3 — last resort)',
                'טיפול מלא (רמה 3 — מוצא אחרון)')),
            subtitle: Text(
                L.t(
                    'For the hardest situations: everything matters, everything '
                    'is shared with the people who care. Guarded to turn on, one '
                    'tap to turn off.',
                    'למצבים הקשים ביותר: הכול חשוב, הכול משותף עם האנשים '
                    'שאכפת להם. מוגן בהפעלה, נגיעה אחת לכיבוי.'),
                style: const TextStyle(fontSize: 12)),
            value: _fullCareMode,
            onChanged: _onFullCareSwitch,
          ),
          SwitchListTile(
            dense: true,
            title: Text(L.t('Guided mode (level 4 — only the list)',
                'מצב מונחה (רמה 4 — רק הרשימה)')),
            subtitle: Text(
                L.t(
                    'When routines are what remains: this device shows the list, '
                    'big and clear. Ticking and telling about problems stay; '
                    'building the day moves to the inspector\'s device. '
                    'The caregiver\'s door: at the bottom of Today, HOLD the '
                    '"Caregiver" button to set up the day right on this device.',
                    'כשהשגרה היא מה שנשאר: המכשיר הזה מציג את הרשימה, גדולה '
                    'וברורה. סימון וסיפור על בעיות נשארים; בניית היום עוברת '
                    'למכשיר של המלווה. הדלת של המטפל: בתחתית "היום", לחיצה '
                    'ארוכה על כפתור "מטפל" מאפשרת לסדר את היום ישר על המכשיר הזה.'),
                style: const TextStyle(fontSize: 12)),
            value: _guidedMode,
            onChanged: _onGuidedSwitch,
          ),

          const SizedBox(height: 40),
          Text(
            L.t(
                'Everything stays private. Only devices you explicitly accept can exchange data.',
                'הכול נשאר פרטי. רק מכשירים שאישרת במפורש יכולים להחליף מידע.'),
            style: const TextStyle(fontSize: 12),
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
      title: Text(L.t('New keys for "${widget.actionLabel}"',
          'מקשים חדשים עבור "${widget.actionLabel}"')),
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
              Text(L.t('Press the combination you want. Take your time.',
                  'הקש את הצירוף שתרצה. קח את הזמן, אין לחץ.')),
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
                      ? L.t('Waiting for keys…', 'מחכה למקשים…')
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
          child: Text(L.t('Cancel — keep the old keys',
              'ביטול — נשאיר את המקשים הישנים')),
        ),
        FilledButton(
          onPressed:
              _combo == null ? null : () => Navigator.pop(context, _combo),
          child: Text(L.t('Use these keys', 'השתמש במקשים האלה')),
        ),
      ],
    );
  }
}

// The pairing dialogs (initiator's ShowCodeDialog, receiver's
// EnterCodeDialog) live in pairing_dialogs.dart — main.dart needs the
// receiver side app-wide, so a pairing request reaches the person on any
// screen, not only while this one is open.
