# Lock In

Lock In is a macOS menu bar app for blocking distracting apps and websites during a timed focus session.

Free. Local-first. No account. No subscription. No telemetry.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/loadcpu/screen-blocker/main/install.sh | bash
```

Requires macOS 13 Ventura or later on Apple Silicon or Intel.

## What It Does

- Blocks selected apps by terminating them if you open them during a session.
- Blocks selected websites at the system level, not just in one browser.
- Tracks daily and weekly usage with app and website breakdowns.
- Keeps the session locked until the timer expires.

## User Download Flow

This is the release path a real user should take:

1. Open the GitHub repo.
2. Copy the install command.
3. Run it in Terminal.
4. Let the script download `LockIn.zip`.
5. Confirm `Lock In.app` lands in `/Applications`.
6. Launch the app.
7. Approve the one-time admin prompt for website blocking.
8. Start a short focus session and verify blocked apps and websites actually fail.

## Build From Source

```sh
git clone https://github.com/loadcpu/screen-blocker
cd screen-blocker
./install.sh
```

Requires Xcode Command Line Tools.

## Screenshots

Add real screenshots here once the app is built on a clean machine:

- Dashboard
- Block setup flow
- Config screen
- Screen Time stats

Recommended file paths:

- `docs/images/dashboard.png`
- `docs/images/block-setup.png`
- `docs/images/config.png`
- `docs/images/stats.png`

Then embed them with standard Markdown image tags.

## How It Works

### App Blocking

Lock In watches running apps with `NSWorkspace` notifications and periodic checks. If a blocked app is detected, it is force-terminated immediately.

### Website Blocking

Website blocking has two layers:

1. Lock In writes blocked domains to `/etc/hosts`.
2. A small privileged helper resolves active IPs for those domains and installs `pfctl` rules to block direct TCP and UDP traffic, including common bypass attempts.

That helper is installed once at:

```text
/usr/local/bin/lockin-hosts
```

The app itself does not run as root.

### Browser Awareness

For browsers, Lock In uses AppleScript to inspect the active tab URL in Safari, Chrome, Arc, Brave, Edge, and Firefox. That is used for:

- better website usage tracking
- reloading tabs when a blocking session starts
- prompting for macOS Automation permission when needed

### Usage Tracking

Lock In prefers macOS Screen Time data from:

```text
~/Library/Application Support/Knowledge/knowledgeC.db
```

If that data is unavailable, it falls back to its own local activity tracker and stores usage data under:

```text
~/.lockin
```

## Permissions

Lock In may ask for:

- Accessibility or Automation-related permissions for browser interaction
- an admin password once, to install the website-blocking helper
- notification permission for session completion alerts

## What Should Be Tested End-to-End

The minimum real-user test matrix is:

1. Fresh install from the `curl` command.
2. Zip download and unzip path.
3. First launch from `/Applications/Lock In.app`.
4. Helper installation prompt.
5. App blocking during an active timer.
6. Website blocking in Safari and one Chromium browser.
7. Browser permission denial and recovery flow.
8. Session persistence across relaunch.
9. Uninstall flow.
10. Upgrade flow from one release zip to the next.

## Clean-Machine Test Flow

The most realistic way to test install and first-run behavior is:

1. Use a separate macOS user account or a spare Mac.
2. Make sure `/Applications/Lock In.app` does not exist.
3. Make sure `/usr/local/bin/lockin-hosts` and `/etc/sudoers.d/lockin` do not exist.
4. Open the GitHub repo in a browser.
5. Copy the README install command and run it in Terminal.
6. Confirm the script downloads `LockIn.zip`, installs `Lock In.app`, and opens it.
7. Start a short session with one blocked app and one blocked website.
8. Verify the admin prompt appears only when website blocking is needed.
9. Verify app blocking, website blocking, relaunch behavior, and uninstall.

If you want to repeat this on the same machine, create a fresh macOS user account. That gives you a clean `~/Library`, clean app permissions, and clean app state without needing a second Mac.

## License

MIT
