# Building Freenet

## Requirements

- macOS 13+ (Apple Silicon or Intel)
- Xcode Command Line Tools (`xcode-select --install`) providing `swiftc`, `lipo`, and macOS SDK

## Build (Universal Binary: `arm64` + `x86_64`)

```bash
cd app
./build.sh
open build/freenet.app
```

`build.sh` compiles all `app/*.swift` sources (excluding `Tests/`) for both `arm64-apple-macosx13.0` and `x86_64-apple-macosx13.0`, combines them via `lipo` into a Universal Binary at `build/freenet.app`, refreshes `CHECKSUMS.sha256`, and ad-hoc signs the bundle.

## Pure-Logic Tests

```bash
cd app
./Tests/run_tests.sh
```

Compiles and runs 88 tests directly against shipped production Swift files (`IntentMode`, `DPIArgsValidator`, `EngineConfigs` / `SingBoxConfig` / `WarpConfigOptimizer` / `WgcfConfigParser` / `SingBoxWarpConfig`, `ChecksumVerifier`, `TorReadiness`, `AppVersion`) with zero mocks.

## Bundled Binaries (`app/Resources/bin/`)

| Binary | Required for | Notes |
|--------|--------------|-------|
| `ciadpi` | Hızlı (`Hibrit Zırh` & standalone DPI) | Tracked in repo, SHA-256 verified |
| `sing-box` | Hızlı (`sing-box`) & Dengeli (`sing-box WARP`) | Tracked in repo, SHA-256 verified |
| `tor` | Maks. Gizlilik (Tor) | Optional; auto-copied from Homebrew at build time if installed (`brew install tor`) |
| `obfs4proxy`, `snowflake-client` | Optional Tor pluggable transports | Detected automatically when installed |
| `CHECKSUMS.sha256` | Binary integrity check before launch | Auto-refreshed by `build.sh` |

Verify checksums manually:

```bash
cd app/Resources/bin
shasum -a 256 -c CHECKSUMS.sha256
```

## Install Script

`install.sh` clones the repository, runs `app/build.sh`, verifies `CHECKSUMS.sha256`, and installs to `/Applications/freenet.app`. Always review scripts before running rather than blindly piping `curl | bash`.
