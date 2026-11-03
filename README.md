# Perasma

A native macOS library and launcher for Windows programs and games. Perasma manages Wine environments and routes `.exe` and `.msi` files opened from Finder into your library.

## Early development (0.2.0)

The app is built with SwiftUI and AppKit, with system sidebars, inspectors, toolbar controls, search, settings and onboarding. App names stay prominent; an icon is shown only when a genuine image has been supplied. No monogram artwork is used.

### Library
- Sections for all apps, Games, Programs, Favorites and Recently opened (newest first)
- Search matches app names, file names and categories; sorting by name, category or last opened
- Grid and list layouts, duplicate detection when adding the same file again
- Edit any app later: name, category, environment, favorite and custom launch arguments (quotes are supported, e.g. `-name "My Profile"`)
- Running apps show a status dot and can be stopped from the card, list or inspector
- Inspector shows environment, last opened, launch arguments and a preview of the latest log output

### Environments
- Create, rename and delete environments in Settings; apps of a deleted environment move to the first remaining one instead of being orphaned
- Per-environment graphics backend (Default or experimental DXVK for D3D10/11)
- Show an environment's Windows drive in Finder, or move the drive to the Trash
- The sidebar lists environments with their app counts

### Runtime
- Download flow (below) or pick an existing Wine executable manually in Settings and clear it again
- Launch uses a per-environment `WINEPREFIX` and only applies DLL overrides for environments that opted into a graphics backend

This development build downloads its Wine runtime from the publisher through one integrated setup flow. **No Wine runtime, D3DMetal, Steam client or Windows software is bundled.** Compatibility with individual programs, Steam games and macOS 27.2 is not yet verified. This is not a replacement for a tested CrossOver release.

The library, preferences and logs are local. Libraries saved by older builds keep loading: new fields (favorites, launch arguments, sort order) fall back to sensible defaults. Wine environments keep Windows settings separate but are **not security sandboxes**. Windows apps can access files and network resources available to your account. Only run software you trust. Launch confirmation is on by default.

All onboarding choices can be changed later in Settings. Finder file associations are never changed silently. To use Perasma, choose it in Finder's Open With menu. Adding an installer does not run it until you press Open and approve the launch.

## Builds

GitHub Actions compiles and tests the source and packages a development `.app`. Artifacts expire after one day. No release is published automatically. The app is ad-hoc signed, not Developer ID signed or notarized, so macOS may warn when opening a downloaded build.

## Runtime roadmap

Per-environment graphics setup ships for DXVK; DXMT and D3D12 remain under evaluation. Apple components are not bundled; their official download and license review stay separate. An updater is not available yet, and real-hardware verification on M1 is still outstanding.

## Download setup (experimental)
Perasma downloads pinned Wine 11.18 from the WineHQ macOS package maintainer, checks SHA-256 and preserves macOS quarantine. It does not bypass Gatekeeper or accept Apple/component licenses. Wine needs Rosetta on Apple Silicon. Media playback is an optional extra: GStreamer 1.28.5 is downloaded from its publisher and checked against the pinned SHA-256, but GStreamer’s macOS installer is not signed with an Apple certificate, so macOS asks you to review it yourself before it installs for all users. Wine works without it. DXMT/D3DMetal/Steam integration is not complete. Nothing is bundled, and “all components” is not a compatibility promise. Download/install flow is not yet verified on M1.

The UI uses native SwiftUI Liquid Glass controls on macOS 26+.
