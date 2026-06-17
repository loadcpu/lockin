# Lock In

A free, open-source macOS menu bar app that blocks distracting apps and websites on a timer — with screen time tracking.

No account. No subscription. No telemetry. 2.7 MB.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/loadcpu/screen-blocker/main/install.sh | bash
```

Requires macOS 13 Ventura or later · Apple Silicon & Intel

## Build from source

```sh
git clone https://github.com/loadcpu/screen-blocker
cd screen-blocker
./install.sh
```

Requires Xcode command line tools (`xcode-select --install`).

## How it works

- **App blocking** — any app you pick gets killed the moment you open it during a session
- **Website blocking** — modifies `/etc/hosts` + `pfctl` to block at the network layer, including IP-based bypass attempts
- **Timed sessions** — timer runs in the menu bar; you can't stop early once it starts
- **Screen time stats** — tracks active app usage and shows daily/weekly breakdowns

On first launch, Lock In asks for your admin password once to install a small privileged helper at `/usr/local/bin/lockin-hosts`. That helper is the only thing that runs as root — the app itself doesn't.

## License

MIT
