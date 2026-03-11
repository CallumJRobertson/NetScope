# Release Checklist

## Pre-Release
- [ ] Confirm app version in Xcode (`MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`).
- [ ] Verify build on a clean machine/user account.
- [ ] Validate menu bar UI on light and dark mode.
- [ ] Validate with active traffic in Safari/Chrome/Zoom/Steam.
- [ ] Validate speed test run and history persistence.
- [ ] Validate alerts permission flow and alert trigger/cooldown.
- [ ] Run one full regression pass on Settings toggles.

## Quality Gate
- [ ] `xcrun swiftc -typecheck` passes.
- [ ] No obvious runtime warnings in Xcode console during 5 minute run.
- [ ] Top consumers and app list populate with non-zero traffic.
- [ ] Processes tab toggles correctly from Settings.

## Repo / GitHub
- [ ] Update `CHANGELOG.md`.
- [ ] Update `README.md` screenshots (menu + dashboard).
- [ ] Tag release (`v0.1.0` style).
- [ ] Publish release notes from changelog summary.

## Post-Release
- [ ] Track issues for app mapping misses.
- [ ] Track issues for `nettop` behavior changes on new macOS versions.
