# Architecture

Four binaries, one shared library, no framework, no `.xcodeproj`.

```
Voltaica.app
├─ Contents/MacOS/Voltaica            SwiftUI menu bar app (unprivileged)
├─ Contents/MacOS/VoltaicaHelper      launchd daemon, runs as root
├─ Contents/MacOS/voltaicactl         CLI, talks to the daemon (or the SMC when root)
└─ Contents/Library/LaunchDaemons/…   the daemon's plist, registered with SMAppService
```

## Why a daemon

Charge control is a handful of SMC keys, and `AppleSMC` refuses writes from anything that is not
root. It also hides the control keys from unprivileged clients entirely: an unprivileged process
enumerating all 2051 keys on an M-series Mac sees `CH0D`, `CH0E`, `CH0H`, `CH0R` and `CH0V` but not
`CH0B`, `CH0C`, `CH0I` or `CHWA`. So the daemon owns the SMC connection, and it is the only thing
that writes.

Reads are different: temperature, voltages and the like come back fine without privileges, which is
why the app can show live telemetry even before the daemon is approved.

## The pieces

### `VoltaicaCore`

Pure, testable, no UI, no privileges assumed.

* `SMC.swift` — the `AppleSMC` user client. The 80-byte `SMCParamStruct` is the whole contract with
  the kernel; a unit test asserts its stride so a Swift repack can never silently break it.
* `PowerHardware.swift` — the key catalog and the safe operations on top of it, including
  `releaseControl()`, which hands the charger back.
* `BatteryReader.swift` — everything `AppleSmartBattery` will report, which is the authoritative
  source for anything shown as a number.
* `PolicyEngine.swift` — a pure function: `(config, snapshot, now) -> decision`. No IO, no clock of
  its own, so every rule is unit tested.
* `Configuration.swift` — the policy as one `Codable` value, with `validated()` clamping anything
  dangerous.
* `License.swift` — offline Ed25519 key verification and the free-tier clamp.
* `HelperClient.swift` / `HelperInterface.swift` — the XPC surface, JSON payloads, so the two sides
  share only this file.

### `VoltaicaHelper` (root)

One serial queue owns the SMC connection. Every three seconds: read the battery, ask the engine,
apply the answer. The keys are rewritten at least once a minute even when nothing changed, because
other software and firmware quirks can reset them.

It persists the policy to `/Library/Application Support/Voltaica/policy.json`, so the limit is held
before anyone logs in, and it watches for sleep and wake to hand the adapter back before sleeping.

Both ends of the XPC connection pin the other's code signature to the developer team, so nothing
else on the machine can drive the charger through it.

### `Voltaica` (the app)

`MenuBarExtra` with `.menuBarExtraStyle(.window)`, an `@Observable` model polled every 2.5 seconds,
and pushes to the daemon debounced at 220 ms so dragging the slider does not flood XPC. Local edits
win for 1.5 seconds so the daemon's echo cannot fight your fingers.

### `voltaicactl`

Everything the UI can do, for scripts. `selftest` proves the write path end to end. `reset` writes
the charger keys directly when run as root, which is the rescue path if the daemon is gone.

## Decisions worth knowing

**The engine never touches the clock.** `evaluate(config:snapshot:now:)` takes the time as an
argument. That is the only reason the policy is testable at all.

**Hysteresis is evaluated before the plug state.** A pack that drifts below the sailing band while
unplugged must resume charging the moment it is plugged back in, not on the next state change.

**Safety rules outrank everything.** A 5% emergency floor beats a pause, a manual discharge, and
heat protection. Heat protection has its own floor. Discharge never goes below 15% whatever the
configuration says.

**No number is invented.** Anything shown as a measurement comes from `AppleSmartBattery` or from a
single SMC key, and the Diagnostics tab shows the raw value behind it.
