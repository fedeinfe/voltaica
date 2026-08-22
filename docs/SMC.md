# Charger control

Voltaica has two backends. Which one a Mac uses is probed at startup and shown in Diagnostics.

## AppleSmartBatteryManager, the Apple Silicon path

`AppleSmartBatteryManagerUserClient` takes two scalar methods, both published in Apple's own
AppleSmartBatteryManager sources:

| Selector | Name | Effect |
|---|---|---|
| 0 | `kSBInflowDisable` | Ignore wall power and run off the battery while plugged in |
| 1 | `kSBChargeInhibit` | Stop the charger, keep powering the Mac from the adapter |

Opening the user client needs root, which is the daemon's whole reason to exist. The kernel clears
both flags when the connection closes, so a daemon that crashes or is stopped cannot leave a Mac
that refuses to charge.

This is the only path that works on Apple Silicon from macOS 26 onwards. The charger keys below are
simply not in the SMC key table any more: on a MacBookPro18,3 running macOS 26.5.2, `#KEY` reports
2051 keys, index enumeration returns all 2051 with no gaps, and `CH0B`, `CH0C`, `CH0I`, `CHWA`,
`BCLM` and `ACEN` are in none of them — not through `keyInfo`, and not through a forced read at any
size from 1 to 32 bytes.

## SMC keys, the Intel path

| Key | Type | Written | Meaning |
|---|---|---|---|
| `CH0B` | ui8 | `0x00` allow, `0x02` inhibit | Charger inhibit, byte 0 |
| `CH0C` | ui8 | `0x00` allow, `0x02` inhibit | Charger inhibit, byte 1. Written together with `CH0B`; some models only honour one |
| `CH0I` | ui8 | `0x00` normal, `0x01` cut | Ignore adapter power, so the Mac runs off the battery while plugged in |
| `CHWA` | ui8 | `0x00` off, `0x01` on | The firmware's own ceiling, around 80%, enforced by the Mac with no software running |
| `ACLC` | ui8 | state value | MagSafe LED colour, only when you turn that on |
| `BCLM` / `ACEN` | ui8 | limit / enable | Intel Macs only, the pre-Apple-silicon way of setting a ceiling |

These are the keys the community documented years ago and that every charge limiter uses. Voltaica
probes each one at startup and reports what it found; a key that is absent is reported as
unsupported rather than guessed at. It never writes a key it has not read first, and it never
writes anything outside this table.

## Accepted is not the same as applied

Both backends can return success and do nothing. On a MacBookPro18,3 at 100%,
`kSBInflowDisable` is accepted, the charger's mode counter moves, and the Mac carries on drawing
1.5 A at 19.6 V from the adapter: `Amperage` stays 0, `AppleRawCurrentCapacity` does not budge over
70 seconds and `pmset -g batt` still says AC Power.

So the daemon does not trust either call. It watches what happens:

* asked to cut the adapter and the battery is not supplying 15 seconds later → the control is
  marked ignored, the adapter is restored and the run-down button disappears;
* asked to stop a charge that was genuinely running and the current stops → the control is marked
  confirmed.

Both verdicts appear in Diagnostics and in `voltaicactl selftest`. The adapter cut is retried on
the next plug-in and again once the pack has dropped five points, in case a full battery was the
reason it was refused.

## Reading

Telemetry comes from the `AppleSmartBattery` IORegistry node, not from the SMC: `CurrentCapacity`,
`AppleRawCurrentCapacity`, `AppleRawMaxCapacity`, `NominalChargeCapacity`, `DesignCapacity`,
`CycleCount`, `Temperature`, `AdapterDetails`, `ChargerData`, `PowerTelemetryData`,
`BatteryData.CellVoltage` and the lifetime counters. No privileges needed and no ambiguity.

The SMC is read for the things IORegistry does not expose, and for the Diagnostics tab.

## The charge percentage

`CurrentCapacity` on Apple Silicon is the gauge's calibrated state of charge and the number macOS
shows. `AppleRawCurrentCapacity / AppleRawMaxCapacity` is the raw ratio, and on a worn pack it
reads lower — 4658/4806 is 96.9% on a battery macOS calls 100%. The charge limit is compared
against `CurrentCapacity`, because that is the only figure the user ever sees; the raw ratio is
shown as a separate hardware readout.

## The endianness trap

Multi-byte integer keys are not consistently ordered. On the same M-series Mac:

* `B0AV` reads `64 31`, which is 12644 mV little-endian and matches IORegistry's `Voltage` of 12645;
* `B0RM` reads `12 56`, which is 4694 mAh big-endian and matches `AppleRawCurrentCapacity` of 4694.

So Voltaica does not pretend to know: `decodeNumber` takes the byte order as an argument, and the
diagnostics view shows both interpretations when they differ. Nothing in the UI depends on it —
the control keys are single bytes, temperature is a `flt `, and everything else comes from
IORegistry.

## The ABI

`IOConnectCallStructMethod(connection, 2 /* kSMCHandleYPCEvent */, …)` with an 80-byte
`SMCParamStruct` in and out. Selectors: 5 read, 6 write, 8 key-from-index, 9 key-info. Swift packs
nested structs by size where C packs by stride, so the struct carries an explicit two-byte pad; a
unit test asserts `MemoryLayout<SMCParamStruct>.stride == 80` because getting this wrong means
reading the wrong fields rather than failing.
