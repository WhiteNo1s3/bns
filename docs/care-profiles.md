# Care profiles — one seat, many people, zero misfires

Owner, 2026-08-17: "we need profiling system for the caregiver, it must
be so straight and sharp flawless diamond... we offer each profile its
own care from caregiver and what knowledge the patient request
assistance or sharing... they should have in their menu option to
choose from dropdown the profile, it will host many bns files and we
keep the loop perfect."

Caregiver report (REQUIRED, same day): one Care seat that follows a few
instances — a nurse with a ward, a parent with two children, L2+L3+L4
side by side. Until this shipped, "multi-profile" meant cloning app
bundles: two Care apps, two stores, one port pair — two Level-4 agents
for one Level-4 person. That is not a product.

**2026-08-17 ~06:50:** the switcher (One Care / few people — sit the right person) is still REQUIRED and not shipped. After 49281ac the L2 Care inspector shows an אנשים dropdown sitting on רמה 2. Early profile chrome, not a switcher. Still one Care / one trusted[] / one list. Multiprofile stays REQUIRED until one seat can follow a few people without a cloned app. Do not claim the dropdown is the switcher. Not L4. Not הגדרות.

## The law

- **A profile is a person.** Each one is its OWN complete BNS home:
  `<home>/profiles/<id>/` holding `bns_data.json`, `audio/`, `exports/`
  — their day, their memories, their `trusted[]`, their pairing, their
  level. The registry is `<home>/profiles/index.json`; the sitting
  (which door is open) is `<home>/profiles/sitting.txt`.
- **Wrong-profile push is impossible by STRUCTURE.** Profile A's store
  only knows A's devices. There is no code path in which B's phone can
  be addressed from A's store — the trust row IS the address book, and
  it lives inside the profile.
- **The sitting.** The dropdown in the Care home names every profile;
  choosing one swaps the ACTIVE store wholesale (flush → swap → the
  whole app repaints via dataRevision). A profile store's `settings`
  are seeded from the caregiver's own (hat ON, guided healed false, the
  caregiver's deviceId — one device, one identity), so every guard that
  asks "am I the helper?" keeps answering yes in any seat.
- **The loop stays perfect (receive first, then send — per profile).**
  The person's device is the source of what HAPPENED; the sitting
  profile is the source of what is PLANNED; ✓ stays the person's.
  Auto-sync serves the sitting profile live. For the profiles that are
  NOT open:
  - a PULL from their person gets **silence, never REVOKED** — unknown
    to the sitting store is not unpaired; the severing word is only
    valid from the store that holds the trust;
  - a PUSH from their person is decrypted with THAT profile's own key
    and kept in `profiles/<id>/inbox/`; it merges the moment their door
    opens (receive-first preserved, words never lost).
- **What each profile shows** is what that person's level sends through
  the per-level wall (see care-levels.md): level 1 — what they ASKED;
  level 2 — what they chose to share; levels 3–4 — the whole day. The
  wall runs on the person's device; the profile simply holds what
  lawfully arrived.
- **Migration is silk.** A Care store from before profiles (one person
  merged into the root store) becomes the first named door by itself at
  launch: data + trusted row move into `profiles/<id>/`, named from the
  person's trusted-row name; the root store keeps only the caregiver's
  own settings. Nothing to configure, nothing visibly changes — the
  same day is simply behind a named door now. A helper's own seed thought is not a person (captures-only must not mint an empty door named after the seat). A leftover empty door does not block adopting the real person now living on root.

## Wave 1 (this build) vs wave 2

Wave 1: registry + migration + sitting + dropdown + REVOKED-guard +
inbox. Live serving is for the sitting profile; closed profiles are
silent-but-safe and catch up on open or by their person's next round.

Wave 2 (with BNS Care, the second entry point / `main_care.dart`,
planned id `com.whiteno1se.bns.care`): live serving for EVERY profile
concurrently (answer PULLs from closed profiles straight off their
store files), per-profile ports/identity if needed, and the ward view
(all doors, one glance).

## Out of scope here, tracked in the ledger

The same-Mac discovery fix (TCP WHO knock + NSBonjourServices consent
keys) rode in with this wave from the Prototyper's hands; the L3
second-done-ask, the wrong-goal hero confirm, and Care later-today are
the next iterate per the caregiver's order.
