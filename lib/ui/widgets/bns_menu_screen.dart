/// THE MENU — every room in the house, written in words (owner, 2026-08-15:
/// "we need a side menu to pop instead of the bullshit icons this ain't
/// jail". First beta reports: the app read as desktop-first, phone
/// navigation felt cramped and icon-coded).
///
/// It POPS instead of sliding: a Material drawer animates in from the
/// edge, and motion is banned here by the older law ("the app must be
/// static to not make nausea"). A full page appears in place — the same
/// static transition every screen uses — and lists everything by NAME.
/// One press on תפריט, and the whole app is readable: no icon has to be
/// decoded, nothing hides behind a glyph.
///
/// Rows are 68dp with 20sp words — sized for the hands and eyes this app
/// is for, not for a design award.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:bns/core/i18n/l.dart';
import 'package:bns/core/version.dart';
import 'package:bns/data/local/isar_service.dart';
import 'package:bns/ui/widgets/bns_app_bar.dart';

class BnsMenuScreen extends StatefulWidget {
  const BnsMenuScreen({super.key});

  @override
  State<BnsMenuScreen> createState() => _BnsMenuScreenState();
}

class _BnsMenuScreenState extends State<BnsMenuScreen> {
  bool _guided = false;

  @override
  void initState() {
    super.initState();
    IsarService.getSettings().then((s) {
      if (mounted && s.guidedMode != _guided) {
        setState(() => _guided = s.guidedMode);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // ONE MAP (owner, 2026-08-16, after the level-1 tester's "two maps"):
    // the doors at the bottom hold the main rooms — Today, Keep this,
    // Memories, Calendar — and THIS list holds only the rest. No room has
    // two doors anymore. Guided mode (level 4) never sees this screen.
    final doors = <(String route, IconData icon, String label, String hint)>[
      (
        '/day',
        Icons.auto_stories,
        L.t('Today\'s words', 'מילות היום'),
        L.t('Everything said and done today', 'כל מה שנאמר ונעשה היום')
      ),
      // The alarm page (owner, 2026-08-19: "its not only to wake up,
      // its to set real clock to alarm") — the wake, what's left today,
      // and real rings planted in the phone's own clock.
      (
        '/wake',
        Icons.alarm,
        L.t('Alarm clock', 'שעון מעורר'),
        L.t('What\'s left today — and a real ring for any mission',
            'מה נשאר היום — וצלצול אמיתי לכל משימה')
      ),
      if (!_guided)
        (
          '/routines',
          Icons.list_alt,
          L.t('My routines', 'השגרות שלי'),
          L.t('Add, change, remove', 'להוסיף, לשנות, להסיר')
        ),
      (
        '/sync',
        Icons.settings,
        L.t('Settings & sync', 'הגדרות וסנכרון'),
        L.t('Devices, reminders, backup', 'מכשירים, תזכורות, גיבוי')
      ),
    ];

    return Scaffold(
      appBar: BnsAppBar(title: L.t('Menu', 'תפריט')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 14),
            child: Text(
              L.t(
                  'The main rooms live on the doors below. Here is the rest.',
                  'החדרים העיקריים נמצאים בדלתות למטה. כאן נמצא כל השאר.'),
              style: TextStyle(
                  fontSize: 15,
                  height: 1.3,
                  color: cs.onSurfaceVariant),
            ),
          ),
          for (final (route, icon, label, hint) in doors)
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  // go() so the doors below stay truthful about where
                  // the person is standing.
                  context.go(route);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 16),
                  child: Row(
                    children: [
                      Icon(icon, size: 32, color: cs.primary),
                      const SizedBox(width: 18),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(label,
                                style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                    height: 1.2)),
                            const SizedBox(height: 2),
                            Text(hint,
                                style: TextStyle(
                                    fontSize: 14,
                                    height: 1.25,
                                    color: cs.onSurfaceVariant)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          // The privacy slogan came OFF this screen (owner, 2026-08-18:
          // "זה משהו לגיטהאב לכתוב כפיצ׳ר") — feature copy lives in the
          // README; the app just behaves that way.
          // The build wears its name (owner, 2026-08-18: "we neglect the
          // versioning") — alpha testers report against THIS line.
          const SizedBox(height: 12),
          Center(
            child: Text(
              'BNS $kBnsVersion',
              style: TextStyle(fontSize: 12, color: cs.outline),
            ),
          ),
        ],
      ),
    );
  }
}
