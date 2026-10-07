# Perasma

A native macOS library and launcher for Windows programs and games. Perasma manages Wine environments and routes `.exe` and `.msi` files opened from Finder into your library.

## Early development

The app is built with SwiftUI and AppKit, with system sidebars, inspectors, toolbar controls, search, settings and onboarding. App names stay prominent; an icon is shown only when a genuine image has been supplied. No monogram artwork is used.

This first development build requires an existing compatible Wine executable, selected in Settings. **No Wine runtime, D3DMetal, Steam client or Windows software is bundled.** Compatibility with individual programs, Steam games and macOS 27.2 is not yet verified. This is not a replacement for a tested CrossOver release.

The library, preferences and logs are local. Wine environments keep Windows settings separate but are **not security sandboxes**. Windows apps can access files and network resources available to your account. Only run software you trust. Launch confirmation is on by default.

All onboarding choices can be changed later in Settings. Finder file associations are never changed silently. To use Perasma, choose it in Finder's Open With menu. Adding an installer does not run it until you press Open and approve the launch.

## Builds

GitHub Actions compiles and tests the source and packages a development `.app`. Artifacts expire after one day. No release is published automatically. The app is ad-hoc signed, not Developer ID signed or notarized, so macOS may warn when opening a downloaded build.

## Runtime roadmap

A redistributable, reproducibly built Wine-compatible runtime and per-app graphics settings are under evaluation. Proprietary Apple components will not be bundled unless their current terms are verified. An updater is not available in this first development build.
