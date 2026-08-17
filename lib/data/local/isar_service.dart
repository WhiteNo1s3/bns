import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show ValueNotifier, visibleForTesting;
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import 'package:bns/core/i18n/l.dart';
import 'package:bns/core/kept_memory.dart';
import 'package:bns/data/local/bns_home.dart';
import 'package:bns/core/day_ideas.dart';
import 'package:bns/core/models/models.dart';
import 'package:bns/core/keybinds.dart';
import 'package:bns/core/owl_time.dart';

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

  // ---- Resilient write pipeline (the "void" fix, owner QA 2026-08-14) ----
  // One failed disk write used to reject the old future-chain: every later
  // save silently died until restart while the screen kept saying "saved" —
  // text and voices fell into the void. Now the newest snapshot waits in
  // [_pendingSnapshot] (bursts coalesce into one write) and a single drain
  // loop writes it, absorbs failures, retries on a timer, and tells the UI
  // honestly through [saveTrouble]. Memory is always the live truth.
  static String? _pendingSnapshot;
  static bool _draining = false;
  static Completer<void>? _drainDone;
  static Timer? _saveRetryTimer;
  static const Duration _saveRetryDelay = Duration(seconds: 20);

  /// Non-null while disk writes are failing: one short, kind, human sentence
  /// for a quiet banner. Cleared by the first write that lands.
  static final ValueNotifier<String?> saveTrouble = ValueNotifier<String?>(null);

  /// Bumped on every persisted change. Lets the lifecycle guard skip
  /// re-imaging a .bns when nothing actually changed.
  static int _revision = 0;
  static int get revision => _revision;

  /// Fired after every persisted change (fire-and-forget). Wired in main to
  /// the notifications service, so editing a routine, adding a plan, a LAN
  /// sync or a .bns import all refresh reminders by themselves — no screen
  /// has to remember to ask.
  static void Function()? onDataChanged;

  /// Bumps on every persisted change. Screens listen and repaint, so data
  /// arriving from a sync or import shows up INSTANTLY — never "after a
  /// restart".
  static final ValueNotifier<int> dataRevision = ValueNotifier<int>(0);

  /// Await the pending disk write (used on app pause/exit — belt and
  /// suspenders on top of the per-change writes). Completes when the current
  /// attempt finishes — even a failed one — so a goodbye can never hang;
  /// on failure the snapshot stays pending and the retry timer keeps at it.
  static Future<void> flush() {
    if (!_draining && _pendingSnapshot == null) return Future.value();
    _drainDone ??= Completer<void>();
    final done = _drainDone!.future;
    _kickDrain();
    return done;
  }

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
      await flush(); // the goodbye must actually reach the disk
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
    var loaded = await _readStore(file);
    if (loaded == null) {
      // The main file is missing or unreadable. Before starting fresh, look
      // for the write that almost made it (.tmp) and the last known good
      // copy (.bak) — a person's memories deserve every rescue attempt.
      for (final rescue in [
        File('${file.path}.tmp'),
        File('${file.path}.bak'),
      ]) {
        loaded = await _readStore(rescue);
        if (loaded != null) break;
      }
    }
    loaded ??= _Data.empty();

    // Session bookkeeping: remember how the LAST session ended, then mark
    // this one "open" until markCleanExit() says goodbye properly.
    lastExitWasClean = loaded.cleanExit;
    loaded.cleanExit = false;

    _data = loaded;
    await _ensureDefaults();
    await _persist(); // persist the "session open" mark
    return _data!;
  }

  /// Parse one store file; null when missing or unreadable. A corrupt file
  /// is kept aside as `.corrupt` for recovery — never silently discarded.
  static Future<_Data?> _readStore(File file) async {
    try {
      if (!await file.exists()) return null;
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return _Data.fromJson(json);
    } catch (_) {
      try {
        await file.copy('${file.path}.corrupt');
      } catch (_) {}
      return null;
    }
  }

  static Future<File> _storeFile() async {
    // Not hardcoded to documents anymore: the person chooses where BNS
    // lives (owner, 2026-08-09); BnsHome holds the answer.
    final dir = await BnsHome.dir();
    return File('${dir.path}/$_fileName');
  }

  /// Persist the in-memory state: instant for the caller, safe on disk right
  /// behind. The UI never waits on storage (owner QA, 2026-08-14: posting a
  /// note felt sluggish, and a stuck disk froze every save after it) — the
  /// returned future completes immediately; [flush] is for the goodbye path.
  static Future<void> _persist() {
    _revision++;
    // Screens listen to this so data arriving BEHIND the UI — a LAN sync,
    // a .bns import — repaints the day instantly. Restarting the app to
    // see an update is fine for a power user and impossible at level 4
    // (owner, 2026-08-10: "the things I forgot people will never learn").
    dataRevision.value = _revision;
    try {
      onDataChanged?.call();
    } catch (_) {}
    _pendingSnapshot = jsonEncode(_data!.toJson());
    _kickDrain();
    return Future.value();
  }

  /// The one writer: keeps writing the newest pending snapshot until none is
  /// left. A failure never kills the pipeline — the snapshot stays pending,
  /// a timer retries, every next change retries, and [saveTrouble] says so.
  static void _kickDrain() {
    if (_draining) return;
    _draining = true;
    _saveRetryTimer?.cancel();
    Future(() async {
      while (true) {
        final snap = _pendingSnapshot;
        if (snap == null) break;
        try {
          await _writeSnapshotToDisk(snap);
          // A newer snapshot may have arrived while writing — loop again.
          if (identical(_pendingSnapshot, snap)) _pendingSnapshot = null;
          if (saveTrouble.value != null) saveTrouble.value = null;
        } catch (_) {
          // Storage said no (full disk, revoked folder, a lock). The words
          // are safe in memory and stay pending — never say "saved" quietly
          // while it isn't. Kind words; no tech dump at the person.
          saveTrouble.value = L.t(
              'Everything you add is held safely in memory, but the storage '
                  'folder is not accepting writes right now. BNS keeps trying '
                  'by itself.',
              'כל מה שהוספת שמור בזיכרון, אבל תיקיית האחסון לא מקבלת כתיבה '
                  'כרגע. BNS ממשיך לנסות לבד.');
          _saveRetryTimer?.cancel();
          _saveRetryTimer = Timer(_saveRetryDelay, _kickDrain);
          break;
        }
      }
      _draining = false;
      _drainDone?.complete();
      _drainDone = null;
    });
  }

  /// One snapshot to disk with a last-known-good net: new → `.tmp`, current
  /// → `.bak`, `.tmp` → real. Never delete-then-hope — if the swap dies
  /// midway, [_load] still finds `.tmp` (a finished write) or `.bak`.
  static Future<void> _writeSnapshotToDisk(String json) async {
    final file = await _storeFile();
    final tmp = File('${file.path}.tmp');
    final bak = File('${file.path}.bak');
    await tmp.writeAsString(json, flush: true);
    if (await file.exists()) {
      try {
        if (await bak.exists()) await bak.delete();
        await file.rename(bak.path);
      } catch (_) {
        // Couldn't set the old copy aside (odd filesystems) — the new truth
        // is already whole in .tmp; clear the way for the rename instead.
        try {
          await file.delete();
        } catch (_) {}
      }
    }
    await tmp.rename(file.path);
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
    // THE HELPER IS NEVER THE GUIDED ONE (owner, 2026-08-17: "the
    // caregiver becomes level 4 user — this is not acceptable"). Stores
    // contaminated before the own-hat merge fix still carry the person's
    // guidedMode on Care — and keeping local flags on merge now PRESERVES
    // that contamination forever. Heal it here, at load: guided is the
    // shape of the person's day, never of the inspector's copy.
    if (s.caregiverDevice && s.guidedMode) {
      s = s.copyWith(guidedMode: false);
      changed = true;
    }
    if (changed) d.settings = s;

    // Gentle seed data on first run so the app feels useful immediately
    if (d.routines.isEmpty && !d.seeded) {
      final now = DateTime.now();
      d.routines.addAll([
        // Hebrew-first seeds (the first users are Israeli; L defaults to
        // 'he' before anyone chose anything).
        Routine(
          id: 'seed-1',
          title: L.t('Morning stretch + water', 'מתיחות בוקר + כוס מים'),
          recurrenceType: RecurrenceType.daily,
          time: '08:00',
          createdAt: now,
          updatedAt: now,
        ),
        Routine(
          id: 'seed-2',
          title: L.t('Take supplements (with food if possible)',
              'תוספים (עם אוכל אם אפשר)'),
          recurrenceType: RecurrenceType.weekdays,
          daysOfWeek: const [1, 2, 3, 4, 5],
          time: '08:15',
          createdAt: now,
          updatedAt: now,
        ),
        Routine(
          id: 'seed-3',
          title: L.t('Gentle walk or sit outside',
              'הליכה רגועה או ישיבה בחוץ'),
          recurrenceType: RecurrenceType.daily,
          createdAt: now,
          updatedAt: now,
        ),
      ]);
      d.seeded = true;
      changed = true;
    }


    // Palace + day's words need text. A voice-only empty note reads as
    // "A voice moment" — seed real words so the list is a list.
    final hasWords = d.captures.any((c) =>
        c.deletedAt == null && memoryWords(c).isNotEmpty);
    if (!hasWords) {
      final now = DateTime.now();
      d.captures.add(QuickCapture(
        id: 'seed-words-1',
        at: now,
        text: L.t(
            'Recording 1\nlamp banana river',
            'הקלטה 1\nמנורה בננה נהר'),
        transcript: L.t('lamp banana river', 'מנורה בננה נהר'),
        tags: const ['quick-thought', 'remember-this'],
        memoryLevel: defaultKeptLevel,
        contextNote: L.t('A kept thought so the palace is not empty.',
            'מחשבה שמורה כדי שהארמון לא יהיה ריק.'),
      ));
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
    return d.events.where((e) => e.date == date).toList();
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

  /// Answer a plan: 'done' (the quiet ✓), 'skipped' (didn't happen, with an
  /// optional kept why), or null — the answer taken back, the plan simply
  /// open again (never secretly something else).
  static Future<void> answerEvent(String id, String? answer,
      {String? reason}) async {
    final d = await _load();
    // THE PERSON ANSWERS (owner, 2026-08-16): a caregiver device builds the
    // day and watches it — it never writes the answer. Done, skip, steps and
    // take-backs are born on the person's own device and arrive here by sync.
    if (d.settings.caregiverDevice) return;
    final i = d.events.indexWhere((e) => e.id == id);
    if (i < 0) return;
    d.events[i] = d.events[i].copyWith(
      answer: answer,
      answerReason: answer == null ? null : reason,
      answerAt: answer == null ? null : DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await _persist();
  }

  // ---- Quick Captures ----

  static Future<List<QuickCapture>> getCapturesForDate(DateTime date) async {
    final d = await _load();
    final list = d.captures
        .where((c) => c.deletedAt == null && captureBelongsToDate(c, date))
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
    // THE PERSON ANSWERS (owner, 2026-08-16) — see answerEvent.
    if (d.settings.caregiverDevice) return;
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
    // THE PERSON ANSWERS (owner, 2026-08-16) — a helper cannot take a ✓
    // back either; the answer belongs to whoever gave it.
    if (d.settings.caregiverDevice) return;
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
    // THE PERSON ANSWERS (owner, 2026-08-16) — see answerEvent.
    if (d.settings.caregiverDevice) return d.stepProgress[key] ?? 0;
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

    // Same law as mergeData: a caregiver device restoring a person's
    // backup carries their DATA, never their hat. And guided is never
    // the helper's hat at all — not even "kept" from a contaminated store.
    final keepRole = local.caregiverDevice;
    d.settings = settings.copyWith(
      serverUrl: local.serverUrl,
      serverToken: local.serverToken,
      deviceId: local.deviceId,
      deviceName: local.deviceName,
      retentionDays: local.retentionDays,
      caregiverDevice: local.caregiverDevice,
      guidedMode: keepRole ? false : null,
      fullCareMode: keepRole ? local.fullCareMode : null,
      careLevel: keepRole ? local.careLevel : null,
      shareName: keepRole ? local.shareName : null,
      careLockHash: keepRole ? local.careLockHash : null,
      // The person-day clock is the person's. A helper copy / default 0
      // must not midnight a set 15:00.
      dayStartHour: adoptPersonDayHour(
        incoming: settings.dayStartHour,
        local: local.dayStartHour,
        incomingIsHelper: settings.caregiverDevice,
        localUnderFullCare: local.fullCareMode || local.guidedMode,
      ),
      dayRolloverHour: adoptPersonDayHour(
        incoming: settings.dayRolloverHour,
        local: local.dayRolloverHour,
        incomingIsHelper: settings.caregiverDevice,
        localUnderFullCare: local.fullCareMode || local.guidedMode,
      ),
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
    // A family-share file only carries shareName (empty deviceId). Applying
    // that stub would reset the helper's care hat and language. Leave local
    // settings; the person's name already lives on the trusted device card.
    if (incomingSettings.deviceId.isEmpty) {
      // Care window stub: no identity, no hats — but the person's DAY
      // includes their clock. 0 stays unset so an empty copy cannot
      // midnight a set 15:00.
      final start = adoptPersonDayHour(
        incoming: incomingSettings.dayStartHour,
        local: local.dayStartHour,
      );
      final end = adoptPersonDayHour(
        incoming: incomingSettings.dayRolloverHour,
        local: local.dayRolloverHour,
      );
      if (start != local.dayStartHour || end != local.dayRolloverHour) {
        d.settings = local.copyWith(
          dayStartHour: start,
          dayRolloverHour: end,
        );
      }
      await _persist();
      return;
    }
    // THE HELPER DOES NOT BECOME THE PERSON (caregiver report,
    // 2026-08-16: after first sync, Care's store said shareName=Ben,
    // guidedMode=true, careLevel=4 — "a later relaunch can confuse who
    // is who"). A caregiver device keeps its OWN hat: role flags, share
    // name and the caregiver's key never adopt the person's.
    //
    // AND THE PERSON DOES NOT BECOME THE HELPER (2026-08-17): hats never
    // travel in EITHER direction. A person's device pulling a Care store
    // must not adopt the helper's flags — adopting guidedMode=false from
    // Care would silently open the level-4 cage, and adopting the
    // helper's shareName/key would rename the person mid-arrangement.
    // Care flags cross only between the person's OWN devices (both sides
    // wearing no helper hat).
    final keepRole = local.caregiverDevice;
    final incomingIsHelper = incomingSettings.caregiverDevice;
    final hatsStay = keepRole || incomingIsHelper;
    d.settings = incomingSettings.copyWith(
      deviceId: local.deviceId,
      deviceName: local.deviceName,
      retentionDays: local.retentionDays,
      serverUrl: local.serverUrl,
      serverToken: local.serverToken,
      caregiverDevice: local.caregiverDevice,
      keybinds: local.keybinds,
      enabledKeybinds: local.enabledKeybinds,
      // A helper's guided is healed to false, never merely "kept".
      guidedMode: keepRole ? false : (hatsStay ? local.guidedMode : null),
      fullCareMode: hatsStay ? local.fullCareMode : null,
      careLevel: hatsStay ? local.careLevel : null,
      shareName: hatsStay ? local.shareName : null,
      careLockHash: hatsStay ? local.careLockHash : null,
      // Person-day clock: a helper's 0 (or an old file that never knew
      // the field) must not eat a set start. Care learns 15 from the
      // person; the person keeps 15 when Care sends midnight back.
      dayStartHour: adoptPersonDayHour(
        incoming: incomingSettings.dayStartHour,
        local: local.dayStartHour,
        incomingIsHelper: incomingIsHelper,
        localUnderFullCare: local.fullCareMode || local.guidedMode,
      ),
      dayRolloverHour: adoptPersonDayHour(
        incoming: incomingSettings.dayRolloverHour,
        local: local.dayRolloverHour,
        incomingIsHelper: incomingIsHelper,
        localUnderFullCare: local.fullCareMode || local.guidedMode,
      ),
    );
    await _persist();
  }

  // ---- Reminder snoozes ("later, by my own will") ----

  /// Push a reminder away until [until] (owner, 2026-08-15: "move a task
  /// by will for a few hours"). Nothing is marked done or skipped — the
  /// task simply knocks again later, because the person said when.
  static Future<void> snoozeReminder(String payload, DateTime until) async {
    final d = await _load();
    d.reminderSnoozes[payload] = until.toIso8601String();
    await _persist();
  }

  /// The still-future snoozes. Expired entries are dropped on read (and
  /// persisted away on the next change) — old snoozes never haunt anyone.
  static Future<Map<String, DateTime>> getReminderSnoozes() async {
    final d = await _load();
    final now = DateTime.now();
    final out = <String, DateTime>{};
    final dead = <String>[];
    d.reminderSnoozes.forEach((k, v) {
      final t = DateTime.tryParse(v);
      if (t == null || !t.isAfter(now)) {
        dead.add(k);
      } else {
        out[k] = t;
      }
    });
    if (dead.isNotEmpty) {
      for (final k in dead) {
        d.reminderSnoozes.remove(k);
      }
      // Quiet cleanup — no need to wake every listener for it; the next
      // real change persists the pruned map.
    }
    return out;
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

  /// The peer's helper hat, learned from its PULL2 ask or its own store
  /// arriving. Decides the care window on every later send (the per-level
  /// wall). No-op when nothing changes or the device is unknown.
  static Future<void> setTrustedDeviceHelper(String id, bool isHelper) async {
    final d = await _load();
    for (var i = 0; i < d.trusted.length; i++) {
      final t = d.trusted[i];
      if (t.id != id) continue;
      if (t.peerIsHelper == isHelper) return;
      d.trusted[i] = t.copyWith(peerIsHelper: isHelper);
      await _persist();
      return;
    }
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
      // Old captures beyond window. THE GARDEN IS SAVED (owner, 2026-08-16:
      // "it should be saved for them to remember"): anything the person
      // deliberately kept — 'remember' AND 'memorize' — never rolls off.
      // A chosen "remember" that self-deletes in two weeks is the void
      // wearing a policy hat. Only passing 'quick' notes ride the window.
      d.captures.removeWhere((c) =>
          c.at.isBefore(cutoff) &&
          c.memoryLevel == MemoryLevel.quick &&
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

  /// Persist the person-day start. Call ONLY from an hour-chip tap
  /// (Today door or Sync). Ranking may assume a 15:00 hole when unset
  /// — it must never land here. Lived 2026-08-17 ~23:57: 15 wrote
  /// itself; a virtual hole is not a chosen day.
  static Future<void> persistDayStartHour(int hour) async {
    final h = hour < 0 ? 0 : (hour > 23 ? 23 : hour);
    final s = await getSettings();
    await updateSettings(s.copyWith(dayStartHour: h));
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
    final base = await BnsHome.dir();
    final dir = Directory('${base.path}/audio');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// A stored audio path that still opens — or null.
  ///
  /// Captures carry absolute paths from the machine that recorded them; a
  /// new PC or user name kills them (the C:\Users\Shaltiel\... ghosts).
  /// When the absolute path is dead, the same FILENAME inside the current
  /// audio folder is the answer — that is where imports and moves put it.
  static Future<String?> resolveAudioPath(String? stored) async {
    if (stored == null || stored.isEmpty) return null;
    try {
      if (await File(stored).exists()) return stored;
      // Ghost paths mix / and \ (they crossed machines) — split on both.
      final name = stored.split(RegExp(r'[\\/]')).last;
      if (name.isEmpty) return null;
      final local = File('${(await getAudioDir()).path}/$name');
      if (await local.exists()) return local.path;
    } catch (_) {}
    return null;
  }

  /// Tests only: forget the in-memory state so the next call re-loads from
  /// disk — a pretend app restart. Never called by the app itself.
  @visibleForTesting
  static Future<void> debugResetForTest() async {
    await flush();
    _saveRetryTimer?.cancel();
    _data = null;
    _pendingSnapshot = null;
    saveTrouble.value = null;
  }

  // ---- Care profiles: the sitting (docs/care-profiles.md) ----

  /// Swap the ACTIVE store to [sittingHome] (a profile's directory), or
  /// back to the seat's own home when null. The current store is flushed
  /// first; every screen repaints through [dataRevision]. The pointer
  /// file is never touched — a sitting is a session, not a move.
  static Future<void> enterHome(Directory? sittingHome) async {
    await flush();
    _saveRetryTimer?.cancel();
    _data = null;
    _pendingSnapshot = null;
    BnsHome.sitIn(sittingHome);
    dataRevision.value = ++_revision;
    try {
      onDataChanged?.call();
    } catch (_) {}
  }

  /// The whole active store as raw JSON — the migration's moving box.
  static Future<Map<String, dynamic>> rawStoreJson() async {
    final d = await _load();
    return d.toJson();
  }

  /// Empty the person-data out of the ACTIVE store (data, logs, trusted),
  /// keeping the seat's own settings. The migration's broom: after the
  /// person moved into their profile, the root store is the caregiver's
  /// alone.
  static Future<void> clearPersonData() async {
    final d = await _load();
    d.routines.clear();
    d.events.clear();
    d.captures.clear();
    d.logs.clear();
    d.trusted.clear();
    await _persist();
  }

  // ---- The home itself ----

  /// Move the whole BNS home (data file, audio/, exports/) to [newPath]
  /// and remember the choice. COPIES, then switches — the old folder stays
  /// behind untouched, a quiet backup. Never deletes the person's data.
  static Future<String> moveHome(String newPath) async {
    final target = Directory(newPath.trim());
    await target.create(recursive: true);
    final old = await BnsHome.dir();
    if (old.path == target.path) return target.path;

    // Let any in-flight write finish in the old home first.
    await flush();

    for (final sub in ['audio', 'exports']) {
      final src = Directory('${old.path}/$sub');
      if (!await src.exists()) continue;
      final dst = Directory('${target.path}/$sub');
      await dst.create(recursive: true);
      await for (final f in src.list()) {
        if (f is! File) continue;
        try {
          await f.copy('${dst.path}/${f.uri.pathSegments.last}');
        } catch (_) {
          // One stubborn file must not stop the move.
        }
      }
    }

    await BnsHome.setDir(target);
    // First persist writes bns_data.json into the NEW home.
    if (_data != null) await _persist();
    return target.path;
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

  /// Reminders the person pushed away for a while (owner, 2026-08-15:
  /// "move a task by will for a few hours"): reminder payload → ISO time
  /// to knock again. Working state like [stepProgress]; past entries are
  /// pruned as they expire.
  final Map<String, String> reminderSnoozes;

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
    Map<String, String>? reminderSnoozes,
  })  : stepProgress = stepProgress ?? {},
        reminderSnoozes = reminderSnoozes ?? {};

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
        if (reminderSnoozes.isNotEmpty) 'reminderSnoozes': reminderSnoozes,
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
        reminderSnoozes: (json['reminderSnoozes'] as Map? ?? const {})
            .map((k, v) => MapEntry(k.toString(), v.toString())),
      );
}
