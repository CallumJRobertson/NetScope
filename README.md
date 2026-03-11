# NetScope

NetScope is a lightweight macOS menu bar network monitor for answering one question quickly:

**What is using my internet right now?**

It provides real-time throughput, per-application usage, destination visibility, top consumers, and integrated speed tests.

## Highlights

- Menu bar live throughput indicator (`↓ / ↑`)
- Popover with:
  - total usage stats
  - live bandwidth graph (1m, 5m, 30m)
  - application bandwidth list (with icons)
  - destination inspector (IP/port/protocol/state + hostname enrichment)
  - top consumers summary
  - speed test control and recent results
- Full dashboard tabs:
  - Overview
  - Applications
  - **Processes** (optional, advanced)
  - Speed Tests
  - Top Consumers
  - Settings
- Alerts for high bandwidth usage (threshold-based)

## Tech Stack

- SwiftUI + Charts
- `nettop` parsing for per-process bandwidth and connections
- `getifaddrs` fallback for total interface throughput
- Reverse DNS resolution with cache
- Cloudflare endpoint speed tests

## Requirements

- macOS 14+
- Xcode 15+

## Run

1. Open [NetScope.xcodeproj](./NetScope.xcodeproj)
2. Select `NetScope` scheme
3. Build and run
4. NetScope appears in the menu bar

## Settings

- Refresh interval (1-5s)
- Visible app rows
- Include system processes
- Show `Processes` tab (advanced)
- Alerts on/off + threshold (Mbps)

## Known Limitations

- `nettop` output quality can vary by macOS version and runtime conditions.
- Some helper/networking processes may map imperfectly to parent apps in edge cases.
- DNS reverse lookup depends on remote PTR records and may be missing.

## Project Structure

```text
NetScope/
  App/
  NetworkMonitor/
  SpeedTest/
  UI/
  Utilities/

docs/
  ARCHITECTURE.md
  RELEASE_CHECKLIST.md
```

## Release Artifacts

- Changelog: [CHANGELOG.md](./CHANGELOG.md)
- Architecture notes: [docs/ARCHITECTURE.md](./docs/ARCHITECTURE.md)
- Release checklist: [docs/RELEASE_CHECKLIST.md](./docs/RELEASE_CHECKLIST.md)

## License

MIT - see [LICENSE](./LICENSE)
