import 'dart:io';
import 'package:isar/isar.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:bns/core/models/models.dart';

/// Central Isar instance + helper methods.
/// All persistence for routines, events, captures, logs, settings.
class IsarService {
  static Isar? _isar;
  static const _uuid = Uuid();

  static Future<Isar> get instance async {
    if (_isar != null) return _isar!;
    final dir = await getApplicationDocumentsDirectory();
    _isar = await Isar.open(
      [
        RoutineSchema,
        CalendarEventSchema,
        QuickCaptureSchema,
        CompletionLogSchema,
        AppSettingsSchema,
        TrustedDeviceSchema,
      ],
      directory: dir.path,
      name: 'bns',
    );
    await _ensureDefaultSettings(_isar!);
    return _isar!;
  }

  static Future<void> _ensureDefaultSettings(Isar isar) async {
    final settings = await isar.appSettings.where().findFirst();
    if (settings == null) {
      await isar.writeTxn(() async {
        await isar.appSettings.put(AppSettings(
          deviceName: 'My BNS Device',
          retentionDays: 14,
          userType: 'normal',
        ));
      });
    }

    // Gentle seed data on first run so the app feels useful immediately
    final existingRoutines = await isar.routines.where().count();
    if (existingRoutines == 0) {
      final now = DateTime.now();
      await isar.writeTxn(() async {
        await isar.routines.putAll([
          Routine(
            id: 'seed-1',
            title: 'Morning stretch + water',
            recurrenceType: RecurrenceType.daily,
            daysOfWeek: const [],
            time: '08:00',
            createdAt: now,
            updatedAt: now,
          ),
          Routine(
            id: 'seed-2',
            title: 'Take supplements (with food if possible)',
            recurrenceType: RecurrenceType.weekdays,
            daysOfWeek: const [1,2,3,4,5],
            time: '08:15',
            createdAt: now,
            updatedAt: now,
          ),
          Routine(
            id: 'seed-3',
            title: 'Gentle walk or sit outside',
            recurrenceType: RecurrenceType.daily,
            daysOfWeek: const [],
            createdAt: now,
            updatedAt: now,
          ),
        ]);
      });
    }
  }

  // ---- Routines ----
  static Future<List<Routine>> getAllRoutines() async {
    final isar = await instance;
    return isar.routines.where().sortByCreatedAtDesc().findAll();
  }

  static Future<Routine> addRoutine(Routine routine) async {
    final isar = await instance;
    final withId = routine.id.isEmpty
        ? routine.copyWith(id: _uuid.v4(), createdAt: DateTime.now(), updatedAt: DateTime.now())
        : routine;
    await isar.writeTxn(() async {
      await isar.routines.put(withId);
    });
    return withId;
  }

  static Future<void> updateRoutine(Routine routine) async {
    final isar = await instance;
    final updated = routine.copyWith(updatedAt: DateTime.now());
    await isar.writeTxn(() async {
      await isar.routines.put(updated);
    });
  }

  static Future<void> deleteRoutine(String id) async {
    final isar = await instance;
    await isar.writeTxn(() async {
      await isar.routines.deleteById(id);
    });
  }

  // ---- Calendar Events ----
  static Future<List<CalendarEvent>> getEventsForDate(String date) async {
    final isar = await instance;
    return isar.calendarEvents.filter().dateEqualTo(date).findAll();
  }

  static Future<List<CalendarEvent>> getAllEvents() async {
    final isar = await instance;
    return isar.calendarEvents.where().sortByDate().findAll();
  }

  static Future<CalendarEvent> addEvent(CalendarEvent event) async {
    final isar = await instance;
    final withId = event.id.isEmpty
        ? event.copyWith(id: _uuid.v4(), createdAt: DateTime.now(), updatedAt: DateTime.now())
        : event;
    await isar.writeTxn(() async {
      await isar.calendarEvents.put(withId);
    });
    return withId;
  }

  // ---- Quick Captures ----
  static Future<List<QuickCapture>> getCapturesForDate(DateTime date) async {
    final isar = await instance;
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    return isar.quickCaptures
        .filter()
        .atBetween(start, end)
        .deletedAtIsNull()
        .sortByAtDesc()
        .findAll();
  }

  static Future<List<QuickCapture>> getAllCaptures() async {
    final isar = await instance;
    return isar.quickCaptures
        .filter()
        .deletedAtIsNull()
        .sortByAtDesc()
        .findAll();
  }

  static Future<QuickCapture> addCapture(QuickCapture capture) async {
    final isar = await instance;
    final withId = capture.id.isEmpty ? capture.copyWith(id: _uuid.v4()) : capture;
    await isar.writeTxn(() async {
      await isar.quickCaptures.put(withId);
    });
    return withId;
  }

  // ---- Completion Logs ----
  static Future<List<CompletionLog>> getLogsForDate(String date) async {
    final isar = await instance;
    return isar.completionLogs.filter().dateEqualTo(date).findAll();
  }

  static Future<List<CompletionLog>> getAllCompletionLogs() async {
    final isar = await instance;
    return isar.completionLogs.where().findAll();
  }

  static Future<void> logCompletion({
    required String routineId,
    required String date,
    required CompletionStatus status,
    String? reason,
    String? reasonAudioPath,
  }) async {
    final isar = await instance;
    final log = CompletionLog(
      id: _uuid.v4(),
      routineId: routineId,
      date: date,
      status: status,
      reason: reason,
      reasonAudioPath: reasonAudioPath,
      at: DateTime.now(),
    );
    await isar.writeTxn(() async {
      await isar.completionLogs.put(log);
    });
  }

  // ---- Full snapshot helpers for .bns imaging ----
  static Future<({ 
    List<Routine> routines, 
    List<CalendarEvent> events, 
    List<QuickCapture> captures, 
    List<CompletionLog> logs, 
    AppSettings settings 
  })> getFullSnapshot() async {
    final isar = await instance;
    final routines = await isar.routines.where().findAll();
    final events = await isar.calendarEvents.where().findAll();
    final captures = await isar.quickCaptures.where().findAll();
    final logs = await isar.completionLogs.where().findAll();
    final settings = await getSettings();
    return (routines: routines, events: events, captures: captures, logs: logs, settings: settings);
  }

  /// Wipes current data and restores from imported snapshot.
  /// Use with care — caller should ask user.
  static Future<void> replaceAllData({
    required List<Routine> routines,
    required List<CalendarEvent> events,
    required List<QuickCapture> captures,
    required List<CompletionLog> logs,
    required AppSettings settings,
  }) async {
    final isar = await instance;
    await isar.writeTxn(() async {
      await isar.routines.clear();
      await isar.calendarEvents.clear();
      await isar.quickCaptures.clear();
      await isar.completionLogs.clear();

      if (routines.isNotEmpty) await isar.routines.putAll(routines);
      if (events.isNotEmpty) await isar.calendarEvents.putAll(events);
      if (captures.isNotEmpty) await isar.quickCaptures.putAll(captures);
      if (logs.isNotEmpty) await isar.completionLogs.putAll(logs);

      // Preserve local retention pref even on full replace
      final current = await getSettings();
      final toPut = settings.copyWith(retentionDays: current.retentionDays);
      await isar.appSettings.put(toPut);
    });
  }

  /// Merge strategy (last write wins by timestamp where possible).
  /// Simple MVP: for each item, if newer or not present, insert/update.
  static Future<void> mergeData({
    required List<Routine> routines,
    required List<CalendarEvent> events,
    required List<QuickCapture> captures,
    required List<CompletionLog> logs,
    required AppSettings incomingSettings,
  }) async {
    final isar = await instance;

    await isar.writeTxn(() async {
      // Routines - upsert
      for (final r in routines) {
        final existing = await isar.routines.get(r.id);
        if (existing == null || (r.updatedAt.isAfter(existing.updatedAt))) {
          await isar.routines.put(r);
        }
      }
      for (final e in events) {
        final existing = await isar.calendarEvents.get(e.id);
        if (existing == null || e.updatedAt.isAfter(existing.updatedAt)) {
          await isar.calendarEvents.put(e);
        }
      }
      for (final c in captures) {
        final existing = await isar.quickCaptures.get(c.id);
        if (existing == null) {
          await isar.quickCaptures.put(c);
        }
      }
      for (final l in logs) {
        final existing = await isar.completionLogs.get(l.id);
        if (existing == null) {
          await isar.completionLogs.put(l);
        }
      }

      // Prefer the device name from the more recently exported if possible
      // But preserve OUR local retentionDays preference (user's choice for file size/sync speed)
      final current = await getSettings();
      final mergedSettings = incomingSettings.copyWith(
        retentionDays: current.retentionDays,
      );
      await isar.appSettings.put(mergedSettings);
    });
  }

  // ---- Trusted Devices (for secure auto-sync) ----
  static Future<List<TrustedDevice>> getTrustedDevices() async {
    final isar = await instance;
    return isar.trustedDevices.where().findAll();
  }

  static Future<TrustedDevice?> getTrustedDevice(String deviceId) async {
    final isar = await instance;
    return isar.trustedDevices.get(deviceId);
  }

  static Future<void> saveTrustedDevice(TrustedDevice device) async {
    final isar = await instance;
    await isar.writeTxn(() async {
      await isar.trustedDevices.put(device);
    });
  }

  static Future<void> removeTrustedDevice(String id) async {
    final isar = await instance;
    await isar.writeTxn(() async {
      await isar.trustedDevices.deleteById(id);
    });
  }

  static Future<void> updateTrustedDeviceLastSync(String id, String address) async {
    final isar = await instance;
    final device = await isar.trustedDevices.get(id);
    if (device != null) {
      await isar.writeTxn(() async {
        await isar.trustedDevices.put(
          device.copyWith(
            lastAddress: address,
            lastSyncedAt: DateTime.now(),
          ),
        );
      });
    }
  }

  // ---- Rolling data retention to keep files small and sync fast ----
  // Default 14 days (2 weeks). Old past data is deleted.
  // Future calendar events are preserved for long-term planning (even 10000+ years).
  // User can expand retention (slower/larger .bns) or reset to default.
  // Routines and core settings are never pruned.
  static Future<void> pruneOldData() async {
    final isar = await instance;
    final settings = await getSettings();
    final retention = settings.retentionDays;
    if (retention <= 0) return; // unlimited / user wants huge redundant file

    final cutoff = DateTime.now().subtract(Duration(days: retention));
    final cutoffDateStr = DateFormat('yyyy-MM-dd').format(cutoff);
    final trashCutoff = DateTime.now().subtract(const Duration(days: 3));

    await isar.writeTxn(() async {
      // Delete old completion logs (per-day routine status)
      await isar.completionLogs
          .filter()
          .dateLessThan(cutoffDateStr)
          .deleteAll();

      // Delete old quick captures (historical notes/voice beyond window)
      // But keep 'memorize' level as permanent memories
      // Also clean trash older than 3 days
      final oldCaptures = await isar.quickCaptures
          .filter()
          .atLessThan(cutoff)
          .findAll();
      for (final cap in oldCaptures) {
        if (cap.memoryLevel != MemoryLevel.memorize && (cap.deletedAt == null || cap.deletedAt!.isBefore(trashCutoff))) {
          await isar.quickCaptures.deleteById(cap.id);
        }
      }

      // Clean up trashed captures older than 3 days (permanent delete)
      final trashedOld = await isar.quickCaptures
          .filter()
          .deletedAtIsNotNull()
          .deletedAtLessThan(trashCutoff)
          .findAll();
      for (final cap in trashedOld) {
        await isar.quickCaptures.deleteById(cap.id);
      }

      // Delete old PAST calendar events only.
      // Future dates (planning far ahead) are kept even if 10000 years.
      final candidates = await isar.calendarEvents
          .filter()
          .dateLessThan(cutoffDateStr)
          .findAll();
      for (final ev in candidates) {
        try {
          final evDate = DateTime.parse(ev.date);
          if (evDate.isBefore(cutoff)) {
            await isar.calendarEvents.deleteById(ev.id);
          }
        } catch (_) {
          // bad date, skip
        }
      }
    });
  }

  static Future<void> updateRetentionDays(int days) async {
    final isar = await instance;
    final current = await getSettings();
    await isar.writeTxn(() async {
      await isar.appSettings.put(
        current.copyWith(retentionDays: days),
      );
    });
    // Prune immediately after change
    await pruneOldData();
  }

  static Future<void> resetRetentionToDefault() async {
    await updateRetentionDays(14);
  }

  // ---- Trash / Soft delete (user control) ----
  // Memories (and captures) can be removed by user.
  // Everything the user wants he can do.
  // Advise if sure (confirmation in UI).
  // Leave in trash for 3 days, then auto permanent delete (in prune).
  // .bns delivers full active data (trashed excluded from export).

  static Future<void> softDeleteCapture(String id) async {
    final isar = await instance;
    final cap = await isar.quickCaptures.get(id);
    if (cap != null) {
      await isar.writeTxn(() async {
        await isar.quickCaptures.put(cap.copyWith(deletedAt: DateTime.now()));
      });
    }
  }

  static Future<void> restoreCapture(String id) async {
    final isar = await instance;
    final cap = await isar.quickCaptures.get(id);
    if (cap != null) {
      await isar.writeTxn(() async {
        await isar.quickCaptures.put(cap.copyWith(deletedAt: null));
      });
    }
  }

  static Future<List<QuickCapture>> getTrashedCaptures() async {
    final isar = await instance;
    return isar.quickCaptures
        .filter()
        .deletedAtIsNotNull()
        .sortByDeletedAtDesc()
        .findAll();
  }

  // Update export to only active data (full current state, no trash)
  // (already handled in getFullSnapshot via getAll* which exclude deleted)
}

  // ---- Settings ----
  static Future<AppSettings> getSettings() async {
    final isar = await instance;
    return (await isar.appSettings.where().findFirst())!;
  }

  static Future<void> updateSettings(AppSettings settings) async {
    final isar = await instance;
    await isar.writeTxn(() async {
      await isar.appSettings.put(settings);
    });
  }

  // Audio directory helper
  static Future<Directory> getAudioDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/audio');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }
}
