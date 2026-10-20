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

## Automatic Updates (Sparkle)

The app updates itself with [Sparkle](https://sparkle-project.org). `build.sh` bundles
`Sparkle.framework` and writes `SUFeedURL` and `SUPublicEDKey` into Info.plist. The feed is
`https://github.com/loadcpu/lockin/releases/latest/download/appcast.xml`, so every
release must carry an `appcast.xml` asset; `release.sh` signs the DMG and writes it.

The EdDSA private key lives in the login keychain (Sparkle's `generate_keys` stores it there).
Print the public key with:

```sh
.build/artifacts/sparkle/Sparkle/bin/generate_keys -p
```

Back it up with `generate_keys -x <file>` and keep it safe: without it, existing installs
can't verify future updates.

Release notes shown in the update dialog and on GitHub come from `LOCKIN_RELEASE_NOTES`.

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

If you also want an app zip, set:

```sh
export LOCKIN_INCLUDE_ZIP=1
```

Versioned alias files such as `LockIn-macOS-v1.dmg` are off by default to keep the
release page clean. Re-enable them only if you explicitly want duplicate alias
downloads:

```sh
export LOCKIN_INCLUDE_VERSIONED_ALIASES=1
```

## Final Checks

Re-run verification against the built app and DMG:

```sh
./verify_release.sh --require-staple ".build/Lock In.app" ".build/dist/LockIn.dmg"
```

Confirm the GitHub release exposes `LockIn.dmg` as the intended install asset.
