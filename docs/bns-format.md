# BNS File Format Specification (.bns)

Version: 2
Status: Active
Last updated: 2026-07-05

## Credits — open technology, used as-is
.bns proudly stands on open, battle-tested technology. **We claim no ownership
of any of it** — we credit it and use it exactly as published:
- **ZIP** container format (PKWARE, public APPNOTE specification) — "the zip magic".
- **DEFLATE / GZIP** compression (RFC 1951 / RFC 1952).
- **JSON** (ECMA-404) for all structured data.
- **AES** (NIST FIPS-197) for LAN transfer encryption.
- The Dart `archive` package for ZIP/GZIP handling.

What is *ours* is the arrangement on top — the identity marker, the manifest +
data layout, the burnout/retention semantics, and the BNS-only LAN framing.
This is the same honest pattern EPUB and OpenDocument use: openly "just a ZIP",
distinctly their own format.

## Database vs travel file (architecture decision, 2026-07-05)
Ben's question: is .bns the database we operate on, or the packed form of it?
**Decision: .bns is the TRAVEL FORM of the database — the wardrobe stays open, the suitcase is packed at the border.**
- The **live database** is an open structure: `bns_data.json` (+ `audio/` folder) in app documents. Every change is written **immediately and atomically** — there is no save button, no save-on-exit dependency, nothing for the user to remember. A crash or battery death at any moment loses at most the keystroke in flight, never the day.
- The **.bns zip** is built only at the boundaries: LAN sync, manual export, and the silent lifecycle imaging below. We never "reopen the package" during normal use — zero zip work while you use the app.
- Why not operate on the zip directly: rewriting an archive per change is slow, re-compresses audio constantly, and a mid-write kill corrupts an archive — exactly wrong for users who force-kill apps and lose battery. The open store + atomic rename can't be half-written.
- **Silent lifecycle imaging** ("save before exit, seamless"): when the app goes to background or is asked to close, it refreshes ONE stable file — `exports/BNS_Latest_<device>.bns` — skipped when nothing changed, written atomically. Result: a current, shareable .bns always exists without the user ever exporting. Sync stays "one static file crossing platforms", not a million wired systems.

## Goals
- Single file that contains the **entire user datasheet**.
- Easy to backup, copy over USB/LAN/SMB/AirDrop, email to self, etc.
- Recognized by the BNS app on every platform (file association).
- Human-inspectable when renamed to .zip (transparency is a feature, not a leak).
- Supports audio attachments for quick thoughts.
- Future-proof with manifest version + schema.

## Container
- A standard ZIP file.
- Extension: `.bns` (the app registers handlers for it).
- Media type: `application/x-bns`.
- Recommended filename when exporting: `BNS_Backup_YYYY-MM-DD_HHMM.bns`

Example internal layout (format v2):
```
BNS_Backup_2026-07-05_1430.bns
├── mimetype       # FIRST entry, STORED (uncompressed): "application/x-bns"
├── manifest.json
├── data.json.gz   # GZip compressed JSON for compact size
└── audio/
    ├── cap_01f3a2b4.m4a
    └── cap_01f3a2c9.m4a
```

## Container abstraction (industry-grade evolution path)
The code never hardcodes ZIP: everything goes through the `BnsPacker`
interface (`lib/data/pack/`) and its registry (`BnsPackers`). The current
writer is `zip-v2`; readers detect the right packer from raw bytes. A future
container (zstd, custom binary, deltas) implements the interface, registers,
and the exporter/importer/LAN never change. Packers are pure byte
transformers — isolate-safe, unit-tested by contract, benchmarked
(`test/pack_benchmark_test.dart`; zip-v2 reference: pack 151ms / unpack+verify
74ms for a 5.9MB heavy dataset).

## Second container: BNS2 (`bns2-v1`, read support everywhere)
A length-prefixed binary format (idea from the 2026-07-06 inbox wave, ported
with the integrity seal the draft lacked):
```
"BNS2"                        4-byte magic — identity at offset 0
u32le manifestLen + manifest  (sealed: packer + sha256 integrity block)
u32le dataLen     + data.json.gz
u32le audioCount  + [u32le nameLen + name + u32le byteLen + bytes]×N
```
All readers (Dart packer registry, web satellite) accept it; **zip-v2 remains
the only writer** — benchmarked head-to-head on the 5.9MB heavy dataset the
two are a dead heat (bns2 85/53ms vs zip 83/54ms pack/unpack), so the
rename-to-.zip transparency keeps the writer seat. The benchmark races every
registered packer; a future format must win there WITH integrity to take over.

## Two official implementations (cross-verified)
zip-v2 is implemented twice, on purpose — a format with two independent
implementations is a format, not an accident of one codebase:
1. **Dart** — `lib/data/pack/bns_zip_packer.dart` (the app, all platforms).
2. **JavaScript** — the `BNS-CORE` block inside `satellite/bns-web.html`
   (the web satellite: a single static HTML file that opens, edits and
   re-seals .bns in the browser — no server, no install, no network).
Both write the marker at bytes 30..54, STORE already-compressed payloads,
seal with SHA-256, and verify CRCs + hashes before trusting content.
`tool/cross_check.dart` (`make` / `verify`) is the referee: each side must
read and fully verify files written by the other. Run it (plus the Node
harness that executes the satellite's core) whenever either implementation
changes.

## Integrity (the unbreakable seal, format v2+)
Every image's manifest carries:
```json
"packer": "zip-v2",
"integrity": {
  "algorithm": "sha256",
  "data": "<sha256 hex of data.json.gz bytes>",
  "audio": { "cap_xxx.m4a": "<sha256 hex>" }
}
```
Unpack verifies ZIP CRC32s AND these hashes before anything reaches the
database. A single flipped bit — corruption in transit, disk rot, tampering —
is rejected with a friendly message and nothing is imported. Legacy v1 files
(no seal) are still accepted through the structural checks. Combined with the
LAN layer (AES per trusted device, strangers refused) and atomic writes, the
chain is: encrypted transport → structural validation → cryptographic
integrity → only then the database.

## The identity marker (what makes the file special, format v2+)
The first archive entry is a file literally named `mimetype`, containing
`application/x-bns`, stored **without compression** and **first** — the same
technique EPUB uses. Because a ZIP local header is exactly 30 bytes, the
marker lands at a **fixed byte offset** in the raw file:
- bytes 30..37 → `mimetype`
- bytes 38..54 → `application/x-bns`

So a genuine .bns is recognizable by reading ~60 bytes, without unpacking —
used by the LAN validator (`BnsImporter.hasBnsMark`) and available to any
other tool. Readers MUST still verify manifest.json + data.json(.gz) exist
before trusting content.

Compatibility policy: readers accept format v1 files (no marker) as long as
manifest + data validate. Writers always produce the current version.

## manifest.json
```json
{
  "formatVersion": 2,
  "mediaType": "application/x-bns",
  "container": "zip (PKWARE APPNOTE) + deflate/gzip (RFC 1951/1952) + json",
  "exportedAt": "2026-07-05T14:30:00.000Z",
  "deviceId": "stable-uuid-of-origin-device",
  "deviceName": "Ben's Pixel",
  "appVersion": "0.1.0+1",
  "schema": "bns/v2",
  "audioCount": 2,
  "totalItems": 47,
  "dataCompressed": true,
  "dataFormat": "gzip+json"
}
```

.bns uses GZip compression on data.json.gz for compactness (our efficient database format). The app (BNS) updates the local DB and spreads the data via .bns exports/imports/sync.

## data.json.gz (top level, GZip compressed)
Full serialised state (compressed for compact .bns database format). All IDs are UUID strings.
The app updates the local DB and uses .bns to spread/deliver the data to the user.

```json
{
  "routines": [ /* array of Routine */ ],
  "events": [ /* array of CalendarEvent */ ],
  "captures": [ /* array of QuickCapture */ ],
  "completionLogs": [ /* array of CompletionLog */ ],
  "settings": { /* Settings */ }
}
```

### Routine
```ts
{
  "id": "uuid",
  "title": "Take morning meds",
  "description": "With water, check blood pressure after",
  "recurrence": {
    "type": "daily" | "weekdays" | "weekly" | "custom",
    "daysOfWeek": [1,2,3,4,5],   // 0=Sun ... 6=Sat (for weekly/custom)
    "time": "08:15"              // optional HH:mm local
  },
  "isActive": true,
  "tags": ["health", "memory"],
  "firstStepOnlyDefault": false,
  "createdAt": "2026-06-20T09:00:00.000Z",
  "updatedAt": "..."
}
```

### CalendarEvent
```ts
{
  "id": "uuid",
  "title": "Neurologist appointment",
  "date": "2026-07-15",
  "time": "14:30",
  "notes": "Bring recent MRI report",
  "isAllDay": false,
  "createdAt": "..."
}
```

### QuickCapture
```ts
{
  "id": "uuid",
  "at": "2026-07-04T10:22:00.000Z",
  "text": "Felt overwhelmed after the call, but I wrote it down anyway",
  "audioPath": "audio/cap_01f3a2b4.m4a",   // relative to zip root, or null
  "linkedRoutineId": "uuid-or-null",
  "linkedEventId": "uuid-or-null",
  "tags": ["reflection"]
}
```

### CompletionLog
```ts
{
  "id": "uuid",
  "routineId": "uuid",
  "date": "2026-07-04",           // YYYY-MM-DD (local)
  "status": "done" | "skipped",
  "reason": "Had a bad headache, recorded voice note",  // optional, encouraged on skip
  "reasonAudioPath": "audio/...", // optional
  "at": "2026-07-04T19:05:00.000Z"
}
```

### Settings
```ts
{
  "deviceName": "Ben's Phone",
  "themeMode": "system" | "light" | "dark",
  "relaxingPalette": "teal" | "lavender" | "sand" | "deep",
  "notificationsEnabled": true,
  "hapticsEnabled": true,
  "lastFullSyncAt": "2026-07-03T22:10:00.000Z"
}
```

## Audio files
- Stored under `audio/`.
- Preferred format in MVP: `.m4a` (AAC) from the `record` package (good size/quality).
- Fallback: `.wav` if needed.
- Filenames: `cap_<short-uuid>.m4a`
- On import the app copies them into its documents directory and updates paths.

## Import / Merge Rules (MVP)
1. Load manifest + validate formatVersion.
2. Read data.json.
3. For each collection, use "last updated wins" based on `updatedAt` / `at` fields (or createdAt).
4. Audio files copied in; collisions use content hash or keep both with suffix.
5. User is shown a summary: "X new routines, Y events, Z captures, 2 audio notes". Confirm before apply.
6. Full replace option also offered ("Use this backup exactly").

## Export
- Always full snapshot of the current local store (JSON snapshot store since July 2026; formerly Isar) + current audio files.
- Written atomically to temp then moved.
- User can choose filename/location via file_picker.

## Future Versions (v2+)
- Delta manifests (list of changed IDs + last sync watermark).
- Optional encryption (user passphrase) — still local only.
- Compression level hints.
- Embedded thumbnails or icons.

## Security / Privacy
- No encryption by default (user controls the file).
- All data stays on user devices.
- `.bns` never touches any server.

## Registration
- Android: intent filter for `application/octet-stream` + custom mime + file extension.
- iOS: Document types + UTType.
- Desktop: file association in platform folders (set during packaging).

This document is the source of truth. Update it when schema changes.
