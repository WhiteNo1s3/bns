/// "LATER, BY MY WILL" — the in-app postpone (owner, 2026-08-16, for
/// levels 3–4: "simple vertical bar to extend, each tick 15 minutes,
/// max 3 hours... this is up to you").
///
/// The delegated decision, decided: NO DRAGGING. A draggable bar demands
/// precision from exactly the hands that do not have it — so the bar is
/// FEEDBACK (it fills), and the input is big +15/−15 taps, each one a
/// haptic tick. Common cases are one to four taps; the maximum stays the
/// owner's 3 hours (12 ticks) because reaching it is rare, and capping
/// lower would cost the nap that postponing exists for.
///
/// Time is spoken the way a person says it — "שעה ורבע", never "01:15:00".
library;

/// One tick of the bar.
const int kPostponeTickMinutes = 15;

/// The whole bar. 12 ticks = the owner's 3 hours.
const int kPostponeMaxTicks = 12;

/// [ticks] (1-based) as a human phrase, in the app's two languages.
String postponeLabel(int ticks, {required bool hebrew}) {
  final t = ticks.clamp(1, kPostponeMaxTicks);
  final minutes = t * kPostponeTickMinutes;
  if (hebrew) {
    switch (t) {
      case 1:
        return 'רבע שעה';
      case 2:
        return 'חצי שעה';
      case 3:
        return '45 דקות';
      case 4:
        return 'שעה';
      case 5:
        return 'שעה ורבע';
      case 6:
        return 'שעה וחצי';
      case 7:
        return 'שעה ו־45 דקות';
      case 8:
        return 'שעתיים';
      case 9:
        return 'שעתיים ורבע';
      case 10:
        return 'שעתיים וחצי';
      case 11:
        return 'שעתיים ו־45 דקות';
      default:
        return 'שלוש שעות';
    }
  }
  final h = minutes ~/ 60, m = minutes % 60;
  if (h == 0) return '$m minutes';
  final hours =
      h == 1 ? 'an hour' : (h == 2 ? 'two hours' : 'three hours');
  if (m == 0) return hours;
  if (m == 30) return h == 1 ? 'an hour and a half' : '$hours and a half';
  return '$hours and $m minutes';
}
