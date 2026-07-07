# Cloud/VPS pivot — CANCELLED prototype (owner decision, 2026-07-06)

**Status: cancelled by Ben. Reference only. Nothing in this folder is code,
nothing here is imported by `lib/`, and therefore nothing here can ever end up
inside a build.** That is the containment model: not comments (`//`) that
someone with source access could un-comment, but *absence* — released APK/exe
binaries are AOT-compiled and obfuscated, and this feature simply is not in
them. There is nothing to reverse-engineer back on.

## What the idea was (from the Grok draft wave of 2026-07-06)
A Hostinger Ubuntu VPS running Node.js/Express with user accounts (JWT,
email/magic-link), per-user snapshot storage (`POST /sync/upload`,
`GET /sync/latest`, 5 GB/user cap with auto-pruning), "last seen" tracking and
push nudges. Motivation: users with memory problems forget to sync; data
should "just be there" when they pick up any device. The full Grok draft
lives in the read-only idea inbox under `server/`.

## What actually got built (0.12a, same day) — and then pulled back out
A session on 2026-07-06 implemented a leaner version into this repo before
the cancellation: a tiny zero-dependency Node server (`server/bns-server.mjs`,
3 endpoints, CLI-provisioned bearer tokens, dumb-store/smart-client) plus a
Dart client (`ServerSyncService`) wired into the Sync screen, with LAN
"demoted" to fallback. All of it now lives HERE, fenced off:
- `server_sync_service.dart.disabled` — the Dart client (was `lib/data/sync/`)
- `server/` — the Node server + deploy scripts (was repo root; also removed
  from `dist\` so it can never ship by accident)
- `server-sync.md` — its documentation (was `docs/`)
- `settings_server_test.dart.disabled`, `server_protocol_check.dart.disabled`
The `serverUrl`/`serverToken` fields remain in the Settings model as inert
compatibility fields (always null unless a future revival sets them; the
exporter keeps stripping `serverToken` from every .bns defensively). No code
path in `lib/` reads them for network purposes anymore.

## Why it was cancelled
- **It breaks the law of the project**: privacy absolute, zero network calls
  except explicit LAN between the user's own devices. A server that receives
  every diary entry, vent, and voice note — from *this* audience — is the
  exact standing exploit target the no-server law exists to prevent.
- A running service = maintenance, uptime duty, breach liability, cost creep;
  "server is annoying to handle" (Ben, 2026-07-05).
- Accounts/e-mail flows add friction for the exact users who can least afford
  friction.
- The actual problem ("data is there when they come back") is already solved
  locally: every change is written instantly and atomically; the silent
  lifecycle image keeps a current `.bns` ready; LAN auto-sync moves it between
  paired devices; the web satellite covers no-install access.

## If this is ever revived, the bar is (all of these, non-negotiable)
1. **Zero-knowledge only**: the server stores end-to-end-encrypted blobs and
   can never read a byte of user data (keys never leave user devices).
2. Encrypted `.bns` as the wire and storage format — reusing the packer
   registry and integrity seal, wrapped in client-side encryption.
3. Optional, off by default, works-forever-without-it.
4. No accounts with personal data; pairing-code-style enrollment.
5. A separate owner decision recorded in AGENTS.md — this README is not
   permission.

## Rules for this folder
- `prototypes/` must never be imported from `lib/` (build scripts don't touch
  it; `flutter build` cannot see it).
- Ideas parked here are documentation, not dormant code.
