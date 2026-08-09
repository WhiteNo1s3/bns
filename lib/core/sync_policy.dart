/// Pure timing decisions for LAN sync — no sockets, no platform, testable.
///
/// The owner's law for this wave (2026-08-09): "why are we seeking for new
/// ones and not syncing the devices — that is what important. I also want it
/// silky." Trusted devices sync by themselves, repeatedly, whenever they are
/// around and something may have changed; seeking NEW devices is a separate,
/// deliberate act.
library;

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

/// Is a peer heard at [lastSeen] still "on the network now" at [now]?
bool peerLooksOnline(DateTime lastSeen, DateTime now,
        {Duration window = kPeerOnlineWindow}) =>
    now.difference(lastSeen) <= window;
