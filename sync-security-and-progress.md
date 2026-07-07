# BNS Sync: Security, Auto-Sync, Progress, and Low-Maintenance Design

This is one of the most amazing parts of the app. User feedback: "the whole case is amazing".

## Core Requirements
- **Zero effort sync** from PC to phone to other PC over LAN/WiFi only.
- **Exploit-free experience** — promised **only when the application is installed** (and only the application gets the .bns files as payload; no other things go through LAN).
  - The LAN protocol is strictly BNS-only.
  - **Only .bns files are ever sent or received as payload.**
  - No other data, commands, files, or arbitrary content (such as injecting a hostile file like a PDF) can go through the LAN channel.
  - Discovery uses `BNS_HELLO`.
  - Transfer uses `BNS_PULL` requests or framed `BNS_PAYLOAD` messages containing a full valid .bns.
  - Anything else is immediately rejected.
  - We do not open ports or create an exploit path for hostile files (the .bns foundation makes injection complicated).
- **Per-device LAN "allowed" option** (toggle in trusted devices list). Default: allowed. **We advise the customer to use this feature**.
- **Unlimited size** — we don't really care for size limiting. It will work like ass if the user holds 100000000 recordings and more 15000000 memories — what can one do? sync.
- **Privacy & Security first**: "we should not be opening an exploit using this sharing method. I don't want to open vault for anyone."
- **Progress always visible**: "we must show progression all the time for the user, we encourage by using proper progress bar, modern in the color of the system of course, or default option of color the relaxing color we chose in our main gradient"
- **Auto-sync to known devices**
- First sync with encryption and accept.

## How It Works (Secure by Design)
**Important**: The exploit-free promise only applies when the official BNS application is installed and running on the devices. The protocol is deliberately designed so that **only the BNS app ever produces, sends, or accepts .bns files as payload** over LAN. No other application or raw traffic (no other things) is understood or allowed.

1. **Discovery**: UDP broadcast using magic `BNS_HELLO`. Only BNS apps respond/appear. Low maintenance.
2. **New Device (First Sync)**:
   - Encryption required.
   - Pairing code (6 digits) shown on both devices.
   - Big, clear dialog: confirm codes match + explicit "accept".
   - Only then: encrypted transfer of a framed `BNS_PAYLOAD` containing a full .bns.
   - Device becomes "trusted" (LAN allowed = true by default).
3. **Trusted / Known Devices**:
   - Per-device "LAN allowed" toggle (we advise enabling).
   - Auto-sync only for lan-allowed + trusted.
   - One-tap or automatic when nearby.
   - Still uses encryption with stored shared secret.
4. **The Wire Protocol (BNS-payload only)**:
   - `BNS_PULL` — request the other side to send its current .bns.
   - `BNS_PAYLOAD` + 4-byte length + (encrypted) .bns data.
   - Receiver strictly checks the magic + ZIP header + manifest structure via importer. Anything else is rejected with no further processing.
   - This guarantees **no other things go through LAN** — only the application gets the .bns files as payload.
   - Size is unlimited (user responsibility for giant datasets).
5. **Progress**:
   - SyncProgress stream reports at every step: export, encrypt, transfer, import.
   - Always-visible LinearProgressIndicator.
   - Colors: system accent or relaxing palette (teal/sage from main gradient).
   - Encouraging messages: "Creating a full picture of your current data...", "Locking it safely...", "Everything is in sync. You're doing great."
6. **Manual Fallback**: Export/Import .bns buttons for USB/AirDrop etc. Still low maintenance.

## UI in SyncScreen
- Trusted devices list with last sync time, forget option, auto-toggle, and **LAN allowed** toggle (per device).
- We advise enabling LAN allowed. Advisory text explains the BNS-payload-only promise.
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
