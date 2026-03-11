# NetScope Architecture

## Data Flow

1. `NetScopeStore` starts a monitor loop.
2. `NettopSampler` runs `/usr/bin/nettop` and parses CSV snapshots.
3. Snapshots are converted to per-process deltas (bps + byte deltas).
4. Store aggregates:
   - total upload/download rates
   - app table rows
   - session totals
   - top consumers
5. UI subscribes via `@EnvironmentObject` and updates in real-time.

If `nettop` is unavailable/fails, store falls back to `InterfaceBandwidthSampler` for total interface throughput only.

## Key Components

## `App/NetScopeStore.swift`

Central orchestrator responsible for:
- monitor lifecycle
- settings persistence (`UserDefaults`)
- speed test execution and history persistence
- alert policy and cooldown handling
- reverse DNS enrichment for visible connections

## `NetworkMonitor/NettopSampler.swift`

- Launches `nettop` in CSV mode.
- Parses process headers and child connection rows.
- Tracks previous totals by PID to compute delta rates.

## `NetworkMonitor/InterfaceBandwidthSampler.swift`

- Reads interface counters with `getifaddrs`.
- Produces total RX/TX rates.
- Used as runtime fallback when `nettop` sampling fails.

## `NetworkMonitor/ReverseDNSResolver.swift`

- Async actor for reverse DNS lookups.
- Caches resolved hostnames by IP address.

## `SpeedTest/CloudflareSpeedTestService.swift`

- Measures ping using multiple requests.
- Measures download and upload throughput with fixed payloads.
- Returns Mbps and latency metrics.

## `Utilities/AlertNotifier.swift`

- Requests notification authorization lazily.
- Sends local notifications for apps crossing threshold (with cooldown).

## UI Surface

## Menu Bar Popover

- Throughput stats
- live chart
- per-app rows with expandable connection detail
- speed test controls + recent history
- top consumers summary

## Dashboard Tabs

- Overview: aggregate stats + graph
- Applications: detailed list and connection destinations
- Speed Tests: historical runs
- Top Consumers: session leaders (download/upload)
- Settings: monitoring and alert preferences

## Design Choices

- Keep sampling and parsing in actors to avoid data races.
- Keep UI simple and reactive through a single store.
- Prefer bounded history (30 min samples, 30 speed tests) for low memory overhead.

## Extension Points

- Replace `CloudflareSpeedTestService` with protocol-backed backends.
- Add persistent store for historical per-app traffic.
- Add export endpoints (JSON/CSV) for diagnostics.
