# Changelog

All notable changes to Voltaica. Format follows [Keep a Changelog](https://keepachangelog.com);
versions follow [semver](https://semver.org).

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
