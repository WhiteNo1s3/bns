import 'dart:convert';
import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'package:bns/core/models/models.dart';
import 'package:bns/core/keybinds.dart';

/// Central persistence for routines, events, captures, logs, settings.
///
/// Historical name (the first design used Isar). Now a simple, dependency-free
/// JSON snapshot store: the whole state lives in memory and is written
/// atomically to `bns_data.json` in the app documents folder on every change.
/// At BNS scale (2-week rolling window, personal data) this is instant, works
/// identically on every platform, and needs zero code generation.
class IsarService {
  static const _uuid = Uuid();
  static const _fileName = 'bns_data.json';

  static _Data? _data;
  static Future<void> _writeChain = Future.value();

  /// Bumped on every persisted change. Lets the lifecycle guard skip
  /// re-imaging a .bns when nothing actually changed.
  static int _revision = 0;
  static int get revision => _revision;

  /// Await all pending disk writes (used on app pause/exit — belt and
  /// suspenders on top of the per-change atomic writes).
  static Future<void> flush() => _writeChain;

  /// True if the previous session ended without a graceful goodbye (crash,
  /// force-kill, battery death). Because every change is persisted instantly,
  /// nothing is actually lost — this exists so the app can say a REASSURING
  /// word, never an alarming one. (Idea: 2026-07-05 reference wave.)
  static bool lastExitWasClean = true;

  /// Called by the lifecycle guard when the app closes gracefully.
  static Future<void> markCleanExit() async {
    final d = await _load();
    if (!d.cleanExit) {
      d.cleanExit = true;
      await _persist();
    }
  }

  /// Called on resume: the session is live again, so a crash from here on
  /// must count as unclean (undoes the goodbye written on pause).
  static Future<void> markSessionOpen() async {
    final d = await _load();
    if (d.cleanExit) {
      d.cleanExit = false;
      await _persist();
    }
  }

  // ---- Load / persist ----

  static Future<_Data> _load() async {
    if (_data != null) return _data!;

    final file = await _storeFile();
    _Data loaded;
    if (await file.exists()) {
      try {
        final json =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        loaded = _Data.fromJson(json);
      } catch (_) {
        // Corrupt file — keep a copy for recovery, start fresh. Never crash.
        try {
          await file.copy('${file.path}.corrupt');
        } catch (_) {}
        loaded = _Data.empty();
      }
    } else {
      loaded = _Data.empty();
    }

    // Session bookkeeping: remember how the LAST session ended, then mark
    // this one "open" until markCleanExit() says goodbye properly.
    lastExitWasClean = loaded.cleanExit;
    loaded.cleanExit = false;

    _data = loaded;
    await _ensureDefaults();
    await _persist(); // persist the "session open" mark
    return _data!;
  }

  static Future<File> _storeFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// Atomic persist: write to a temp file, then rename over the real one.
  /// Writes are chained so they never interleave.
  static Future<void> _persist() {
    _revision++;
    final snapshotJson = jsonEncode(_data!.toJson());
    _writeChain = _writeChain.then((_) async {
      final file = await _storeFile();
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(snapshotJson, flush: true);
      if (await file.exists()) await file.delete();
      await tmp.rename(file.path);
    });
    return _writeChain;
  }

  static Future<void> _ensureDefaults() async {
    final d = _data!;
    var s = d.settings;
    var changed = false;

    if (s.deviceId.isEmpty) {
      s = s.copyWith(deviceId: _uuid.v4());
      changed = true;
    }
    if (s.keybinds.isEmpty) {
      s = s.copyWith(
        keybinds: Map<String, String>.from(Keybinds.defaults),
        enabledKeybinds: Map<String, bool>.from(Keybinds.defaultEnabled),
      );
      changed = true;
    }
    if (changed) d.settings = s;

    // Gentle seed data on first run so the app feels useful immediately
    if (d.routines.isEmpty && !d.seeded) {
      final now = DateTime.now();
      d.routines.addAll([
        Routine(
          id: 'seed-1',
          title: 'Morning stretch + water',
          recurrenceType: RecurrenceType.daily,
          time: '08:00',
          createdAt: now,
          updatedAt: now,
        ),
        Routine(
          id: 'seed-2',
          title: 'Take supplements (with food if possible)',
          recurrenceType: RecurrenceType.weekdays,
          daysOfWeek: const [1, 2, 3, 4, 5],
          time: '08:15',
          createdAt: now,
          updatedAt: now,
        ),
        Routine(
          id: 'seed-3',
          title: 'Gentle walk or sit outside',
          recurrenceType: RecurrenceType.daily,
          createdAt: now,
          updatedAt: now,
        ),
      ]);
      d.seeded = true;
      changed = true;
    }

    if (changed) await _persist();
  }

  // ---- Routines ----

  static Future<List<Routine>> getAllRoutines() async {
    final d = await _load();
    final list = List<Routine>.from(d.routines);
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  static Future<Routine> addRoutine(Routine routine) async {
    final d = await _load();
    final withId = routine.id.isEmpty
        ? routine.copyWith(
            id: _uuid.v4(),
            createdAt: DateTime.now(),
            updatedAt: DateTime.now())
        : routine;
    d.routines.removeWhere((r) => r.id == withId.id);
    d.routines.add(withId);
    await _persist();
    return withId;
  }

  static Future<void> updateRoutine(Routine routine) async {
    final d = await _load();
    final updated = routine.copyWith(updatedAt: DateTime.now());
    d.routines.removeWhere((r) => r.id == updated.id);
    d.routines.add(updated);
    await _persist();
  }

  static Future<void> deleteRoutine(String id) async {
    final d = await _load();
    d.routines.removeWhere((r) => r.id == id);
    await _persist();
  }

  // ---- Calendar Events ----

  static Future<List<CalendarEvent>> getEventsForDate(String date) async {
    final d = await _load();
    // Includes multi-day special orders that span this day.
    return d.events.where((e) => e.activeOn(date)).toList();
  }

  /// Special orders active on [date] (out-of-the-ordinary day items).
  static Future<List<CalendarEvent>> getSpecialOrdersForDate(
      String date) async {
    final all = await getEventsForDate(date);
    return all.where((e) => e.isSpecialOrder).toList();
  }

  static Future<List<CalendarEvent>> getAllEvents() async {
    final d = await _load();
    final list = List<CalendarEvent>.from(d.events);
    list.sort((a, b) => a.date.compareTo(b.date));
    return list;
  }

  static Future<CalendarEvent> addEvent(CalendarEvent event) async {
    final d = await _load();
    final withId = event.id.isEmpty
        ? event.copyWith(
            id: _uuid.v4(),
            createdAt: DateTime.now(),
            updatedAt: DateTime.now())
        : event;
    d.events.removeWhere((e) => e.id == withId.id);
    d.events.add(withId);
    await _persist();
    return withId;
  }

  static Future<void> updateEvent(CalendarEvent event) async {
    final d = await _load();
    final updated = event.copyWith(updatedAt: DateTime.now());
    d.events.removeWhere((e) => e.id == updated.id);
    d.events.add(updated);
    await _persist();
  }

  static Future<void> deleteEvent(String id) async {
    final d = await _load();
    d.events.removeWhere((e) => e.id == id);
    await _persist();
  }

  // ---- Quick Captures ----

  static Future<List<QuickCapture>> getCapturesForDate(DateTime date) async {
    final d = await _load();
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    final list = d.captures
        .where((c) =>
            c.deletedAt == null && !c.at.isBefore(start) && c.at.isBefore(end))
        .toList();
    list.sort((a, b) => b.at.compareTo(a.at));
    return list;
  }

  static Future<List<QuickCapture>> getAllCaptures() async {
    final d = await _load();
    final list = d.captures.where((c) => c.deletedAt == null).toList();
    list.sort((a, b) => b.at.compareTo(a.at));
    return list;
  }

  static Future<QuickCapture> addCapture(QuickCapture capture) async {
    final d = await _load();
    final withId =
        capture.id.isEmpty ? capture.copyWith(id: _uuid.v4()) : capture;
    d.captures.removeWhere((c) => c.id == withId.id);
    d.captures.add(withId);
    await _persist();
    return withId;
  }

  // ---- Completion Logs ----

  static Future<List<CompletionLog>> getLogsForDate(String date) async {
    final d = await _load();
    return d.logs.where((l) => l.date == date).toList();
  }

  static Future<List<CompletionLog>> getAllCompletionLogs() async {
    final d = await _load();
    return List<CompletionLog>.from(d.logs);
  }

  static Future<void> logCompletion({
    required String routineId,
    required String date,
    required CompletionStatus status,
    String? reason,
    String? reasonAudioPath,
  }) async {
    final d = await _load();
    // One truth per routine per day — replace, never pile up.
    d.logs.removeWhere((l) => l.routineId == routineId && l.date == date);
    d.logs.add(CompletionLog(
      id: _uuid.v4(),
      routineId: routineId,
      date: date,
      status: status,
      reason: reason,
      reasonAudioPath: reasonAudioPath,
      at: DateTime.now(),
    ));
    await _persist();
  }

  /// Unchecking the checkbox: the day simply has no answer for this routine
  /// anymore — not done, not skipped, just open again. (Owner, 2026-07-08:
  /// there was no way to take a ✓ back.) Step progress resets with it.
  static Future<void> removeCompletion({
    required String routineId,
    required String date,
  }) async {
    final d = await _load();
    d.logs.removeWhere((l) => l.routineId == routineId && l.date == date);
    d.stepProgress.remove('$date|$routineId');
    await _persist();
  }

  // ---- Step progress (the parts inside a routine, per day) ----

  static Future<int> getStepProgress(String routineId, String date) async {
    final d = await _load();
    return d.stepProgress['$date|$routineId'] ?? 0;
  }

  /// One more part handled. Returns the new count.
  static Future<int> advanceStep(
      String routineId, String date, int totalSteps) async {
    final d = await _load();
    final key = '$date|$routineId';
    final next = ((d.stepProgress[key] ?? 0) + 1).clamp(0, totalSteps);
    d.stepProgress[key] = next;
    await _persist();
    return next;
  }

  static Future<Map<String, int>> stepProgressForDate(String date) async {
    final d = await _load();
    final out = <String, int>{};
    d.stepProgress.forEach((k, v) {
      if (k.startsWith('$date|')) out[k.substring(date.length + 1)] = v;
    });
    return out;
  }

  // ---- Full snapshot helpers for .bns imaging ----

  static Future<
      ({
        List<Routine> routines,
        List<CalendarEvent> events,
        List<QuickCapture> captures,
        List<CompletionLog> logs,
        AppSettings settings
      })> getFullSnapshot() async {
    final d = await _load();
    return (
      routines: List<Routine>.from(d.routines),
      events: List<CalendarEvent>.from(d.events),
      // Export active data only (no trash)
      captures: d.captures.where((c) => c.deletedAt == null).toList(),
      logs: List<CompletionLog>.from(d.logs),
      settings: d.settings,
    );
  }

  /// Wipes current data and restores from imported snapshot.
  /// This device keeps its own identity (deviceId + deviceName) and its
  /// local retention preference — imports never rename or re-identify a device.
  static Future<void> replaceAllData({
    required List<Routine> routines,
    required List<CalendarEvent> events,
    required List<QuickCapture> captures,
    required List<CompletionLog> logs,
    required AppSettings settings,
  }) async {
    final d = await _load();
    final local = d.settings;

    d.routines
      ..clear()
      ..addAll(routines);
    d.events
      ..clear()
      ..addAll(events);
    d.captures
      ..clear()
      ..addAll(captures);
    d.logs
      ..clear()
      ..addAll(logs);

    d.settings = settings.copyWith(
      serverUrl: local.serverUrl,
      serverToken: local.serverToken,
      deviceId: local.deviceId,
      deviceName: local.deviceName,
      retentionDays: local.retentionDays,
    );
    await _persist();
  }

  /// Merge strategy (last write wins by timestamp where possible).
  static Future<void> mergeData({
    required List<Routine> routines,
    required List<CalendarEvent> events,
    required List<QuickCapture> captures,
    required List<CompletionLog> logs,
    required AppSettings incomingSettings,
  }) async {
    final d = await _load();

    for (final r in routines) {
      final i = d.routines.indexWhere((x) => x.id == r.id);
      if (i == -1) {
        d.routines.add(r);
      } else if (r.updatedAt.isAfter(d.routines[i].updatedAt)) {
        d.routines[i] = r;
      }
    }
    for (final e in events) {
      final i = d.events.indexWhere((x) => x.id == e.id);
      if (i == -1) {
        d.events.add(e);
      } else if (e.updatedAt.isAfter(d.events[i].updatedAt)) {
        d.events[i] = e;
      }
    }
    for (final c in captures) {
      if (!d.captures.any((x) => x.id == c.id)) d.captures.add(c);
    }
    for (final l in logs) {
      if (!d.logs.any((x) => x.id == l.id)) d.logs.add(l);
    }

    // Keep this device's identity, local preferences, and local secrets
    // (server credentials never travel — see BnsExporter — so incoming
    // settings must never blank them out).
    final local = d.settings;
    d.settings = incomingSettings.copyWith(
      deviceId: local.deviceId,
      deviceName: local.deviceName,
      retentionDays: local.retentionDays,
      serverUrl: local.serverUrl,
      serverToken: local.serverToken,
    );
    await _persist();
  }

  // ---- Trusted Devices (for secure auto-sync) ----

  static Future<List<TrustedDevice>> getTrustedDevices() async {
    final d = await _load();
    return List<TrustedDevice>.from(d.trusted);
  }

  static Future<TrustedDevice?> getTrustedDevice(String deviceId) async {
    final d = await _load();
    for (final t in d.trusted) {
      if (t.id == deviceId) return t;
    }
    return null;
  }

  static Future<void> saveTrustedDevice(TrustedDevice device) async {
    final d = await _load();
    d.trusted.removeWhere((t) => t.id == device.id);
    d.trusted.add(device);
    await _persist();
  }

  static Future<void> removeTrustedDevice(String id) async {
    final d = await _load();
    d.trusted.removeWhere((t) => t.id == id);
    await _persist();
  }

  static Future<void> updateTrustedDeviceLastSync(
      String id, String address) async {
    final d = await _load();
    final i = d.trusted.indexWhere((t) => t.id == id);
    if (i != -1) {
      d.trusted[i] = d.trusted[i].copyWith(
        lastAddress: address,
        lastSyncedAt: DateTime.now(),
      );
      await _persist();
    }
  }

  // ---- Rolling data retention to keep files small and sync fast ----
  // Default 20 days of history. Future calendar events preserved.
  // Routines and core settings are never pruned.
  static Future<void> pruneOldData() async {
    final d = await _load();
    var changed = false;

    // Mad-mode vents burn out fast (~2 days) no matter what retention is set:
    // anger gets space, not a permanent record. Vents deliberately promoted
    // to "memorize" are respected and kept.
    final ventCutoff = DateTime.now().subtract(const Duration(hours: 48));
    final before = d.captures.length;
    d.captures.removeWhere((c) =>
        c.tags.contains('mad-vent') &&
        c.memoryLevel != MemoryLevel.memorize &&
        c.at.isBefore(ventCutoff));
    if (d.captures.length != before) changed = true;

    final retention = d.settings.retentionDays;
    if (retention > 0) {
      final cutoff = DateTime.now().subtract(Duration(days: retention));
      final cutoffDateStr = DateFormat('yyyy-MM-dd').format(cutoff);
      final trashCutoff = DateTime.now().subtract(const Duration(days: 3));

      final logsBefore = d.logs.length;
      d.logs.removeWhere((l) => l.date.compareTo(cutoffDateStr) < 0);
      if (d.logs.length != logsBefore) changed = true;

      // Step working-state from days gone by is meaningless — clear it.
      final stepsBefore = d.stepProgress.length;
      d.stepProgress
          .removeWhere((k, _) => k.split('|').first.compareTo(cutoffDateStr) < 0);
      if (d.stepProgress.length != stepsBefore) changed = true;

      final capsBefore = d.captures.length;
      // Old captures beyond window ('memorize' level is permanent).
      d.captures.removeWhere((c) =>
          c.at.isBefore(cutoff) &&
          c.memoryLevel != MemoryLevel.memorize &&
          (c.deletedAt == null || c.deletedAt!.isBefore(trashCutoff)));
      // Trashed captures older than 3 days (permanent delete).
      d.captures.removeWhere(
          (c) => c.deletedAt != null && c.deletedAt!.isBefore(trashCutoff));
      if (d.captures.length != capsBefore) changed = true;

      final evBefore = d.events.length;
      d.events.removeWhere((ev) {
        final evDate = DateTime.tryParse(ev.date);
        return evDate != null && evDate.isBefore(cutoff);
      });
      if (d.events.length != evBefore) changed = true;
    }

    if (changed) await _persist();
  }

  static Future<void> updateRetentionDays(int days) async {
    final d = await _load();
    d.settings = d.settings.copyWith(retentionDays: days);
    await _persist();
    await pruneOldData();
  }

  static Future<void> resetRetentionToDefault() async {
    // Owner FINAL (2026-07-08): "20 days past, 10 days into the future" —
    // the +10 forward is the calendar's bound (calendar_screen.dart).
    await updateRetentionDays(20);
  }

  // ---- Trash / Soft delete (user control) ----
  // Deleted items stay in trash 3 days, then auto permanent delete (in prune).
  // .bns exports exclude trash.

  static Future<void> softDeleteCapture(String id) async {
    final d = await _load();
    final i = d.captures.indexWhere((c) => c.id == id);
    if (i != -1) {
      d.captures[i] = d.captures[i].copyWith(deletedAt: DateTime.now());
      await _persist();
    }
  }

  static Future<void> restoreCapture(String id) async {
    final d = await _load();
    final i = d.captures.indexWhere((c) => c.id == id);
    if (i != -1) {
      d.captures[i] = d.captures[i].copyWith(deletedAt: null);
      await _persist();
    }
  }

  static Future<List<QuickCapture>> getTrashedCaptures() async {
    final d = await _load();
    final list = d.captures.where((c) => c.deletedAt != null).toList();
    list.sort((a, b) => b.deletedAt!.compareTo(a.deletedAt!));
    return list;
  }

  // ---- Settings ----

  static Future<AppSettings> getSettings() async {
    final d = await _load();
    return d.settings;
  }

  static Future<void> updateSettings(AppSettings settings) async {
    final d = await _load();
    d.settings = settings;
    await _persist();
  }

  /// Update or add a keybind (PC robust feature). Set-and-forget.
  static Future<void> setKeybind(String id, String combo,
      {bool? enabled}) async {
    final current = await getSettings();
    final newBinds = Map<String, String>.from(current.keybinds);
    final newEnabled = Map<String, bool>.from(current.enabledKeybinds);

    newBinds[id] = combo;
    if (enabled != null) {
      newEnabled[id] = enabled;
    } else if (!newEnabled.containsKey(id)) {
      newEnabled[id] = true;
    }

    await updateSettings(current.copyWith(
      keybinds: newBinds,
      enabledKeybinds: newEnabled,
    ));
  }

  static Future<void> toggleKeybindEnabled(String id, bool enabled) async {
    final current = await getSettings();
    final newEnabled = Map<String, bool>.from(current.enabledKeybinds);
    newEnabled[id] = enabled;
    await updateSettings(current.copyWith(enabledKeybinds: newEnabled));
  }

  static Future<void> resetKeybindsToDefault() async {
    final current = await getSettings();
    await updateSettings(current.copyWith(
      keybinds: Map<String, String>.from(Keybinds.defaults),
      enabledKeybinds: Map<String, bool>.from(Keybinds.defaultEnabled),
    ));
  }

  // ---- "I am mad" mode (rage pressure valve, burns out on its own) ----

  static Future<bool> isMadModeActive() async {
    final s = await getSettings();
    final until = s.madModeUntil;
    if (until == null) return false;
    if (until.isBefore(DateTime.now())) {
      // Burned out — quietly return to calm.
      await updateSettings(s.copyWith(madModeUntil: null));
      return false;
    }
    return true;
  }

  static Future<void> setMadMode(bool on) async {
    final s = await getSettings();
    await updateSettings(s.copyWith(
      madModeUntil: on ? DateTime.now().add(const Duration(hours: 24)) : null,
    ));
  }

  // ---- Audio directory helper ----

  static Future<Directory> getAudioDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/audio');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }
}

/// In-memory state, serialized as one JSON document.
class _Data {
  final List<Routine> routines;
  final List<CalendarEvent> events;
  final List<QuickCapture> captures;
  final List<CompletionLog> logs;
  final List<TrustedDevice> trusted;
  AppSettings settings;
  bool seeded;

  /// True only when the previous session said goodbye via markCleanExit().
  bool cleanExit;

  /// Per-day step progress: 'yyyy-MM-dd|routineId' → parts done so far.
  /// Device-local working state (the finished day travels via logs).
  final Map<String, int> stepProgress;

  _Data({
    required this.routines,
    required this.events,
    required this.captures,
    required this.logs,
    required this.trusted,
    required this.settings,
    required this.seeded,
    this.cleanExit = true,
    Map<String, int>? stepProgress,
  }) : stepProgress = stepProgress ?? {};

  factory _Data.empty() => _Data(
        routines: [],
        events: [],
        captures: [],
        logs: [],
        trusted: [],
        settings: const AppSettings(),
        seeded: false,
      );

  Map<String, dynamic> toJson() => {
        'version': 1,
        'seeded': seeded,
        'cleanExit': cleanExit,
        'settings': settings.toJson(),
        'routines': routines.map((e) => e.toJson()).toList(),
        'events': events.map((e) => e.toJson()).toList(),
        'captures': captures.map((e) => e.toJson()).toList(),
        'logs': logs.map((e) => e.toJson()).toList(),
        'trusted': trusted.map((e) => e.toJson()).toList(),
        'stepProgress': stepProgress,
      };

  factory _Data.fromJson(Map<String, dynamic> json) => _Data(
        seeded: json['seeded'] as bool? ?? true,
        cleanExit: json['cleanExit'] as bool? ?? true,
        settings: json['settings'] == null
            ? const AppSettings()
            : AppSettings.fromJson(json['settings'] as Map<String, dynamic>),
        routines: (json['routines'] as List? ?? const [])
            .map((j) => Routine.fromJson(j as Map<String, dynamic>))
            .toList(),
        events: (json['events'] as List? ?? const [])
            .map((j) => CalendarEvent.fromJson(j as Map<String, dynamic>))
            .toList(),
        captures: (json['captures'] as List? ?? const [])
            .map((j) => QuickCapture.fromJson(j as Map<String, dynamic>))
            .toList(),
        logs: (json['logs'] as List? ?? const [])
            .map((j) => CompletionLog.fromJson(j as Map<String, dynamic>))
            .toList(),
        trusted: (json['trusted'] as List? ?? const [])
            .map((j) => TrustedDevice.fromJson(j as Map<String, dynamic>))
            .toList(),
        stepProgress: (json['stepProgress'] as Map? ?? const {})
            .map((k, v) => MapEntry(k.toString(), (v as num).toInt())),
      );
}
