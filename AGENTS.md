# AGENTS.md

Guidance for AI coding agents working in this repository.

## What this is

Harbor is a native Swift + SwiftUI macOS GUI for Apple Container (0.4 preview, macOS 27). It never implements a VM, engine, or Docker API itself: every action shells out (without a shell) to the official `container` CLI. Docker / Compose support is an optional extension that talks to a Socktainer Unix socket. No external Swift package dependencies, no Electron/WebView/Node.

## Language: English only

Everything in this repository is written in English, with no exceptions:
- code: identifiers, comments, UI strings, error and log messages, test names and test data;
- docs: `README.md`, `FEATURES.md`, `VALIDATION.md`, this file and any new Markdown;
- scripts, config files and file names;
- git: commit messages, branch names, PR titles and descriptions, review replies.

This holds even when the request is written in another language: translate, don't copy. If a file you touch still contains non-English text, translate it in the same change.

## Commands

The app is macOS only (SwiftUI, AppKit, `codesign`). The minimum is macOS 27 (`Package.swift`, and `LSMinimumSystemVersion` in `scripts/build-app.sh`), so building needs the macOS 27 SDK: Xcode 27 or its Command Line Tools. `HarborCore` and `HarborChecks` also build and run on Linux, so core changes can be verified without a Mac; keep `HarborCore` free of SwiftUI/AppKit.

CI (`.github/workflows/ci.yml`) builds `Harbor.app` on a macOS runner, runs `HarborChecks` on Linux (and on macOS once the runner is on 27), and runs the Docker adapter check. Without a Mac, CI is the only way to compile the SwiftUI target, so push and read its result before calling UI work done.

```sh
bash scripts/build-app.sh                 # release build → ./Harbor.app (ad-hoc signed, not notarized)
HARBOR_CONFIGURATION=debug bash scripts/build-app.sh
swift build --product Harbor              # compile only
swift run HarborChecks                    # run the test suite
docker run --rm -v "$PWD":/src -w /src swift:6.1-noble swift run HarborChecks   # same, on Linux
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
- `Command.swift`: `Command` (executable + argv array, never a shell string; `quote` leaves safe words bare), `TerminalScript` (the AppleScript/shell line for Terminal hand-off), `Runner.run/checked` (runs off-main via `Task.detached`, writes stdout/stderr to separate temp files to avoid pipe deadlock, polls for timeout/cancellation then SIGTERM→SIGKILL, stops a command once either stream passes its `outputLimit` (2 MB by default; followed logs pass 256 MB and keep only the last megabyte on screen), optionally streams complete lines to `onOutput` about every 250 ms), and `RuntimeConfig` (tool paths + socket; builds `nativeCommand`, `dockerCommand`, `composeCommand`).
- `Native.swift`: `NativeParser` (parses `container ... --format json` as the 1.5.0 encoders write it: ISO 8601 dates, mount types and users as single-key enum objects (`{"virtiofs":{}}`, `{"id":{"uid":0,"gid":0}}`), `ipv4Address` with its prefix length, cumulative `stats` counters; also the legacy shape where `status` is a string and dates are reference-date seconds; throws on unknown shapes rather than returning empty lists), `ArgumentTokenizer` (POSIX-style quote/escape splitting only, no expansion), `NativeHelp.matches` (confirms `--help` output belongs to the requested subcommand, not the root fallback; k8s plugin prints `USAGE: k8s ...`), and `NativeOperation.all`, the catalog of all 67 leaf CLI commands (`terminal`/`destructive`/`admin` flags; `groups` and `operations(in:)` for the UI).
- `Forms.swift`: `BuildOptions`, `NetworkOptions`, `VolumeOptions` (form → argv with `problem`, like `RunOptions`) and `ResourceName`.
- `Files.swift`: `ContainerFiles` (browse with the container's own `ls -1Ap`, copy with `container copy`; local paths with a colon are refused because `copy` reads `id:path`) and `DockerImport` (known engine sockets, `docker image ls` rows, save/load arguments).
- `Installer.swift`: `InstallerPackage` (picks the signed `.pkg` from the latest apple/container GitHub release JSON).
- `Models.swift`: `ContainerRow` (native rows with `ContainerDetails`, and Compose service rows decoded from Docker's JSON keys, including `Publishers` and `Service`) with `PortMapping`s (browser `url` per published TCP port), `ImageRow`/`ImageReference` (keeps registry ports and digests out of the tag; `isValid` for image fields; `sameImage` matches `docker.io/library/…` spellings), `JSONRows` (Docker JSON array or JSON-lines), `ComposeProject` (`directory` is derived from the first file, so reordering moves it), `ComposeAction` (typed Compose buttons → argv, optionally for one service), `RunOptions` (Run Container form → argv; `problem` is the inline validation message; `optionalFlags` are offered only when `run --help` lists them), `ContainerStats` (cumulative counters; `cpuPercent` and `rate` compare two samples), `TextTable` (column-aligned CLI listings → rows, nil when not aligned), `JSONText.pretty`.

**`Harbor`** (executable, SwiftUI/AppKit, one `Window` scene):
- `Store.swift`: the single `@MainActor @Observable` store (views read it with `@Environment(Store.self)`), plus `Job`, `EngineState`, `SheetRoute` and `NativeRequest`.
  - `run(_:subject:showOutput:_:)` is the one path for user-triggered work (`perform` wraps it for one command, `stream(_:into:timeout:)` runs a command inside a job). Each `Job` is its own `@Observable` object, so streamed output redraws only the views showing that job.
  - Jobs run concurrently. A job with a `subject` (container ID, `"image <ref>"`, project ID, `"engine"`, `"bridge"`) refuses to start while another job on that subject runs, and `isBusy(_:)` disables the matching controls.
  - When a job ends, `banner` drives the activity capsule (failures stay, successes clear after 4 s), `changeCount` tells raw listings to reload, and `refresh()`/`refreshServices()` re-read state.
  - `listings` keeps each resource page's last raw CLI listing. `ResourceView` shows it at once and refreshes in place with `readListing`, and `prefetchPages` reads every page, plus the Compose status, when the engine comes up. Pages must not open empty and grow when data arrives: keep fetched data in the store and assign only values that changed (as `apply` and `refreshServices` do).
  - `present(_:)` is the only way to show a sheet; it closes the current one first, since macOS shows one at a time, and a newer request cancels an older one still waiting.
  - A failed container list is read once more after a second before the engine counts as stopped, and only while it was running; a list or image read that fails while the engine answers keeps the previous rows and sets `containerError`/`imageError`. Pages must not flip to setup or empty on one hiccup.
  - The store owns polling (started in `init`, so it continues for the menu bar extra with the window closed): every 6 s while the app is active, every 30 s in the background only while the menu bar extra is shown. `apply` only reassigns values that changed, and a refresh requested mid-read queues one more pass. Async work snapshots `config` and discards results if it changed meanwhile.
  - Persists only `RuntimeConfig`, Compose project paths and the `Preference` values (menu bar extra, notifications, glass style, backdrop style and custom picture path) in `UserDefaults`. A job that fails or runs 5 s or longer while Harbor is inactive posts a user notification. Owns the Socktainer process it starts (`startBridge`/`stopOwnedBridge`; stopped when it fails to become ready and, via a `willTerminate` observer in `init`, on quit even if the window is closed) and Terminal hand-off via `osascript`. `help(for:)`/`supports(_:flag:)` cache local `--help` to gate optional features such as log following.
- `HarborApp.swift`: the window (hidden title bar), settings and `MenuBarExtra` scenes, menu commands and keyboard shortcuts (including the Go menu, ⌘1–⌘9), the `ViewState` alias.
- `MenuBarView.swift`: the menu bar extra (engine state, per-container actions, opening the window).
- `ContainerPanels.swift`: the inspector's Stats tab (two samples per point, Swift Charts) and Files tab (browse, download, upload, drop to upload).
- `FormSheets.swift`: Build Image, Tag Image, Create Network, Create Volume and Import Images sheets.
- `RootView.swift`: the floating shell (sidebar pane beside the page, over the `BackdropView`, in the `Backdrop.space` coordinate space; renders the panes' mirror when the backdrop, appearance or glass style changes), the `Page` enum (`group` maps a page to its catalog group) and sidebar sections, sheet routing, `Store.requestedPage` handling and window-wide drops (`Store.open`).
- `Shell.swift`: the window chrome and shared controls: `WindowControls` (the system's own traffic-light buttons, moved into the sidebar pane), `WindowDragArea`, `PageScaffold` (title and controls over the wallpaper, the page's panes below, the activity capsule over the bottom), `GlassControls`/`HeaderIcon`/`HeaderMenu`, `PrimaryActionButton`, `GlassSearchField`, `PillPicker`, `SelectableRows` (the custom list with violet selection, multi-select, keyboard, double-click and context menus), `MiniButtonStyle`, `InfoSection`/`InfoRow` and `paneScroll()`.
- `ActivityViews.swift`: the Liquid Glass activity capsule, the Activity button and popover (at the foot of the sidebar) and `JobOutputSheet`.
- `ContainersView.swift`, `ImagesView.swift`, `RunContainerSheet.swift` (with `PullImageSheet` in the images file), `ComposeView.swift`, `EngineView.swift` (also `EngineSetupView` for first-run states, and `SettingsView`, which edits a draft that `Store.applySettings` commits so half-typed paths never reach the live config).
- `NativeViews.swift`: `ResourceView` for build/network/volume/machine/registry/k8s (the CLI listing parsed with `TextTable`, per-row actions from `Page.rowActions` that prefill the resource name via `NativeOperation.example(naming:)`), the command catalog, and `NativeOperationSheet` (edit args, load and verify local `--help`, enable Run only if the help matched, confirm destructive ops, optionally run in Terminal; `system dns create/delete` run with `sudo` in Terminal).
- `Setup.swift`: installing Apple Container (`installWithHomebrew`, `installWithHomebrewInTerminal`, `installWithOfficialInstaller`), all ending in `startInstalledEngine` (locate the CLI, `adoptCLI`, `system start`), plus `HostInfo.isAppleSilicon`. `SetupGuide` in `EngineView.swift` is its UI.
- `Components.swift`: `LogTextView`/`OutputPanel` (NSTextView-backed output that appends incrementally and follows the end), `PortLinks`, `StateBadge`, `RowIcon`, `EntryListEditor`.
- `Backdrop.swift`: `BackdropStyle` (aurora, harbor, desktop picture, custom picture), the `Backdrop` model (style, picture, size and origin relative to the window, and `mirror`, the backdrop pre-blurred for the glass style), `BackdropView`, `BackdropMirror`, `BackdropContent`, `BackdropTracker` (keeps picture backdrops lined up with the screen) and the aurora and harbor painters.
- `Theme.swift`: the Aurora Ice colors (dynamic light/dark), `GlassStyle`, the `GlassPanel` modifier (the pane's part of the mirror under `ClearSurface` or `CrystalSurface`, with `PaneShadow`) with `glassPanel()`, `card(padding:)` and `huggingGlassPanel(height:)`.

## Invariants to preserve

- **No shell evaluation of user input.** Always pass argv arrays to `Process`. The only shell path is Terminal (`TerminalScript`, used by `Store.openInTerminal`), where every argument goes through `Command.quote` and the working directory is quoted separately. Tests (`testTokenizerDoesNotEvaluateShell`, `testRunArgumentsKeepEnvironmentLiteral`, `testShellQuoteRoundTrip`, `testTerminalScriptQuotesEveryPart`) guard this.
- **Native backend never touches Docker.** `nativeCommand` uses only `config.container`.
- **Docker commands always target the explicit socket.** `dockerCommand` adds `--host unix://<socket>` and `RuntimeConfig.environment` strips inherited `DOCKER_*`/`COMPOSE_*` context/TLS vars so nothing can leak to OrbStack or another daemon. Never switch the user's default Docker context. The one command that reads another engine, image import, names that engine's socket the same way (`dockerCommand(_:socket:)`) and only runs `image ls` and `image save` there.
- **Compose file order matters**: files are passed as repeated `--file` in the user's chosen override order, with `--project-directory` set to the first file's directory.
- **Installers come only from official sources, and passwords never pass through Harbor.** `InstallerPackage.parse` accepts only HTTPS `.pkg` assets from `github.com/apple/container/releases/download/` (guarded by `testInstallerPackageComesFromOfficialReleases`). The downloaded package is quarantine-marked and must pass `pkgutil --check-signature` before Installer opens it. Anything that needs a password happens in macOS Installer or Terminal.
- Don't invent UI for commands the CLI doesn't have (e.g. there is no `k8s start` in 1.5.0). Features are gated on the local `--help`, not on a hardcoded version.

- **Optional `run` flags are gated on the local help.** The Run Container form shows a control only when `container run --help` lists its flag (`RunOptions.optionalFlags`); `testRunFormOptionalFlags` checks the form never emits an ungated flag.

## App icon

`Resources/AppIcon.icns` is generated: change `scripts/make-icon.py` (needs Pillow) and run `python3 scripts/make-icon.py`, never edit the `.icns` by hand. `scripts/build-app.sh` copies it into the bundle.

## Keeping the catalog in sync

`NativeOperation.all` entries must stay in the literal form `.init("group", "title", "sub command", ...)`: `scripts/check-native-catalog.py` extracts command paths from `Native.swift` with a regex on that form. Group names are matched as strings by the UI (`Page.group`, `NativeActionsMenu(group:)`, the Engine page's `"System"` tiles) and by `testNativeCatalogIncludesAllFeatureGroups`. `Page.rowActions` names catalog IDs whose examples must end with the resource name. The timeout/cancel/output-limit tests match on wording in `Runner`'s error messages, and `scripts/check-docker-adapter.py` mirrors the `compose ps` arguments in `ComposeProject.serviceQuery`. When adding or removing a command, also update the table in `FEATURES.md` and the 67-command counts in `README.md`/`FEATURES.md`/`VALIDATION.md`. `VALIDATION.md` records what was actually verified versus only help-checked; don't claim end-to-end runtime verification there unless it was done.

## UI conventions

- The layout is the design's **floating shell**, not the system split view: the window has no title bar, and panes of glass float over a backdrop the app draws itself with gaps between them (10 pt from the window edge, 14 between sidebar and page, 12 between page and inspector). The sidebar is a pane with the window's buttons inside it; each page is a `PageScaffold` whose title and controls sit on the backdrop; details open in a pane of their own beside the page. Don't bring back `NavigationSplitView`, `.toolbar`, `.searchable` or `.inspector`: the split view collapsed the sidebar when the inspector opened, and toolbar items reflowed while it slid in. Gaps and titles move the window (`WindowDragArea`); controls must not overlap the sidebar's traffic lights.
- Lists use `SelectableRows`, whose violet selection stays violet when the list loses focus (the system list turns it gray). Keep `ContentUnavailableView`, menus, popovers, sheets and grouped `Form`s in sheets; they are native and fine.
- The look is **Aurora Ice with clear glass**, design B + 4 (`Theme.swift`, `Backdrop.swift`; values cited in comments). Glass needs color and shape behind it: over a plain or white background (the desktop through a clear window, or a behind-window blur) every recipe read as a white card, so Harbor draws its own backdrop (`BackdropStyle`: aurora blocks by default, the design's harbor, the desktop picture lined up with the screen, or a custom picture). Panes use public API only: each draws its part of `Backdrop.mirror` (the backdrop rendered once with the glass style's blur and saturation: 6 and 1.6 for clear, 14 and 1.8 for crystal), lined up through `Backdrop.space`, then `ClearSurface` (design B, with a 30 % tint instead of 12 % and blur 6 instead of 2.5 so small gray text stays readable on any backdrop; 122° sheen, top-left and bottom-right edge light, faint inner glow, white border) or `CrystalSurface` (design C: stronger tint, inner glow, sheen, edge light), and a Core Animation `PaneShadow` cut out under the pane. Don't use behind-window `NSVisualEffectView`s or SwiftUI materials for panes: they cannot be tuned and looked flat. A `glassPanel()` inside another pane draws as a lighter well (`insidePane`), never as a second sheet of glass. Floating controls (header groups, the activity capsule) always use the system's clear Liquid Glass (`.glassEffect(.clear…)`), which bends the backdrop. With Reduce Transparency the panes are solid. Don't add other materials or fills for content.
- Pane sizes: a pane stretched over the whole page reads as a background, so lists use `huggingGlassPanel(height:)` and scrolling pages of cards use `paneScroll()`, which keeps the cards' shadows from being cut off at the sides.
- Colors come from `Theme.swift` only, never literal values in views:
  - `Color.harbor` (violet) for tint, selection washes, brand icons and the primary button;
  - `Color.harborText` for small violet text;
  - `Color.harborLive` for running, connected and success (the design's deep violet);
  - `Color.harborInk` for body text (set on the shell) and `Color.harborSub` for secondary text, section labels and idle icons.
  
  Each has a light and a dark value; keep text at 4.5:1 on glass in both.
- Page filters (such as All / Running / Stopped) are `PillPicker`s in the page's pane, with the list they filter.
- Key actions stay visible: each page's main action is a labeled `PrimaryActionButton` (a short verb such as Run or Pull, with the full name and shortcut in its tooltip), and a container row always shows start/stop; secondary row actions show on hover and on the selected row. Sidebar badges count only what signals activity (running containers), never totals. Finished states step aside: the Engine page drops the setup guide once the engine runs and has containers, and shows only everyday system commands, with the rest in its … menu.
- Pane shadows are Core Animation shadows with a fixed path (`PaneShadow`); never a blurred SwiftUI `.shadow` on a pane, which is redrawn on every frame of a resize and made the inspector animation stutter.
- Lifecycle actions run as quiet jobs with a `subject`; only commands whose output is the point pass `showOutput: true`.
- Animate state changes with `.animation(_:value:)` scoped to the value that changed, not global animations.
- Long or growing text goes through `OutputPanel`, never a giant `Text`.

## Code style

Compact but readable: short type bodies, `;` only for trivially related statements, and break modifier chains across lines once they stop fitting comfortably. Keep views small and split by page or concern. Language mode is Swift 5 (`swiftLanguageModes: [.v5]`) on the Swift 6 toolchain, min macOS 27. Views use the `ViewState<T>` alias for `SwiftUI.State` (defined in `HarborApp.swift`) to avoid ambiguity with SDKs that export a `State` macro; use it for new `@State` properties and spell out the property type when the initial value is an implicit member (`@ViewState<Tab> private var tab: Tab = .overview`).
