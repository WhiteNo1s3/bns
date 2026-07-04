# BNS File Format Specification (.bns)

Version: 1
Status: Draft (MVP)
Last updated: 2026-07-04

## Goals
- Single file that contains the **entire user datasheet**.
- Easy to backup, copy over USB/LAN/SMB/AirDrop, email to self, etc.
- Recognized by the BNS app on every platform (file association).
- Human-inspectable when renamed to .zip.
- Supports audio attachments for quick thoughts.
- Future-proof with manifest version + schema.

## Container
- A standard ZIP file.
- Extension: `.bns` (the app registers handlers for it).
- Recommended filename when exporting: `BNS_Backup_YYYY-MM-DD_HHMM.bns`

Example internal layout:
```
BNS_Backup_2026-07-04_1430.bns
├── manifest.json
├── data.json
└── audio/
    ├── cap_01f3a2b4.m4a
    └── cap_01f3a2c9.m4a
```

## manifest.json
```json
{
  "formatVersion": 1,
  "exportedAt": "2026-07-04T14:30:00.000Z",
  "deviceId": "uuid-v4-of-origin-device",
  "deviceName": "Ben's Pixel",
  "appVersion": "0.1.0+1",
  "schema": "bns/v1",
  "audioCount": 2,
  "totalItems": 47
}
```

## data.json (top level)
Full serialised state. All IDs are UUID strings.

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
- Always full snapshot of current Isar + current audio files.
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
