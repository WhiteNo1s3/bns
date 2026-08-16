import 'package:flutter_test/flutter_test.dart';
import 'package:bns/core/owl_time.dart';

void main() {
  // Saturday-night 02:00: calendar is already Sunday 16 Aug 2026.
  // Person-day ends 05:00, starts 15:00 — still Saturday 15 Aug.
  final owlNight = DateTime(2026, 8, 16, 2, 0);
  const start = 15;
  const end = 5;
  final saturday = DateTime(2026, 8, 15);
  final sunday = DateTime(2026, 8, 16);
  final monday = DateTime(2026, 8, 17);

  group('look-only — future person-day, not calendar midnight', () {
    test('owl: 02:00 with day end 05:00 is still today', () {
      expect(logicalDateOf(owlNight, end), DateTime(2026, 8, 15));
      expect(
        lookOnly(
            day: saturday, now: owlNight, rolloverHour: end, startHour: start),
        isFalse,
      );
      expect(
        hasNotCome(
            day: saturday, now: owlNight, rolloverHour: end, startHour: start),
        isFalse,
      );
      expect(
        offersCompleteOrSkip(
            day: saturday, now: owlNight, rolloverHour: end, startHour: start),
        isTrue,
        reason: 'current person-day still offers complete/skip',
      );
    });

    test('Sunday 08:00 during Saturday-night 02:00 is FUTURE', () {
      expect(
        isFuturePersonDay(sunday,
            now: owlNight, rolloverHour: end, startHour: start),
        isTrue,
      );
      expect(
        lookOnly(
            day: sunday, now: owlNight, rolloverHour: end, startHour: start),
        isTrue,
      );
      expect(
        hasNotCome(
            day: sunday, now: owlNight, rolloverHour: end, startHour: start),
        isTrue,
      );
      expect(
        offersCompleteOrSkip(
            day: sunday, now: owlNight, rolloverHour: end, startHour: start),
        isFalse,
        reason: 'future person-day does not offer complete/skip',
      );
    });

    test('Monday after that night is also look-only', () {
      expect(
        lookOnly(
            day: monday, now: owlNight, rolloverHour: end, startHour: start),
        isTrue,
      );
      expect(
        offersCompleteOrSkip(
            day: monday, now: owlNight, rolloverHour: end, startHour: start),
        isFalse,
      );
    });

    test('after the person-day ends, Sunday is today and can be answered', () {
      final sundayMorning = DateTime(2026, 8, 16, 8, 0);
      expect(logicalDateOf(sundayMorning, end), DateTime(2026, 8, 16));
      expect(
        lookOnly(
            day: sunday,
            now: sundayMorning,
            rolloverHour: end,
            startHour: start),
        isFalse,
      );
      expect(
        offersCompleteOrSkip(
            day: sunday,
            now: sundayMorning,
            rolloverHour: end,
            startHour: start),
        isTrue,
      );
      expect(
        lookOnly(
            day: monday,
            now: sundayMorning,
            rolloverHour: end,
            startHour: start),
        isTrue,
      );
    });

    test('calendar midnight without owl still treats 02:00 as that date', () {
      expect(
        lookOnly(day: sunday, now: owlNight, rolloverHour: 0, startHour: 0),
        isFalse,
      );
      expect(
        lookOnly(day: monday, now: owlNight, rolloverHour: 0, startHour: 0),
        isTrue,
      );
    });
  });
}
