# Changelog

All notable changes to this project will be documented in this file.

## [0.1.0] - 2026-03-11

### Added
- Menu bar throughput indicator and popover.
- Live bandwidth chart with 1m/5m/30m windows.
- Application-level bandwidth aggregation and connection inspection.
- Optional advanced Processes tab for per-PID inspection.
- Top consumer tracking (download/upload) for session.
- Reverse DNS hostname enrichment for destinations.
- Cloudflare-backed speed test (ping/download/upload) with history.
- High-usage notification alerts with configurable threshold.
- Project documentation (`README`, architecture, release checklist).

### Changed
- Improved process/app mapping using PID-to-app bundle inference.
- Stabilized bandwidth values with improved sampling and smoothing.
- Default filtering now prioritizes user-facing apps over background daemons.

### Known Limitations
- `nettop` output quality can vary across macOS versions and runtime conditions.
- Some helper/networking processes may still map imperfectly to parent apps in edge cases.
