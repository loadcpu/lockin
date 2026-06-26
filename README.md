# Lock In

Lock In is a strict macOS app blocker.

It blocks apps and websites during a timed focus session.

Free. Local-first. No account. No subscription. No telemetry.

## Install

Download `LockIn.dmg` from the latest release, open it, and drag `Lock In.app` into `/Applications`.

Requires macOS 13 or later.

## Build

```sh
./build.sh
```

## Apple Developer Release

Ship this as a direct download signed with `Developer ID Application` and notarized by Apple. It is not a good Mac App Store candidate because it edits `/etc/hosts`, uses `pfctl`, installs a LaunchAgent, and automates other apps.

1. Pick your permanent bundle ID, for example `com.yourdomain.lockin`.
2. Confirm your `Developer ID Application` certificate is present in Keychain Access.
3. Export your signing settings:

```sh
export LOCKIN_BUNDLE_ID="com.yourdomain.lockin"
export LOCKIN_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
```

4. Build a signed app:

```sh
./build.sh
```

5. Verify the signed app bundle locally:

```sh
./verify_release.sh
```

6. Store notarization credentials once:

```sh
xcrun notarytool store-credentials "lockin-notary" \
  --apple-id "you@example.com" \
  --team-id "TEAMID" \
  --password "app-specific-password"
```

7. Publish a notarized release:

```sh
export LOCKIN_NOTARY_PROFILE="lockin-notary"
./release.sh 1.0.0 100
```

`LockIn.entitlements` enables Apple Events under hardened runtime, which this app needs to talk to browsers.

`release.sh` now targets DMG-first distribution and `verify_release.sh` can be rerun against the built app or DMG to confirm codesigning, Gatekeeper assessment, and stapling status.

## Launch Audit

See [docs/launch-audit.md](docs/launch-audit.md) for the current repository cleanup notes, DMG distribution guidance, and the native macOS architecture review against OpenAI's guidance.

## License

MIT
