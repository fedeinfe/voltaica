# FAQ

**Is this safe for my battery?**
Holding a charge below 100% is what Apple's own Optimised Charging tries to do, less precisely. The
keys Voltaica writes are the charger inhibit keys the SMC exposes for exactly this purpose. Voltaica
never changes charge current, voltage or any thermal limit.

**Can it leave my Mac unable to charge?**
The daemon hands the charger back to macOS when the policy is turned off, when it shuts down, and
when it is uninstalled, and it re-asserts state every minute while running. If something still goes
wrong, `sudo /Applications/Voltaica.app/Contents/MacOS/voltaicactl reset` puts the keys back with
nothing else running. Unplugging and replugging also clears the inhibit on most models.

**Does it void the warranty?**
No. Writing SMC keys is not a hardware modification and leaves no trace beyond the current charger
state, which resets. That said, this is unsupported by Apple and comes with no warranty of its own;
see the licenses.

**Why does macOS ask me to approve a background item?**
Because the part that writes to the charger has to run as root, and macOS makes every root
`launchd` daemon installed by an app visible and revocable. Approving it in Login Items &
Extensions is the whole install step, and you can revoke it there at any time.

**Does the limit hold when I log out or close the lid?**
Yes. The daemon runs independently of your login session and reads its policy from
`/Library/Application Support/Voltaica/policy.json`. Before sleep it restores adapter power, so a
sleeping Mac never drains itself.

**Should I use this with Optimised Battery Charging?**
Either is fine. Optimised Charging becomes redundant once you hold a limit below 80%, and macOS
simply has less to do.

**What is sailing?**
Holding a hard limit means the charger switches on and off constantly around it. Sailing lets the
charge drift a few percent below the limit before charging again, which is far kinder to the
charger and to the pack, and it is the whole reason to use a tool like this rather than the
firmware ceiling.

**80%, 60% or 50%?**
80% for a laptop that lives on a desk but travels. 60% if it never leaves the desk. Below 60% the
extra benefit is small and you lose usable runtime. 100% is fine for a week before a trip.

**Does it work on Intel Macs?**
Yes, using `BCLM`/`ACEN`, which set a firmware ceiling rather than inhibiting the charger. Sailing
and discharge are Apple silicon features; the app reports what your Mac supports.

### Why is the run-down button greyed out?

Because your Mac accepted the request to ignore wall power and then carried on drawing from the
wall anyway. Voltaica waits fifteen seconds, checks whether the battery is actually supplying the
system, and switches the feature off rather than leave you watching a percentage that never moves.
It tries again the next time you plug in, and again once the pack has dropped a few points. Unplug
and the battery drains normally — that is the only way down on those models.

### Voltaica says 100% and the gauge readout says 96.9%. Which is right?

Both. The big number is `CurrentCapacity`, the calibrated state of charge macOS itself shows, and
it is what the charge limit is compared against. The smaller one is raw capacity over raw full
capacity straight off the gas gauge, which sits lower on a worn pack. Diagnostics shows both.

**Where is the data stored?**
Policy and license in `/Library/Application Support/Voltaica/`, samples in `samples.jsonl` in the
same place, trimmed to 30 days. UI preferences in the app's own defaults. Nothing leaves your Mac:
no analytics, no network calls, and license checks are offline by design.

**I bought a license. How many Macs?**
Three. Activation is offline: the key itself carries the entitlement, so there is no server to
check in with and nothing to phone home to.

**Can I build it myself instead of paying?**
Yes, and that is deliberate. The engine is GPL, the app is source available, and a build you make
for yourself is yours. The price covers the notarised build, the Pro features in it, and the work.
