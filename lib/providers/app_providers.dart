import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bns/core/models/models.dart';
import 'package:bns/data/local/isar_service.dart';

// Simple async providers + notifiers for the app state.

final routinesProvider = FutureProvider<List<Routine>>((ref) async {
  return IsarService.getAllRoutines();
});

final eventsForDateProvider = FutureProvider.family<List<CalendarEvent>, String>((ref, date) async {
  return IsarService.getEventsForDate(date);
});

final capturesForDateProvider = FutureProvider.family<List<QuickCapture>, DateTime>((ref, date) async {
  return IsarService.getCapturesForDate(date);
});

final settingsProvider = FutureProvider<AppSettings>((ref) async {
  return IsarService.getSettings();
});

// Notifier for mutations (Today actions etc.)
class RoutinesNotifier extends AsyncNotifier<List<Routine>> {
  @override
  Future<List<Routine>> build() async {
    return IsarService.getAllRoutines();
  }

  Future<void> add(Routine r) async {
    state = const AsyncLoading();
    await IsarService.addRoutine(r);
    state = AsyncData(await IsarService.getAllRoutines());
  }

  Future<void> toggleComplete(String routineId, String date, bool isDone) async {
    final status = isDone ? CompletionStatus.done : CompletionStatus.skipped;
    await IsarService.logCompletion(
      routineId: routineId,
      date: date,
      status: status,
    );
    // Refresh routines list if needed (in real would be smarter)
    state = AsyncData(await IsarService.getAllRoutines());
  }
}

final routinesNotifierProvider = AsyncNotifierProvider<RoutinesNotifier, List<Routine>>(
  () => RoutinesNotifier(),
);

// Quick capture saver
class CapturesNotifier extends AsyncNotifier<List<QuickCapture>> {
  @override
  Future<List<QuickCapture>> build() => IsarService.getAllCaptures();

  Future<QuickCapture> save(QuickCapture c) async {
    final saved = await IsarService.addCapture(c);
    state = AsyncData(await IsarService.getAllCaptures());
    return saved;
  }
}

final capturesNotifierProvider = AsyncNotifierProvider<CapturesNotifier, List<QuickCapture>>(
  () => CapturesNotifier(),
);
