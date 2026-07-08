# BNS — Agent Instructions

This is a sensitive, high-empathy project for people with neurological challenges (memory loss, executive dysfunction, TBI, etc.).

## Non-negotiables
- **Never** introduce language, stats, or UI that punishes, shames, or creates pressure ("you missed", streak counters that feel bad, red X on incomplete, etc.).
- On skip or incomplete → always offer kind invitation to log why (voice preferred). Treat the log itself as a win. A **deliberate** skip is a decision, and deciding counts as a win — say so.
- **"I am mad" mode is sacred**: rage is common in this community and gets first-class, judgment-free space. While active, the app validates anger and invites venting (cursing fully allowed *by the user, in their vents*). Vents tagged `mad-vent` burn out (auto-delete) within ~2 days and the mode expires after ~24h. Never quote a vent back to the user, never surface old vents, never let mad content into summaries or the memory garden unless the user explicitly promoted it to Memorize.
- All copy must be short, warm, clear, and forgiving.
- Low cognitive load first. One primary action per screen. Generous spacing and targets.
- **The app is STATIC — owner law (2026-07-06): "the app must be static to not make nausea on people."** Vestibular sensitivity is common after TBI. No screen transitions, no sliding/flying content, no morphing theme changes — screens appear in place (`_StaticTransitionsBuilder` in `lib/ui/theme.dart`, `themeAnimationDuration: zero`). Stationary feedback (color changes, ripples) is allowed; MOTION of content is not. Confetti exists only as an opt-out celebration and dies entirely in quiet mode. Never add an animated transition "for polish".
- Privacy absolute: zero network calls except explicit LAN between the user's own paired devices. Never anyone's cloud (including ours — there isn't one), never analytics, never anything unrequested.
- **Sync Security**: Never open an exploit. First sync with unknown device MUST use encryption + pairing code + explicit user accept; auto-sync ONLY for trusted/paired devices. During pairing acceptance, show the person's **share name** (a chosen, family-facing name — not the phone's technical name) so e.g. a father instantly recognizes whose device is asking; strangers still get nothing. Progress ALWAYS visible during sync.
- **The family sharing spectrum (owner design, 2026-07-06)** — sharing is ALWAYS the person's side of the wall:
  1. Default: nothing leaves. 2. Chosen: events marked "family can know" + moments tagged `family` (voice notes ride along) enter the family file — and ONLY those. A `mad-vent` never enters a filtered share even if tagged (a rage-moment decision must not outlive the rage). 3. **FULL CARE (`fullCareMode`) — the last resort** for the severely impaired ("people with their name and number on their back in rehabilitation"): the family file carries EVERYTHING, because every fleeting thought is gold for the people easing the path ("thought about shaving but doesn't shave"; "annoyed at the elevator" → assist with elevators). Guarded ON (typed share-name confirmation, grave copy, decided together); one-tap OFF — reducing sharing must always be the easy direction. In full care the data includes vents (that's the point) but the Explorer's family view still never headlines them — available for care, never paraded.
- **NO servers, NO accounts — ever, by owner decision (July 2026; re-affirmed 2026-07-06 after the VPS mistake).** The app opens no listening ports beyond the LAN-sync sockets and embeds no HTTP servers, web builds, or remote-control pages. The 0.12a "account server" pivot was CANCELLED the same day it appeared: the entire server + client code is quarantined in `prototypes/cloud-pivot/` (reference only, never imported from `lib/`, therefore absent from every build — cancelled features must be ABSENT, not commented out). Any future revival must clear the zero-knowledge bar written in that folder's README and get a fresh owner decision.
  - **The web SATELLITE stays allowed** — `satellite/bns-web.html`, a single static HTML file that opens/edits/re-seals .bns files entirely in the browser's memory. Document tool, not a service: no listener, no network calls, no storage, no traces. Hostable as a plain static file; it is also the family/caregiver window (children's computer) onto a shared .bns.
- **Android is the current flagship platform (pivot, 2026-07-06).** "Peach perfect" on Android first — widgets (in bundles: today's mission, upcoming, quick actions), voice capture, .bns association, LAN sync; PC remains fully supported. Ship builds, not source: release binaries are AOT-compiled and obfuscated.
- **Business model (owner, 2026-07-06): premium, paid-only.** No ads, ever. No free tier. Store purchase is the only distribution. Launch price ~$1–2 (final number pending; possible scheduled price step later). No AI-API subscription costs passed to users — on-device/OS capabilities only (e.g. the platform speech recognizer for voice-note subjects).

## Technical
- Follow the plan in `../sessions/.../plan.md` (the master plan file). Prioritize per "What to Start First": docs first, then sync polish.
- Start from the `.bns` format in `docs/bns-format.md`.
- Port good patterns from `C:\dev\PillMemorizer` (timeline %, checklist interaction, celebration prompt, date grace logic, kind messaging) — reimplement in Dart/Flutter.
- Use Riverpod for state. Models are plain hand-written Dart classes (manual `toJson`/`fromJson`/`copyWith`, no codegen). Persistence is a JSON snapshot store in `lib/data/local/isar_service.dart` (historical name) — atomic file writes, whole state in memory. No database packages, no build_runner. Don't reintroduce codegen without a strong reason.
- Theme: dynamic_color first, then relaxing palette seeds defined in `lib/ui/theme.dart`. Progress and accents use relaxing colors or OS.
- Confetti and micro-celebrations are encouraged for completes, but optional "quiet mode" for low stimulation.
- See `docs/ideas-for-handicapped-users.md` for all awesome ideas (progress visibility, secure pairing, gentle summaries, voice-first, last-sync indicators, quiet mode, etc.). Add new ideas there.

## Development habits
- After any feature that touches data: verify roundtrip via export/import `.bns`.
- LAN/Sync features: test pairing (new device), auto-sync (trusted), progress on real multi-device (Windows + emulator). Ensure no unauthenticated access.
- Every new screen or flow should have a "close / no explanation needed" escape.
- Keep audio short and compressible.
- Update `docs/bns-format.md` and ideas md when schema or new features added.
- Always show progression with proper progress bars during sync/export/import. Use encouraging messages.
- Document everything in the md files.

## When user tests
- Ask specifically:
  - "Was anything confusing or too much?"
  - "Did it ever feel like it was mad at you?"
  - "Was the LAN sync effortless and safe feeling?"
  - "Voice capture easy enough?"
  - "Did you see progress clearly? Was it encouraging?"

Welcome changes that make it gentler, simpler, more secure, or better documented in md files.

**Start First**: Documentation updates to all .md files (README, AGENTS, new ideas/sync docs). Then polish the sync (progress everywhere, pairing UX, device names, summaries).
