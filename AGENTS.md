# AGENTS.md

Guidance for AI coding agents working in this repository.

## What this is

Harbor is a native Swift + SwiftUI macOS GUI for Apple Container (0.2 preview). It never implements a VM, engine, or Docker API itself: every action shells out (without a shell) to the official `container` CLI. Docker / Compose support is an optional extension that talks to a Socktainer Unix socket. No external Swift package dependencies, no Electron/WebView/Node.

The repository is English-only: UI strings, error messages, docs, comments and commit messages. Do not add text in other languages.

## Commands

macOS only (AppKit, Darwin, `codesign`); it will not build on Linux. Requires Swift 6 toolchain (Command Line Tools is enough, Xcode not required).

```sh
bash scripts/build-app.sh                 # release build → ./Harbor.app (ad-hoc signed, not notarized)
HARBOR_CONFIGURATION=debug bash scripts/build-app.sh
swift build --product Harbor              # compile only
swift run HarborChecks                    # run the test suite
python3 scripts/check-native-catalog.py   # verify every catalog entry against local `container <path> --help`
python3 scripts/check-docker-adapter.py   # real Docker CLI against a fake Engine API on a temp socket
```

Env overrides: `HARBOR_BUILD_DIR` (build cache), `HARBOR_CONTAINER`, `HARBOR_K8S_PLUGIN` (standalone k8s plugin binary), `HARBOR_DOCKER`. None of the checks pull images, create containers, or touch the default Docker context; keep it that way.

### Tests are not XCTest

`Tests/HarborCoreTests/HarborCoreTests.swift` is compiled as the `HarborChecks` **executable target** (see `Package.swift`), so `swift test` does nothing useful. The file defines its own `XCTAssert*` shims that call `precondition`/`fatalError`, and a `@main` that calls each test method explicitly. When adding a test:
- add the method to `HarborCoreTests`,
- call it from `HarborChecks.main()` (otherwise it never runs),
- update the count/summary in the final `PASS:` line.

There is no filter flag; to run a single test, temporarily comment out the other calls in `main()`.

## Architecture

```
SwiftUI (Sources/Harbor) → HarborCore → Foundation.Process → container CLI → Apple Container services
optional Compose → Docker CLI --host unix://<socktainer socket> → Socktainer → Apple Container
```

**`HarborCore`** (library, UI-free, everything testable lives here):
- `Command.swift`: `Command` (executable + argv array, never a shell string), `Runner.run/checked` (runs off-main via `Task.detached`, writes stdout/stderr to separate temp files to avoid pipe deadlock, polls for timeout/cancellation then SIGTERM→SIGKILL, rejects output over 2 MB), and `RuntimeConfig` (tool paths + socket; builds `nativeCommand`, `dockerCommand`, `composeCommand`).
- `Native.swift`: `NativeParser` (parses `container ... --format json`, including the legacy shape where `status` is a string instead of an object; throws on unknown shapes rather than returning empty lists), `ArgumentTokenizer` (quote/escape splitting only, no expansion), `NativeHelp.matches` (confirms `--help` output belongs to the requested subcommand, not the root fallback; k8s plugin prints `USAGE: k8s ...`), and `NativeOperation.all`, the catalog of all 67 leaf CLI commands.
- `Models.swift`: `ContainerRow`/`ImageRow` (Docker-style field names, reused for native rows), `JSONRows` (Docker JSON array or JSON-lines), `ComposeProject`, `RunOptions` (create-container form → argv with validation).

**`Harbor`** (executable, SwiftUI/AppKit):
- `Store.swift`: the single `@MainActor ObservableObject`. `perform(title:command:timeout:)` is the one path for user-triggered commands: only one runs at a time (`busy`), output goes to the output sheet, then `refresh()` re-reads containers/images. `ContentView` also polls `refresh()` every 8 s. Async work snapshots `config` and discards results if it changed meanwhile. Persists only `RuntimeConfig` and Compose project paths in `UserDefaults`. Also owns the Socktainer process it starts (`startBridge`/`stopOwnedBridge`, stopped on app quit) and Terminal hand-off via `osascript`.
- `HarborApp.swift`: app scene, sidebar `Page` enum, containers/images/Compose pages, settings, create/pull/output sheets.
- `NativeViews.swift`: generic pages for build/network/volume/machine/registry/k8s (`NativeSection` shows raw CLI table output, not parsed), the searchable command catalog, and `NativeOperationSheet` (edit args, load and verify local `--help`, enable Execute only if help matched, confirm destructive ops, optionally run in Terminal; `system dns create/delete` run with `sudo` in Terminal).

## Invariants to preserve

- **No shell evaluation of user input.** Always pass argv arrays to `Process`. The only shell path is Terminal (`Store.openNativeTerminal`), where every argument goes through `Command.quote` and the working directory is quoted separately. Tests (`testTokenizerDoesNotEvaluateShell`, `testRunArgumentsKeepEnvironmentLiteral`, `testShellQuoteRoundTrip`) guard this.
- **Native backend never touches Docker.** `nativeCommand` uses only `config.container`.
- **Docker commands always target the explicit socket.** `dockerCommand` adds `--host unix://<socket>` and `RuntimeConfig.environment` strips inherited `DOCKER_*`/`COMPOSE_*` context/TLS vars so nothing can leak to OrbStack or another daemon. Never switch the user's default Docker context.
- **Compose file order matters**: files are passed as repeated `--file` in the user's chosen override order, with `--project-directory` set to the first file's directory.
- Don't invent UI for commands the CLI doesn't have (e.g. there is no `k8s start` in 1.5.0). Features are gated on the local `--help`, not on a hardcoded version.

## Keeping the catalog in sync

`NativeOperation.all` entries must stay in the literal form `.init("group", "title", "sub command", ...)`: `scripts/check-native-catalog.py` extracts command paths from `Native.swift` with a regex on that form. Group names are matched as strings by the UI (`NativeSection(group:)`, `Page.rawValue`, which doubles as the sidebar label) and by `testNativeCatalogIncludesAllFeatureGroups`. Compose action labels in `HarborApp.swift` are likewise the `switch` keys in `Store.compose`, and the timeout/cancel tests match on wording in `Runner`'s error messages. When adding or removing a command, also update the table in `FEATURES.md` and the 67-command counts in `README.md`/`FEATURES.md`/`VALIDATION.md`. `VALIDATION.md` records what was actually verified versus only help-checked; don't claim end-to-end runtime verification there unless it was done.

## Code style

Match the existing dense style: short type bodies, multiple statements per line with `;`, long single-line SwiftUI modifier chains. Language mode is Swift 5 (`swiftLanguageModes: [.v5]`) on the Swift 6 toolchain, min macOS 14. Views use the `ViewState<T>` alias for `SwiftUI.State` (defined in `HarborApp.swift`) to avoid ambiguity with SDKs that export a `State` macro; use it for new `@State` properties.
