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
- Full `macos/Runner/Info.plist` created with CFBundleDocumentTypes for .bns (Viewer role, Owner rank). This enables opening .bns files to deliver full data (active routines, memories, etc.) via the app.
- The happy green smiling brain icon/logo applies here too (use in Assets.xcassets/AppIcon.appiconset – generate .icns from bns_icon.png or use flutter_launcher_icons if supported).
- Build: `flutter build macos --release`. The app feels native on macOS.
- File handling: On open, use `BnsFileHandler` (desktop args work on macOS).

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

macOS is **not voided** - full cross-platform support (Flutter). .bns file type works natively (open file -> app imports full active data including memories). Icon/logo (happy green smiling brain) applies. Build feels native on macOS. No direct "home widget" like Android, but desktop app with file assoc and menu support.

## Recommended next packaging polish
- Add app icon assets (in `assets/icon/`). Must be perfect - gentle, matching relaxing palette or OS. Use flutter_launcher_icons.
- Set proper app name / bundle id in each platform.
- Add code signing configuration.
- Create a simple "Export .bns" + "Import .bns" UI that uses file_picker + the exporter.
- Android widget (gadget): Code in lib/platform/android_widget.dart. After build, long-press home -> widgets -> add BNS. Updates automatically on data change. Perfect for quick glance at routines.

For full widget support on Android, after flutter build, the home_widget package will require a basic widget layout XML in res (see package docs). Basic Dart side is ready and perfect.

All of the above keeps the app local-first and zero-server.
