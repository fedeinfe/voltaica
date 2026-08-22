# Security

Voltaica installs a `launchd` daemon that runs as root and writes to the SMC. That is a serious
thing to put on someone's Mac, so here is what it does and does not do.

## The attack surface

* One Mach service, `com.federicoinfelici.Voltaica.Helper`, reachable only by processes whose code
  signature matches the developer team **and** one of two bundle identifiers.
* One XPC protocol, six methods, JSON payloads decoded into a `Codable` struct that clamps every
  value it accepts.
* No network access of any kind. No shell invocation. No file writes outside
  `/Library/Application Support/Voltaica/`.
* Writes are restricted to the keys listed in [docs/SMC.md](docs/SMC.md); the key catalog is a
  compile-time constant, never a value from a client.

## Reporting a vulnerability

Email **fede.infe1@gmail.com** with `voltaica security` in the subject. Please do not open a public
issue for anything that would let a local process drive another user's charger or escalate through
the daemon. Expect a reply within 72 hours.

If you are looking for somewhere to start: the XPC client requirement in `HelperInterface.swift`,
the configuration clamp in `Configuration.validated()`, and the license verifier in `License.swift`
are the three places where a bug would matter most.

## Supported versions

The latest release. Security fixes are not backported.
