# BNS Packaging & File Associations

## .bns File Type
The canonical backup/sync format. See `docs/bns-format.md`.

## Code-side Handling
- `lib/services/file_handler.dart` — ready for launch-with-file and import.
- On desktop launch with `.bns` the path can be passed to `BnsFileHandler.handleLaunchWithFile`.

## Platform Configuration

### Android (Perfect build with .bns + Icon)
- Full `AndroidManifest.xml` is already at `android/app/src/main/AndroidManifest.xml` with:
  - .bns file association (VIEW intent for content/file with *.bns)
  - launcher
  - Proper for home_widget and notifications.
- For icon: Run `flutter pub run flutter_launcher_icons:main` after placing icon in `assets/icon/bns_icon.png` (512x512 recommended, use relaxing teal or system color).
  - Adaptive icon configured in pubspec.yaml.
- To handle .bns on launch: In `main.dart`, call `BnsFileHandler.handleLaunchWithFile` from intent (use `uni_links` or platform channel if needed for full).
- Build: `flutter build apk --release` (or aab for play, but private).

Ensure `android:launchMode="singleTop"` (already set) for file handling.

### Windows
After `flutter build windows --release`:
- The generated .exe can be set as default app for .bns via Windows "Open with".
- For professional installer use Inno Setup or MSIX with file extension registration.

Example InnoSetup snippet (future):
```
[Registry]
Root: HKCU; Subkey: "Software\Classes\.bns"; ValueType: string; ValueName: ""; ValueData: "BNSFile"; Flags: uninsdeletevalue
...
```

### macOS
Add document type in `macos/Runner/Info.plist` (see `macos/Runner/Info.plist-bns-association-snippet.plist`).

### iOS
Similar document types in `ios/Runner/Info.plist`.

## Packaging Commands

```powershell
# Full release builds
flutter build windows --release
flutter build apk --release
flutter build ios --release
flutter build macos --release

# Or use the helper
.\scripts\build.ps1
```

## Recommended next packaging polish
- Add app icon assets (in `assets/`).
- Set proper app name / bundle id in each platform.
- Add code signing configuration.
- Create a simple "Export .bns" + "Import .bns" UI that uses file_picker + the exporter.

All of the above keeps the app local-first and zero-server.
