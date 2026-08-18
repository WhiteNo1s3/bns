/// Pure timing decisions for LAN sync — no sockets, no platform, testable.
///
/// The owner's law for this wave (2026-08-09): "why are we seeking for new
/// ones and not syncing the devices — that is what important. I also want it
/// silky." Trusted devices sync by themselves, repeatedly, whenever they are
/// around and something may have changed; seeking NEW devices is a separate,
/// deliberate act.
library;

import 'package:bns/core/need_help.dart';

/// After a successful auto-sync, how long before the same device is synced
/// again merely for being on the network. Local data changes bypass this —
/// they push almost immediately via [kChangePushDebounce].
const Duration kAutoSyncCooldown = Duration(minutes: 10);

/// How long to sit on a local change before pushing it to nearby trusted
/// devices — long enough to batch a burst of edits, short enough to feel
/// like the devices simply agree with each other.
const Duration kChangePushDebounce = Duration(seconds: 4);

/// A device whose hello was heard within this window counts as "on the
/// network now" (hellos repeat every ~5s; this forgives a few lost packets).
const Duration kPeerOnlineWindow = Duration(seconds: 20);

/// Discovered peers unseen for this long are ghosts — dropped from the list
/// so "found on your Wi-Fi" never shows devices that left an hour ago.
const Duration kPeerEvictAfter = Duration(minutes: 2);

/// Should a trusted device that was just heard on the network be synced now?
bool shouldAutoSyncOnSight({
  required bool autoSyncEnabled,
  required bool trusted,
  required bool lanAllowed,
  required DateTime? lastAutoSyncAt,
  required DateTime now,
  Duration cooldown = kAutoSyncCooldown,
}) {
  if (!autoSyncEnabled || !trusted || !lanAllowed) return false;
  if (lastAutoSyncAt == null) return true;
  return now.difference(lastAutoSyncAt) >= cooldown;
}

/// A local change pushes to a trusted door without anyone opening
/// Settings. Unauthorized / LAN-off / auto-sync-off never ride this.
bool shouldPushChangeToTrusted({
  required bool autoSyncEnabled,
  required bool trusted,
  required bool lanAllowed,
}) =>
    autoSyncEnabled && trusted && lanAllowed;

/// Is a peer heard at [lastSeen] still "on the network now" at [now]?
bool peerLooksOnline(DateTime lastSeen, DateTime now,
        {Duration window = kPeerOnlineWindow}) =>
    now.difference(lastSeen) <= window;

/// THE PER-LEVEL WALL (2026-08-17). Which care window leaves toward a
/// peer — or null for the person's own device, which always gets the
/// full day. LAN sync used to ship the FULL store, vents included, to
/// every trusted device at every care level; the family-share law
/// (`familyShareLevelFor`) existed with no sync callers. Now the peer's
/// helper hat picks the window:
///   level 1 → opened asks only, level 2 → chosen family, 3–4 → full care.
FamilyShareLevel? careWindowFor({
  required bool peerIsHelper,
  required int careLevel,
  required bool fullCareMode,
}) {
  if (!peerIsHelper) return null;
  return familyShareLevelFor(careLevel, fullCareMode: fullCareMode);
}
