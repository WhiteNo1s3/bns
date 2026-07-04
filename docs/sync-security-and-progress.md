# BNS Sync: Security, Auto-Sync, Progress, and Low-Maintenance Design

This is one of the most amazing parts of the app. User feedback: "the whole case is amazing".

## Core Requirements
- **Zero effort sync** from PC to phone to other PC over LAN/WiFi only.
- **Privacy & Security first**: "we should not be opening an exploit using this sharing method. I don't want to open vault for anyone."
- **Progress always visible**: "we must show progression all the time for the user, we encourage by using proper progress bar, modern in the color of the system of course, or default option of color the relaxing color we chose in our main gradient"
- **Auto-sync to known devices**
- First sync with encryption and accept.

## How It Works (Secure by Design)
1. **Discovery**: UDP broadcast. Devices on same WiFi auto-appear in Sync screen. Low maintenance.
2. **New Device (First Sync)**:
   - Encryption required.
   - Pairing code (6 digits) shown on both devices.
   - Big, clear dialog: confirm codes match + explicit "accept".
   - Only then: encrypted transfer of full .bns (ZIP with data + audio).
   - Device becomes "trusted".
3. **Trusted / Known Devices**:
   - Auto-sync option (toggle).
   - One-tap or automatic when nearby.
   - Still uses encryption with stored shared secret.
4. **Progress**:
   - SyncProgress stream reports at every step: export, encrypt, transfer, import.
   - Always-visible LinearProgressIndicator.
   - Colors: system accent or relaxing palette (teal/sage from main gradient).
   - Encouraging messages: "Creating a full picture of your current data...", "Locking it safely...", "Everything is in sync. You're doing great."
5. **Manual Fallback**: Export/Import .bns buttons for USB/AirDrop etc. Still low maintenance.

## UI in SyncScreen
- Trusted devices list with last sync time, forget option, auto-toggle.
- Discovered peers: "Sync now" (trusted) or "Pair & Sync (secure)" (new).
- Prominent progress section at top when active.
- Pairing dialog: large code display, simple yes/no.
- All with generous targets, warm language, escapes.

## Implementation Notes
- LanSyncService: handles UDP, TCP, encryption (AES via encrypt package), pairing code gen, progress emission.
- TrustedDevice in Isar.
- BnsExporter / Importer for the .bns imaging.
- Progress bars and colors tied to BnsTheme (relaxing or system).
- No unauthenticated data exchange ever.

## Ideas to Build On (from docs/ideas-for-handicapped-users.md)
- Gentle "Last synced" in Today.
- "What changed?" positive summary post-sync.
- Quiet mode (no confetti/animations).
- Device friendly names.
- Visual device icons that "light up".
- Voice confirmation on complete.
- "I feel off" re-sync button.

See main plan.md for what to start first (docs first, then this polish), and full ideas list.

This makes sync safe ("no vault for anyone"), encouraging (progress + kind words), and truly low-maintenance (auto for known, one-tap, progress always shown).
