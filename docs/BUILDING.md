# Building, signing, releasing

## Build

```bash
./Scripts/build.sh
```

Compiles every product, assembles `build/Voltaica.app` by hand, substitutes the version into
`Info.plist`, and signs the nested binaries before the bundle. No `.xcodeproj` is involved, which is
what makes the CI build hermetic.

Signing identity is chosen by `Scripts/pick-identity.sh`, which reads the **OU** out of each
certificate rather than matching on the common name: an Apple Development certificate's CN contains
the user id, not the team, so grepping for the team would silently pick the wrong certificate or
fall back to ad-hoc. Preference order is Developer ID Application, then Apple Development, then
`-` (ad-hoc).

```bash
VOLTAICA_TEAM=68438RG5HP ./Scripts/build.sh   # override the team
VOLTAICA_IDENTITY="Developer ID Application: …" ./Scripts/build.sh
```

## Ad-hoc builds and the daemon

An ad-hoc signed build runs, reads the battery and shows everything — but `SMAppService` will not
register its daemon, so nothing can hold a limit. That is macOS policy, not a bug: a root daemon
must be signed by a real team. For development, an Apple Development certificate is enough.

## Release

```bash
./Scripts/release.sh 1.0.0
```

1. bumps `Sources/VoltaicaCore/Version.swift`
2. runs the tests
3. builds and signs with the Developer ID certificate
4. packages `build/Voltaica-1.0.0.dmg`
5. notarises with `notarytool` and staples the ticket
6. prints the checksums for the release notes and the Homebrew cask

Notarising needs a keychain profile:

```bash
xcrun notarytool store-credentials voltaica-notary \
  --apple-id fede.infe1@gmail.com --team-id 68438RG5HP --password <app-specific-password>
```

An app-specific password comes from appleid.apple.com, not the account password.

## Licenses

License keys are Ed25519 signatures over a small JSON payload, verified offline against a public key
compiled into `License.swift`. The private half lives in `~/.voltaica/license-signing-key.b64` and
must never be committed.

```bash
swift run voltaica-license mint --email buyer@example.com --order 12345
swift run voltaica-license check <key>
```

Rotating the key means shipping a new public key and re-issuing every license, so keep the file
backed up somewhere you will still have in five years.
