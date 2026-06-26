# Releasing Lock In

Lock In ships as a direct-download macOS app signed with `Developer ID Application` and notarized by Apple.

It is not a good Mac App Store candidate because it edits `/etc/hosts`, uses `pfctl`, installs a LaunchAgent, and automates other apps.

## Release Settings

Pick your permanent bundle ID, for example:

```sh
export LOCKIN_BUNDLE_ID="com.yourdomain.lockin"
export LOCKIN_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
```

Store notarization credentials once:

```sh
xcrun notarytool store-credentials "lockin-notary" \
  --apple-id "you@example.com" \
  --team-id "TEAMID" \
  --password "app-specific-password"
```

Then export the profile when publishing:

```sh
export LOCKIN_NOTARY_PROFILE="lockin-notary"
```

## Local Verification

Build the app:

```sh
./build.sh
```

Verify the signed app bundle:

```sh
./verify_release.sh
```

## Publish A Release

Create and notarize a DMG-first release:

```sh
./release.sh 1.0.0 100
```

This produces `LockIn.dmg` as the primary user install artifact.

## Final Checks

Re-run verification against the built app and DMG:

```sh
./verify_release.sh --require-staple ".build/Lock In.app" ".build/dist/LockIn.dmg"
```

Confirm the GitHub release exposes `LockIn.dmg` as the intended install asset.
