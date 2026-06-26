# Lock In Launch Audit

Last updated: 2026-06-26

Reference:
- OpenAI Codex use case, "Build for macOS" practical tips: <https://developers.openai.com/codex/use-cases/native-macos-apps#practical-tips>

## Launch goals

- Keep the repository free of stale release artifacts and signing leftovers.
- Make DMG download the primary install path for end users.
- Keep the release flow verifiable outside of "it launched on my machine."
- Check the app structure against current native macOS guidance.

## Repo hygiene status

What is now aligned:
- Release-only local artifacts are ignored, including certificate exports and generated DMGs.
- The README now describes DMG install as the only end-user install path.
- Release verification is codified in `./verify_release.sh` instead of being implicit.

What still needs human discipline:
- `DeveloperIDG2CA.cer` is present locally and should stay uncommitted.
- `.build/` remains a working directory, so local release staging will continue to appear there by design.

## Distribution alignment

Current state:
- `release.sh` builds a signed app, packages `LockIn.dmg`, optionally notarizes, and publishes GitHub release assets.
- `AppUpdateChecker` prefers DMG assets from GitHub Releases, which matches the intended download path.

Launch guidance:
- Treat `LockIn.dmg` as the primary release artifact.
- Before publishing, run `./verify_release.sh` after `./build.sh` and again after `./release.sh` if notarization is enabled.

## Architecture review against OpenAI practical tips

### 1. Keep scenes explicit

Status: Partial

Evidence:
- The app already separates dashboard, stats, and block setup into different windows in [Sources/LockIn/AppDelegate.swift](/Users/decadence/Documents/projects/apps/lockin/Sources/LockIn/AppDelegate.swift:196).
- Those windows are still created manually through `NSWindow` and `NSHostingView`.

Gap:
- The app does not yet model those surfaces as SwiftUI scene roots such as `WindowGroup`, `Settings`, or `MenuBarExtra`.
- Entry is still manual AppKit bootstrap in [Sources/LockIn/main.swift](/Users/decadence/Documents/projects/apps/lockin/Sources/LockIn/main.swift:1).

Recommendation:
- Move to a SwiftUI `@main App` entry point and keep `NSApplicationDelegateAdaptor` only for the small pieces that truly require delegate hooks.

### 2. Let system chrome do more of the work

Status: Mostly aligned

Evidence:
- The app uses standard titled, closable, miniaturizable, and resizable windows.
- The UI itself is largely SwiftUI-based, and the release flow is package-first with shell scripts.

Gap:
- Window construction, lifecycle, menus, and activation are centralized in one delegate object, which makes the app feel more AppKit-managed than scene-managed.

Recommendation:
- As part of the scene migration, move command/menu wiring and window ownership closer to SwiftUI scenes instead of a single imperative controller.

### 3. Treat AppKit as a narrow edge

Status: Partial

Evidence:
- Views such as the dashboard are implemented in SwiftUI.
- The app uses targeted AppKit bridges for window sizing and system integration.

Gap:
- AppKit is not just a narrow bridge here; it currently owns the app lifecycle, menus, and every top-level window.

Recommendation:
- Keep AppKit for helpers like activation policy, notifications, and any missing browser or launchd integration, but make SwiftUI the source of truth for window structure and app state.

### 4. Validate signing and notarization separately from local build success

Status: Aligned after this pass

Evidence:
- `release.sh` already performs signing, packaging, notarization, and stapling work.
- `./verify_release.sh` now gives a repeatable check for `plutil`, `codesign`, `spctl`, and stapler validation.

Recommendation:
- Treat a successful `swift build` or local launch as necessary but not sufficient for release readiness.

## Release checklist

1. Run `./test.sh`.
2. Run `./build.sh`.
3. Run `./verify_release.sh`.
4. Publish with `./release.sh <version> <build>`.
5. Run `./verify_release.sh .build/Lock\ In.app .build/dist/LockIn.dmg`.
6. Confirm the GitHub release contains `LockIn.dmg` as the primary asset.

## Highest-priority follow-up

The main architectural follow-up is a scene migration:
- Replace manual `NSApplication` startup with a SwiftUI `App`.
- Model dashboard, stats, and setup as explicit scenes.
- Reduce `AppDelegate` to lifecycle hooks and system integration only.

That is the biggest remaining gap between the current codebase and OpenAI's current native macOS guidance.
