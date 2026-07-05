import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:bns/ui/theme.dart';
import 'package:bns/core/models/models.dart';
import 'package:bns/providers/app_providers.dart';
import 'package:bns/ui/widgets/routine_tile.dart';
import 'package:bns/ui/widgets/quick_capture_bar.dart';
import 'package:bns/ui/widgets/bns_app_bar.dart';
import 'package:bns/features/capture/quick_capture_screen.dart';
import 'package:bns/features/calendar/calendar_screen.dart';
import 'package:bns/features/sync/sync_screen.dart';
import 'package:bns/features/routines/routines_screen.dart';
import 'package:bns/features/memory/memories_screen.dart';
import 'package:bns/platform/android_widget.dart';
import 'package:bns/data/local/isar_service.dart';
import 'package:bns/services/notifications_service.dart';
import 'package:bns/services/file_handler.dart';
import 'package:bns/core/models/trusted_device.dart';
import 'package:confetti/confetti.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationsService.init();

  // Desktop: basic .bns handling (full support via platform channels in later builds)
  // For now the handler is ready; real args come from the embedder on open-with.

  await NotificationsService.rescheduleAll();

  // Prune old historical data on startup to keep files small (2 week default rolling)
  // Future planning (calendar) is preserved. Routines stay.
  await IsarService.pruneOldData();

  runApp(const ProviderScope(child: BnsApp()));
}

final _router = GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const TodayScreen(),
    ),
    GoRoute(
      path: '/calendar',
      builder: (context, state) => const CalendarScreen(),
    ),
    GoRoute(
      path: '/capture',
      builder: (context, state) {
        final extra = state.extra as Map<String, String?>? ?? {};
        return QuickCaptureScreen(
          linkedRoutineId: extra['linkedRoutineId'],
          initialText: extra['initialText'],
        );
      },
    ),
    GoRoute(
      path: '/sync',
      builder: (context, state) => const SyncScreen(),
    ),
    GoRoute(
      path: '/routines',
      builder: (context, state) => const RoutinesScreen(),
    ),
    GoRoute(
      path: '/memories',
      builder: (context, state) => const MemoriesScreen(),
    ),
  ],
);

class BnsApp extends StatelessWidget {
  const BnsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'BNS',
      debugShowCheckedModeBanner: false,
      theme: BnsTheme.build(
        palette: RelaxingPalette.teal,
        mode: ThemeModeSetting.system,
      ),
      darkTheme: BnsTheme.build(
        palette: RelaxingPalette.teal,
        mode: ThemeModeSetting.dark,
      ),
      routerConfig: _router,
    );
  }
}

/// Today screen using real Riverpod + Isar data.
/// Positive, forgiving, linked to calendar and capture.
/// Confetti + skip-with-reason flow preserved.
class TodayScreen extends ConsumerStatefulWidget {
  const TodayScreen({super.key});

  @override
  ConsumerState<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends ConsumerState<TodayScreen> {
  late ConfettiController _confetti;
  final _diaryController = TextEditingController(); // for interactive diary entry

  @override
  void initState() {
    super.initState();
    _confetti = ConfettiController(duration: const Duration(seconds: 2));
  }

  @override
  void dispose() {
    _confetti.dispose();
    _diaryController.dispose();
    super.dispose();
  }

  Future<void> _toggleComplete(Routine r) async {
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final isDone = await _isDoneToday(r.id, todayStr);

    await IsarService.logCompletion(
      routineId: r.id,
      date: todayStr,
      status: isDone ? CompletionStatus.skipped : CompletionStatus.done,
    );

    if (!isDone) {
      _confetti.play();
    }

    // Refresh
    ref.invalidate(routinesProvider);
    setState(() {}); // force rebuild for logs

    // Update Android widget (gadget) with fresh data
    AndroidBnsWidget.updateWidget();

    // Offer "Remember this" for what happened in the routine (crises, why)
    if (!isDone && mounted) {
      final remember = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Remember this?'),
          content: Text('Capture what happened during "${r.title}" today. The day and context can be memorized.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not now')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Yes, remember this moment'),
            ),
          ],
        ),
      );
      if (remember == true) {
        await context.push('/capture', extra: {
          'linkedRoutineId': r.id,
          'initialText': 'What happened in this routine today? Why?',
        });
      }
    }
  }

  Future<bool> _isDoneToday(String routineId, String date) async {
    final logs = await IsarService.getLogsForDate(date);
    return logs.any((l) => l.routineId == routineId && l.status == CompletionStatus.done);
  }

  void _openSkipSheet(Routine r) {
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('No pressure at all.', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            const Text('It can help to capture why. Voice or text — or just close.'),
            const SizedBox(height: 20),
            QuickCaptureBar(
              onTap: () {
                Navigator.pop(ctx);
                context.push('/capture', extra: {
                  'linkedRoutineId': r.id,
                  'initialText': 'Reason for today / what happened: ',
                });
              },
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await IsarService.logCompletion(
                  routineId: r.id,
                  date: todayStr,
                  status: CompletionStatus.skipped,
                );
                ref.invalidate(routinesProvider);
              },
              child: const Text('Close — no need to explain'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveDiaryEntry() async {
    final text = _diaryController.text.trim();
    if (text.isEmpty) return;

    // Save as diary capture - interactive moving diary
    final capture = QuickCapture(
      id: '',
      at: DateTime.now(),
      text: text,
      tags: ['diary', 'goal-progress'],
      memoryLevel: MemoryLevel.remember,
      contextNote: 'Daily interactive diary - goals & wins',
    );
    await IsarService.addCapture(capture);
    _diaryController.clear();
    ref.invalidate(routinesProvider);
    AndroidBnsWidget.updateWidget();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved to diary! V for done — no win is too small. You made it!')),
      );
      // Offer to make permanent in garden
      final perm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Memorize this win?'),
          content: const Text('Add to your permanent memory garden?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not now')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes')),
          ],
        ),
      );
      if (perm == true) {
        final memCap = QuickCapture(
          id: '',
          at: DateTime.now(),
          text: text,
          tags: ['diary', 'memorize-win', 'good'],
          memoryLevel: MemoryLevel.memorize,
          contextNote: 'Permanent diary win - you did it!',
        );
        await IsarService.addCapture(memCap);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final routinesAsync = ref.watch(routinesProvider);
    final today = DateTime.now();
    final todayStr = DateFormat('yyyy-MM-dd').format(today);

    return Scaffold(
      appBar: BnsAppBar(
        title: 'Today • BNS',
        leading: Image.asset('assets/icon/bns_logo.png', height: 28, width: 28),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: 'LAN Sync',
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('LAN sync (zero effort) will be here.')),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.calendar_month),
            tooltip: 'Calendar',
            onPressed: () => context.push('/calendar'),
          ),
          IconButton(
            icon: const Icon(Icons.sync_alt),
            tooltip: 'Sync your devices',
            onPressed: () => context.push('/sync'),
          ),
          IconButton(
            icon: const Icon(Icons.psychology),
            tooltip: 'Memories',
            onPressed: () => context.push('/memories'),
          ),
        ],
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Hey — whatever today looks like is okay.',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                'Routines support you. They never get mad.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),

              // Gentle awareness of sync status (helps memory)
              FutureBuilder<List<TrustedDevice>>(
                future: IsarService.getTrustedDevices(),
                builder: (ctx, snap) {
                  if (!snap.hasData || snap.data!.isEmpty) return const SizedBox.shrink();
                  final last = snap.data!.map((d) => d.lastSyncedAt).reduce((a, b) => a.isAfter(b) ? a : b);
                  return Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 12),
                    child: Text(
                      'Last synced across devices: ${last.toLocal().toString().substring(0, 16)}',
                      style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  );
                },
              ),
              const SizedBox(height: 28),

              Text('Today\'s gentle steps', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),

              routinesAsync.when(
                data: (routines) {
                  final todaysRoutines = routines.where((r) => r.appliesOn(today) && r.isActive).toList();

                  if (todaysRoutines.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text('No active routines for today. Add some from settings (coming soon).'),
                    );
                  }

                  return Column(
                    children: todaysRoutines.map((r) {
                      return FutureBuilder<bool>(
                        future: _isDoneToday(r.id, todayStr),
                        builder: (ctx, snap) {
                          final done = snap.data ?? false;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: RoutineTile(
                              routine: r,
                              isDone: done,
                              onToggle: () => _toggleComplete(r),
                              onSkip: () => _openSkipSheet(r),
                            ),
                          );
                        },
                      );
                    }).toList(),
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Text('Error loading: $e'),
              ),

              const SizedBox(height: 24),

              // Interactive Moving Diary integration
              Text('Moving Diary - Remind & Set Goals, Mark V for Done', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                'Set goals, note wins. Every step forward counts — we applaud any progress (big or small like "pissing on floor then in toilet").',
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _diaryController,
                maxLines: 2,
                decoration: const InputDecoration(
                  hintText: 'Today\'s goal or win... (e.g. completed morning routine)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 4),
              ElevatedButton.icon(
                onPressed: _saveDiaryEntry,
                icon: const Icon(Icons.check),
                label: const Text('Save to Diary (V = done! You made it)'),
              ),

              const SizedBox(height: 24),
              QuickCaptureBar(
                onTap: () => context.push('/capture'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => context.push('/calendar'),
                icon: const Icon(Icons.event_note),
                label: const Text('Open calendar for appointments & day notes'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => context.push('/routines'),
                icon: const Icon(Icons.list_alt),
                label: const Text('Manage all routines (add, edit, delete)'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => context.push('/memories'),
                icon: const Icon(Icons.psychology),
                label: const Text('Memory section: Remember & Memorize what happened'),
              ),
            ],
          ),

          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confetti,
              blastDirectionality: BlastDirectionality.explosive,
              shouldLoop: false,
              numberOfParticles: 28,
              colors: const [
                Color(0xFF14B8A6),
                Color(0xFF8B5CF6),
                Color(0xFFFDE047),
                Color(0xFFFB923C),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final routines = await IsarService.getAllRoutines();
          final todayR = routines.where((r) => r.appliesOn(today)).toList();
          if (todayR.isNotEmpty) _toggleComplete(todayR.first);
        },
        label: const Text('Mark something done'),
        icon: const Icon(Icons.check_rounded),
      ),
    );
  }
}
