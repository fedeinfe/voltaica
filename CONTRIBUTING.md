# Contributing

Bug reports and patches to the engine are very welcome. Please read this first, it is short.

## What is open to contributions

`Sources/VoltaicaCore`, `Sources/VoltaicaHelper` and `Sources/voltaicactl` are GPL-3.0-or-later and
open to patches. The app in `Sources/Voltaica` is a paid product under a source-available license;
bug reports about it are welcome, but pull requests against it can only be merged with a copyright
assignment, so please open an issue first rather than writing code nobody can take.

## Before a pull request

```bash
swift test
./Scripts/build.sh
```

Both must pass. `swift test` covers the policy engine, the configuration clamps, the SMC ABI and the
license verifier; a change to any of those needs a test that would have failed before it.

## House rules

* **Never widen the set of SMC keys that are written** without evidence from public documentation
  and a probe that proves the key exists before writing it. A wrong key on a stranger's Mac is not
  a bug to fix later.
* **The policy engine stays pure.** No clock, no IO, no logging inside `evaluate`. Take `now` as an
  argument.
* **Safety rules keep their order.** The emergency floor outranks pauses, discharge and heat
  protection. If you add a rule, say in the pull request where it sits and why.
* **Comment the why, not the what.** The code says what it does.

## Reporting a bug

Include the output of:

```bash
/Applications/Voltaica.app/Contents/MacOS/voltaicactl selftest
/Applications/Voltaica.app/Contents/MacOS/voltaicactl json
```

Redact the serial if you would rather not share it. The Mac model, the macOS version and whether the
Mac was plugged in matter more than anything else.
