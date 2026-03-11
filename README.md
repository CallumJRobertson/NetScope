# NetScope

![macOS](https://img.shields.io/badge/platform-macOS-blue)
![License](https://img.shields.io/github/license/CallumJRobertson/NetScope)
![GitHub release](https://img.shields.io/github/v/release/CallumJRobertson/NetScope?display_name=release)

NetScope is a lightweight **macOS menu bar network monitor** designed to answer one question instantly:

**What is using my internet right now?**

It shows real-time bandwidth usage, per-application traffic, connection destinations, top consumers, and integrated internet speed tests — all directly from your menu bar.

---

# Download

Download the latest version:

➡️ https://github.com/CallumJRobertson/NetScope/releases

### Install

1. Download **NetScope.dmg**
2. Open the DMG
3. Drag **NetScope.app** into **Applications**
4. Launch the app

NetScope will appear in your **menu bar**.

---

# Features

### Live Menu Bar Monitoring
- Real-time upload/download indicator (`↓ / ↑`)
- Instant visibility of current network activity

### Bandwidth Dashboard
Popover view includes:

- Total network throughput
- Live bandwidth graph (1m, 5m, 30m)
- Per-application bandwidth usage
- Application icons for quick identification
- Destination inspector (IP, port, protocol, state)
- Hostname enrichment via reverse DNS

### Top Consumers
Quickly see which apps are using the most bandwidth.

Example:

Chrome        ↓ 18 Mbps
Docker        ↓ 7 Mbps
Zoom          ↑ 3 Mbps

### Integrated Speed Tests

Run internet speed tests directly from the app.

Shows:

- Ping
- Download speed
- Upload speed
- Recent test history

### Alerts

Optional alerts when apps exceed bandwidth thresholds.

---

# Dashboard Views

NetScope includes a full dashboard with tabs:

- **Overview** — total bandwidth + live graph
- **Applications** — per-app network usage
- **Processes** — optional advanced monitoring
- **Speed Tests** — run and review tests
- **Top Consumers** — heavy network users
- **Settings**

---

# Requirements

- **macOS 14 or newer**

NetScope is designed for modern Apple Silicon and Intel Macs running recent macOS versions.

---

# Settings

Configurable options include:

- Refresh interval (1–5 seconds)
- Number of visible applications
- Include system processes
- Enable/disable advanced **Processes** tab
- Bandwidth alert thresholds
- Speed test options

---

# How It Works

NetScope collects network information using macOS system tools and APIs:

- `nettop` parsing for per-process bandwidth and connections
- `getifaddrs` fallback for total interface throughput
- Reverse DNS resolution with local caching
- Cloudflare endpoints for speed tests

All monitoring happens **locally on your device**.

---

# Known Limitations

- `nettop` output can vary slightly between macOS versions.
- Some helper processes may appear instead of their parent apps in rare cases.
- Reverse DNS hostname resolution depends on external PTR records.

---

# Development

To build NetScope locally:

1. Open `NetScope.xcodeproj`
2. Select the **NetScope** scheme
3. Build and run

Requires:

- macOS 14+
- Xcode 15+

---

# Project Structure

NetScope/
App/
NetworkMonitor/
SpeedTest/
UI/
Utilities/

docs/
ARCHITECTURE.md
RELEASE_CHECKLIST.md

---

# Documentation

- Architecture notes: `docs/ARCHITECTURE.md`
- Release checklist: `docs/RELEASE_CHECKLIST.md`
- Changelog: `CHANGELOG.md`

---

# License

MIT License  
See [LICENSE](LICENSE) for details
