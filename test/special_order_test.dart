// Special orders + silent didn't (owner lived direction, 2026-07-20).
import 'package:flutter_test/flutter_test.dart';
import 'package:bns/core/models/models.dart';

void main() {
  group('CalendarEvent special order', () {
    test('legacy events stay ordinary (defaults)', () {
      final legacy = CalendarEvent.fromJson({
        'id': 'old',
        'title': 'Doctor',
        'date': '2026-07-15',
      });
      expect(legacy.isSpecialOrder, false);
      expect(legacy.disruptive, false);
      expect(legacy.endDate, isNull);
      expect(legacy.companionNote, isNull);
    });

    test('special order fields survive JSON roundtrip', () {
      final e = CalendarEvent(
        id: 'so1',
        title: 'Month away',
        date: '2026-08-01',
        endDate: '2026-08-31',
        isSpecialOrder: true,
        disruptive: true,
        companionNote: 'Parents are coming',
        notes: 'Cold feet are ok',
        isAllDay: true,
        createdAt: DateTime.utc(2026, 7, 20),
        updatedAt: DateTime.utc(2026, 7, 20),
      );
      final back = CalendarEvent.fromJson(e.toJson());
      expect(back.isSpecialOrder, true);
      expect(back.disruptive, true);
      expect(back.endDate, '2026-08-31');
      expect(back.companionNote, 'Parents are coming');
      expect(back.notes, 'Cold feet are ok');
    });

    test('activeOn spans multi-day special orders', () {
      final e = CalendarEvent(
        id: 'so2',
        title: 'Laptop repair drive',
        date: '2026-07-20',
        endDate: '2026-07-22',
        isSpecialOrder: true,
        disruptive: true,
        createdAt: DateTime.utc(2026, 7, 20),
        updatedAt: DateTime.utc(2026, 7, 20),
      );
      expect(e.activeOn('2026-07-19'), false);
      expect(e.activeOn('2026-07-20'), true);
      expect(e.activeOn('2026-07-21'), true);
      expect(e.activeOn('2026-07-22'), true);
      expect(e.activeOn('2026-07-23'), false);
    });

    test('single-day event activeOn is just the date', () {
      final e = CalendarEvent(
        id: 'so3',
        title: 'One errand',
        date: '2026-07-20',
        isSpecialOrder: true,
        createdAt: DateTime.utc(2026, 7, 20),
        updatedAt: DateTime.utc(2026, 7, 20),
      );
      expect(e.activeOn('2026-07-20'), true);
      expect(e.activeOn('2026-07-21'), false);
    });
  });

  group('CompletionLog silent didn\'t', () {
    test('skipped with null reason is valid', () {
      final log = CompletionLog(
        id: 'l1',
        routineId: 'r1',
        date: '2026-07-20',
        status: CompletionStatus.skipped,
        reason: null,
        at: DateTime.utc(2026, 7, 20),
      );
      final back = CompletionLog.fromJson(log.toJson());
      expect(back.status, CompletionStatus.skipped);
      expect(back.reason, isNull);
    });
  });

  group('Pass 7 settings + capture fields', () {
    test('rediscovery and fog fields default and roundtrip', () {
      expect(const AppSettings().hasSeenListTutorial, false);
      expect(const AppSettings().fogReading, false);
      expect(const AppSettings().listReadyNudgeEnabled, true);
      final s = const AppSettings().copyWith(
        fogReading: true,
        hasSeenListTutorial: true,
        listReadyNudgeEnabled: false,
        lastOpenedAt: DateTime.utc(2026, 7, 1),
      );
      final back = AppSettings.fromJson(s.toJson());
      expect(back.fogReading, true);
      expect(back.hasSeenListTutorial, true);
      expect(back.listReadyNudgeEnabled, false);
      expect(back.lastOpenedAt?.day, 1);
      expect(back.daysSinceLastOpen, isNotNull);
    });

    test('transcript field survives capture roundtrip', () {
      final c = QuickCapture(
        id: 'c1',
        at: DateTime.utc(2026, 7, 20),
        text: 'Visit notes',
        transcript: 'Doctor said rest and water',
        tags: const ['doctor-visit', 'family'],
        memoryLevel: MemoryLevel.remember,
      );
      final back = QuickCapture.fromJson(c.toJson());
      expect(back.transcript, 'Doctor said rest and water');
      expect(back.tags, contains('doctor-visit'));
      // Legacy captures without transcript stay fine.
      final legacy = QuickCapture.fromJson({
        'id': 'old',
        'at': '2026-01-01T00:00:00.000Z',
      });
      expect(legacy.transcript, isNull);
    });
  });
}
