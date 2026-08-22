# Changelog

All notable changes to Voltaica. Format follows [Keep a Changelog](https://keepachangelog.com);
versions follow [semver](https://semver.org).

## [1.0.2] — 2026-08-22

### Fixed
* **The charge limit was not being enforced at all on Apple Silicon running macOS 26.** The SMC
  charger keys every limiter uses — `CH0B`, `CH0C`, `CH0I`, `CHWA` — are gone from the key table:
  on a MacBookPro18,3 running 26.5.2, `#KEY` reports 2051 keys, enumeration returns all 2051 with
  no gaps, and none of them is a charger key. Control now goes through
  `AppleSmartBatteryManagerUserClient` (`kSBChargeInhibit`, `kSBInflowDisable`), with the SMC keys
  kept for Intel.
* **Asking for a run-down while the charge limit was switched off did nothing.** The request was
  parked behind the "limit off" early return, so the engine never looked at it. Explicit
  discharge requests are now handled before that gate, because they are a direct instruction and
  not part of the limit policy.
* **The limit acted on the wrong percentage.** It compared raw capacity over raw full capacity
  (96.9% on this Mac) while the user, and macOS, see the gauge's calibrated state of charge (100%).
  On a worn pack that is several points of drift in whatever the slider says. The limit, the ring
  and the menu bar now all use the figure macOS shows; the raw ratio stays as a hardware readout.

### Added
* Both charger controls are verified against what the hardware actually does, not against the
  return code. An adapter cut that leaves the Mac drawing from the wall after fifteen seconds is
  marked ignored, the adapter is restored and the run-down button disappears — retried on the next
  plug-in and again once the pack has dropped five points. A charge that was genuinely running and
  then stopped marks the inhibit confirmed. Both verdicts show in Diagnostics and in
  `voltaicactl selftest`.
* `voltaicactl selftest --discharge` exercises the adapter cut end to end and reports what the
  battery actually did.
* Diagnostics names which backend is in use.

### Changed
* `voltaicactl smc` asks the daemon first, since root sees keys an unprivileged process does not.
* A raw SMC dump distinguishes a key that is absent from one that answers a read but refuses
  `keyInfo`, instead of silently skipping both.

## [1.0.1] — 2026-08-22

### Fixed
* The app quit the moment the menu bar icon was clicked. The paywall presenter was attached above
  `.environment(model)` in every scene, so its `@Environment(AppModel.self)` lookup resolved against
  an environment that had no model in it and trapped as soon as the panel's body ran. The presenter
  now takes the model directly, which no modifier order can break.
* The offscreen render harness now mirrors each scene's modifier stack exactly, so this class of bug
  fails a build rather than a click.

## [1.0.0] — 2026-08-22

First release.

### Added
* Charge limit from 20% to 100%, enforced by a root `launchd` daemon so it survives logout, sleep
  and a crash of the UI.
* Sailing: the charger stays off until the charge drifts a set amount below the limit.
* Heat protection with its own floor, so a warm nearly-empty battery still charges.
* One-shot top up to 100%, and a scheduled top up by weekday and time.
* Run down to the limit by cutting adapter power, with a hard 15% floor.
* Guided calibration: charge, soak, controlled discharge, recharge, with history.
* Firmware ceiling (`CHWA`) as a fallback that works with no software running.
* Optional MagSafe LED feedback.
* Menu bar panel, dashboard with charge, temperature and power history, health screen with cell
  voltages and lifetime counters, and a diagnostics screen showing the raw SMC and IORegistry
  values behind every number.
* `voltaicactl`, including `selftest` to prove the write path and `reset` as a rescue path.
* 14-day full trial, then a free tier that keeps monitoring and the 80% ceiling.
