# SMC keys

Voltaica writes four keys, and only these four.

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

## Reading

Telemetry comes from the `AppleSmartBattery` IORegistry node, not from the SMC: `CurrentCapacity`,
`AppleRawCurrentCapacity`, `AppleRawMaxCapacity`, `NominalChargeCapacity`, `DesignCapacity`,
`CycleCount`, `Temperature`, `AdapterDetails`, `ChargerData`, `PowerTelemetryData`,
`BatteryData.CellVoltage` and the lifetime counters. No privileges needed and no ambiguity.

The SMC is read for the things IORegistry does not expose, and for the Diagnostics tab.

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
