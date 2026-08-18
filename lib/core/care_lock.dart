/// THE CAREGIVER'S KEY — a password on the care arrangement itself.
///
/// Owner decision, 2026-08-15, after the argument was made both ways:
/// "level 3 and 4 are to the mercy of the caregiver… they cannot handle
/// day routines and they have the app to help them pass the day WITHOUT
/// the caregiver to sit on their head."
///
/// The point of the lock is independence, not control: when the app can
/// be trusted to hold the structure, the caregiver can leave the room.
/// Without the lock, one confused tap dissolves the arrangement — and
/// the alternative to the app holding it is the caregiver hovering,
/// which is the thing everyone is trying to escape.
///
/// (This supersedes the earlier "turning it off is always one tap" for
/// devices where a caregiver deliberately set a key. Enabling still
/// happens together, in the open, with the typed confirmation.)
///
/// Mechanics, kept honest:
///   - Only a SALTED HASH is ever stored — the password itself exists
///     nowhere, travels nowhere, and cannot be read out of a .bns.
///   - The copy never shames: a wrong password is "this door opens with
///     the caregiver's password", never an accusation.
library;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';

import 'package:bns/core/i18n/l.dart';
import 'package:bns/data/local/isar_service.dart';
import 'package:bns/ui/snack.dart';

/// THE CONTAINMENT STATE — one truth the whole app can ask synchronously.
///
/// A level-4 tester walked out of the list through every side door
/// (2026-08-16 report: the menu, the bottom doors, keyboard shortcuts,
/// the caregiver screen itself). Scattered `if (_guided)` checks each
/// screen remembered on its own is how those doors were left open — so
/// the state lives HERE, fed by main on every settings change, and the
/// router, the app bar, the keybinds and the screens all ask the same
/// object.
class CareState {
  CareState._();

  /// Live guided-mode flag (level 4). Fed by main at startup and on every
  /// persisted change; readable synchronously anywhere (router redirects
  /// cannot await).
  static final ValueNotifier<bool> guided = ValueNotifier<bool>(false);

  /// Live helper-hat flag: this copy belongs to the person who HELPS.
  /// The phone doors ask it — an inspector at phone width lost the
  /// routines room entirely (caregiver report, 2026-08-16).
  static final ValueNotifier<bool> caregiver = ValueNotifier<bool>(false);

  static DateTime? _unlockedUntil;

  /// The caregiver opened their door moments ago — routes that belong to
  /// them (routines building, settings) stay open for a short window, so
  /// one password covers one sitting, not one tap.
  static bool get caregiverUnlocked =>
      _unlockedUntil != null && DateTime.now().isBefore(_unlockedUntil!);

  static void noteUnlocked() =>
      _unlockedUntil = DateTime.now().add(const Duration(minutes: 5));

  static void relock() => _unlockedUntil = null;

  /// The door-frame rule, in one place the router asks: where may this
  /// route go? null = pass, a path = go there instead.
  ///
  /// A HELPER'S DEVICE IS NEVER THE CONTAINED ONE (owner, 2026-08-17:
  /// "the caregiver becomes level 4 user — this is not acceptable").
  /// Containment is the shape of the PERSON's guided day; the inspector's
  /// rooms are their work. Whatever a contaminated store still claims,
  /// the helper walks free — and the person's cage never opens from here.
  static String? containmentRedirect(String path) {
    if (caregiver.value) return null;
    if (!guided.value) return null;
    if (caregiverUnlocked) return null;
    const open = {'/', '/capture'};
    return open.contains(path) ? null : '/';
  }
}

/// 'salt:hash' for [password]. A fresh random salt per set.
String makeCareLockHash(String password, {String? salt}) {
  final s = salt ??
      base64UrlEncode(
          List<int>.generate(12, (_) => Random.secure().nextInt(256)));
  final h = sha256.convert(utf8.encode('$s:${password.trim()}')).toString();
  return '$s:$h';
}

/// True when [password] opens [stored]. An empty [stored] means no lock
/// was ever set — that door is simply open (every pre-lock device).
bool verifyCareLock(String stored, String password) {
  final t = stored.trim();
  if (t.isEmpty) return true;
  final i = t.indexOf(':');
  if (i <= 0) return false;
  final salt = t.substring(0, i);
  return makeCareLockHash(password, salt: salt) == t;
}

/// True when this device's care level is guarded by a caregiver key.
Future<bool> careLockIsSet() async =>
    (await IsarService.getSettings()).careLockHash.trim().isNotEmpty;

/// Ask for the caregiver's password. True = opened (or no lock exists).
///
/// The person seeing this dialog may be at level 3–4: the words stay
/// warm, the day goes on, and nothing about a wrong try is held anywhere.
Future<bool> showCareUnlockDialog(
  BuildContext context, {
  bool offerSetupIfMissing = false,
}) async {
  final settings = await IsarService.getSettings();
  final stored = settings.careLockHash.trim();
  if (stored.isEmpty) {
    // A guided device with no key yet must not swing open (level-4 tester,
    // 2026-08-16: "no caregiver lock... I cannot lock it myself") — the
    // first caregiver through this door SETS the key, right here.
    if (!offerSetupIfMissing) return true;
    if (!context.mounted) return false;
    final hash = await showCareLockSetupDialog(context);
    if (hash == null) return false;
    await IsarService.updateSettings(
        (await IsarService.getSettings()).copyWith(careLockHash: hash));
    CareState.noteUnlocked();
    return true;
  }
  if (!context.mounted) return false;

  final ctrl = TextEditingController();
  final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(L.t('The caregiver\'s door', 'הדלת של המלווה')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                L.t(
                    'This part is held by the caregiver, so the day can '
                        'keep working on its own. Their password opens it.',
                    'החלק הזה שמור אצל המלווה, כדי שהיום ימשיך לעבוד '
                        'בעצמו. הסיסמה שלו פותחת אותו.'),
                style: const TextStyle(fontSize: 15, height: 1.35),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: ctrl,
                obscureText: true,
                autofocus: true,
                onSubmitted: (_) => Navigator.pop(ctx, true),
                decoration: InputDecoration(
                  labelText: L.t('Caregiver password', 'סיסמת המלווה'),
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(L.t('Not now', 'לא עכשיו'))),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(L.t('Open', 'לפתוח'))),
          ],
        ),
      ) ??
      false;

  final opened = ok && verifyCareLock(stored, ctrl.text);
  if (opened) CareState.noteUnlocked();
  ctrl.dispose();
  if (ok && !opened && context.mounted) {
    BnsSnack.show(context, SnackBar(
      content: Text(L.t(
          'That door stays with the caregiver. All is well — your day '
              'continues as usual. 💚',
          'הדלת הזאת נשארת אצל המלווה. הכול בסדר — היום שלך ממשיך '
              'כרגיל. 💚')),
    ));
  }
  return opened;
}

/// Ask the caregiver to CHOOSE the password when raising to level 3–4.
/// Returns the hash to store, or null on cancel (nothing changes then).
Future<String?> showCareLockSetupDialog(BuildContext context) async {
  final p1 = TextEditingController();
  final p2 = TextEditingController();
  String? error;

  final hash = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDlg) => AlertDialog(
        title: Text(
            L.t('A key for the caregiver', 'מפתח למלווה')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              L.t(
                  'This level is set up together. The password stays with '
                      'the caregiver: changing the care level later opens '
                      'with it, so one confused tap cannot undo what you '
                      'built here. Keep it somewhere safe.',
                  'את הרמה הזאת מגדירים ביחד. הסיסמה נשארת אצל המלווה: '
                      'שינוי רמת הליווי בהמשך נפתח איתה, כך שלחיצה אחת '
                      'מבולבלת לא תפרק את מה שבניתם כאן. שמרו אותה במקום '
                      'בטוח.'),
              style: const TextStyle(fontSize: 14.5, height: 1.35),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: p1,
              obscureText: true,
              autofocus: true,
              decoration: InputDecoration(
                labelText: L.t('Choose a password (4+ characters)',
                    'בחרו סיסמה (4+ תווים)'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: p2,
              obscureText: true,
              decoration: InputDecoration(
                labelText: L.t('Once more', 'עוד פעם'),
                border: const OutlineInputBorder(),
                errorText: error,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(L.t('Cancel', 'ביטול'))),
          FilledButton(
            onPressed: () {
              final a = p1.text.trim(), b = p2.text.trim();
              if (a.length < 4) {
                setDlg(() => error =
                    L.t('At least 4 characters', 'לפחות 4 תווים'));
                return;
              }
              if (a != b) {
                setDlg(() => error = L.t('The two don\'t match — try again',
                    'לא יצא אותו דבר — עוד ניסיון'));
                return;
              }
              Navigator.pop(ctx, makeCareLockHash(a));
            },
            child: Text(L.t('Set the key', 'לקבוע את המפתח')),
          ),
        ],
      ),
    ),
  );
  p1.dispose();
  p2.dispose();
  return hash;
}
