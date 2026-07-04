# BNS — Agent Instructions

This is a sensitive, high-empathy project for people with neurological challenges (memory loss, executive dysfunction, TBI, etc.).

## Non-negotiables
- **Never** introduce language, stats, or UI that punishes, shames, or creates pressure ("you missed", streak counters that feel bad, red X on incomplete, etc.).
- On skip or incomplete → always offer kind invitation to log why (voice preferred). Treat the log itself as a win.
- All copy must be short, warm, clear, and forgiving.
- Low cognitive load first. One primary action per screen. Generous spacing and targets.
- Privacy absolute: zero network calls except explicit LAN between user devices.
- **Sync Security**: Never open an exploit. First sync with unknown device MUST use encryption + pairing code + explicit user accept ("codes match" confirmation). Auto-sync ONLY for trusted/paired devices. Progress bars ALWAYS visible during sync (use system or relaxing palette colors from main gradient).

## Technical
- Follow the plan in `../sessions/.../plan.md` (the master plan file). Prioritize per "What to Start First": docs first, then sync polish.
- Start from the `.bns` format in `docs/bns-format.md`.
- Port good patterns from `C:\dev\PillMemorizer` (timeline %, checklist interaction, celebration prompt, date grace logic, kind messaging) — reimplement in Dart/Flutter.
- Use Riverpod + Freezed + Isar.
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
