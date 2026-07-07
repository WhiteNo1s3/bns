# BNS Account Server — server-first sync (0.12a pivot)

Decision (Ben, 2026-07-06): **enter the market with a real backend.** LAN
Wi-Fi pairing is too much stress and ceremony for people with Alzheimer's/TBI;
the main road is now an account on a BNS server. The `.bns` file stays as the
import/export travel file. The clients (PC primary, Android, iOS, macOS,
Linux) all speak to the same tiny server.

## Why this shape
- **They forget, they are not careful.** A user can kill the app mid-anything;
  therefore the truth also lives on the server, and the client's own store is
  already crash-proof (atomic per-change writes). Data exists in two safe
  places without the user doing a single thing.
- **We don't pack.** Data lives UNPACKED on the server: `data.json` plus each
  voice note as its own file. Zip work happens only for `.bns` export/import.
  Syncs move only what's missing (audio is content-addressed by name), so a
  normal sync is one small JSON — it loads in a second, the user won't notice.

## The server (`server/bns-server.mjs`)
One file. Zero npm dependencies. Node 18+. Nothing to install beyond Node
itself, nothing to break.

- **Exactly 3 network commands** — `POST /v1/hello`, `/v1/pull`, `/v1/push`.
  Everything else, any method, any path: 404. No signup endpoint, no UI, no
  static files, no directory listing.
- **Accounts are provisioned on the box, never over the network**
  (`node bns-server.mjs adduser <name>` → prints the bearer token exactly
  once; only its SHA-256 is stored). Fits the business flow: payment agreed
  first, then Ben creates the account.
- **Not payload-exploitable**: constant-time token compare; per-IP lockout
  after repeated auth failures (429); streaming body caps (200MB request,
  20MB data, 25MB per voice note); audio filenames must match a strict
  whitelist — path traversal is structurally impossible; data must be a BNS
  snapshot shape or it's refused; JSON only; no eval/exec/shell anywhere.
- **Never root**: refuses to start as root (unless `--allow-root` for odd
  containers). Run it as a plain user under systemd.
- **Dumb on purpose**: the server stores and validates, nothing more. ALL
  merge logic runs on clients (pull → merge locally → push). Last write wins
  per push; a per-user lock rejects concurrent pushes (409).
- **TLS**: either terminate SSL at the nginx/apache Ben already manages
  (recommended — `proxy_pass http://127.0.0.1:8787;`) or serve TLS directly
  with `--cert/--key`.
- Ctrl+C shuts it down cleanly, as requested.

### Run it
```bash
node bns-server.mjs adduser ben            # once per customer; token shown once
node bns-server.mjs serve --port 8787 --data-dir /home/bns/data
# behind nginx with the SSL cert Ben already provisions per site
```

### Storage layout (per user, unpacked)
```
data/users/<name>/data.json    # the whole snapshot, atomic tmp+rename writes
data/users/<name>/audio/*.m4a  # voice notes, one file each, immutable by name
data/users/<name>/meta.json    # revision counter + updatedAt
```

## The client (`lib/data/sync/server_sync_service.dart`)
- Settings gain `serverUrl` + `serverToken` (Sync screen → "Your BNS account"
  → Set up: paste address + access code once).
- One sync = hello (auth + server's audio list) → pull (snapshot + audio we
  lack) → merge locally (same last-write-wins as .bns import) → push (full
  merged snapshot + audio the server lacks).
- **The token never leaves the device**: stripped from every .bns export and
  LAN payload (`BnsExporter`), preserved through merges/replaces
  (`IsarService.mergeData`/`replaceAllData`).
- Friendly failure copy always ends in the truth: "Nothing was lost" — the
  local store is the first-class citizen and syncs are additive.

## Verification (all green 2026-07-06)
- `server/test-server.mjs` — 23 checks: happy path, auth surface, traversal
  attempts (`../../`, backslash, wrong extension), garbage bodies, non-snapshot
  data, lockout, revision bookkeeping, nothing-escapes-the-user-dir.
- `tool/server_protocol_check.dart` — the Dart client contract against a LIVE
  Node server: hello/pull/push round trip, byte-identical audio, emoji-safe
  JSON, have-list dedupe, bad-token refusal.

## Deployment (decided 2026-07-06): Ubuntu VPS, Germany, 100GB, unlimited bandwidth
Everything needed is in `server/deploy/`:
- `setup-ubuntu.sh` — one `sudo bash` run on the fresh VPS: installs Node,
  creates the unprivileged `bns` system user, `/opt/bns/data`, installs and
  starts the service. Idempotent.
- `bns-sync.service` — hardened systemd unit: non-root, `ProtectSystem=strict`
  (writable ONLY in its data dir), private /tmp, no privilege escalation,
  syscall filtering, 512MB memory ceiling, auto-restart. Binds `127.0.0.1`
  so only nginx can reach it.
- `nginx-bns.conf` — reverse proxy with the certbot/SSL flow Ben already runs
  for customer sites; only `/v1/` is forwarded, everything else 404s at the
  proxy too.
- **Disk safety on the fixed 100GB**: `--quota-mb 2048` in the unit — no
  account can exceed 2GB (413 with a friendly message; the client's rolling
  retention prunes and the next sync fits). Typical accounts run a few MB
  (14-day retention, ~200KB per voice note), so realistic capacity is
  thousands of accounts; worst-case guaranteed floor is ~45. `node
  bns-server.mjs stats` shows per-account usage at any time.
- Germany/EU hosting is also the right privacy story (GDPR-friendly posture:
  data minimal, no content logging, tokens stored hashed, deletion =
  `removeuser` + removing the folder).
- Business flow unchanged: payment agreed → `adduser` on the box → hand the
  customer the domain + token → the app does the rest.
- LAN sync remains in the app as a fallback (demoted in UI, edge-case risk
  accepted at this stage); .bns import/export remains for USB/AirDrop/doctor
  handoffs. Growth path if ever outgrown: AWS pay-per-action.

This document is the source of truth for the sync server. Update it when the
protocol changes.
