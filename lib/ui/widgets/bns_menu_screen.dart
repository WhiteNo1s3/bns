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

    // Where each door leads, in the person's words. Guided mode (level 4)
    // hides managing — the inspector builds the day, and a menu must not
    // offer rooms that will only say "not for you" inside.
    final doors = <(String route, IconData icon, String label, String hint)>[
      (
        '/',
        Icons.today,
        L.t('Today', 'היום'),
        L.t('The day, its steps, the diary', 'היום, הצעדים שלו, היומן')
      ),
      (
        '/capture',
        Icons.mic,
        L.t('Keep this', 'לשמור את זה'),
        L.t('Say or write a thought — it stays', 'להגיד או לכתוב מחשבה — זה נשאר')
      ),
      (
        '/memories',
        Icons.menu_book,
        L.t('Your memories', 'הזיכרונות שלך'),
        L.t('Everything you kept', 'כל מה ששמרת')
      ),
      (
        '/calendar',
        Icons.calendar_month,
        L.t('Calendar', 'לוח שנה'),
        L.t('Appointments and days ahead', 'תורים וימים שמתקרבים')
      ),
      (
        '/day',
        Icons.auto_stories,
        L.t('Today\'s words', 'מילות היום'),
        L.t('Everything said and done today', 'כל מה שנאמר ונעשה היום')
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
          const SizedBox(height: 12),
          Center(
            child: Text(
              L.t('Everything stays on your devices.\nPrivate • No cloud • Yours',
                  'הכול נשאר במכשירים שלך.\nפרטי • בלי ענן • שלך'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
