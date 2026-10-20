# Validation record

Date: 2026-10-19 (Asia/Shanghai).

## Verified

- **The native SwiftUI app compiles and packages as an arm64 macOS `.app`**; the Info.plist format and local ad-hoc signature were checked.
- **All 15 core checks of that version passed on macOS**: native managed/legacy container JSON, image and registry port parsing, native backend independent of Docker, argument tokenizing, command catalog, help scoping, optional Docker socket isolation, Compose working directory/file order, Docker JSON, literal arguments, shell quoting, large stdout/stderr output, exit codes, timeout and cancellation.
- The CLI was extracted from Apple's official signed 1.5.0 installer and its help was read only inside the working directory, **without installing or starting the services**. **Scoped help was confirmed for 67/67 commands**; a recursive walk of the actual subcommand tree found 67 leaf commands, matching the app's catalog.
- The five Kubernetes subcommands were verified by reading help from the official `k8s` plugin inside the installer. The main CLI cannot discover plugins until the services are installed and started, so runtime plugin discovery is not claimed as verified.
- The real Docker CLI 29.8.2 was connected to an isolated temporary Unix socket to check container/image JSON fields; no OrbStack backend was connected or modified.
- Docker Compose 5.5.0 ran `config --quiet` successfully on the bundled nginx + Redis example.
- The macOS app was actually launched, and the home page, category navigation, networks page and native command argument panel were inspected through the native accessibility tree and screenshots; with the CLI missing, an error is shown and execution is disabled.

## Update: streamed activity output and Compose services

Same date, on Linux (no Mac was available for this change set):

- **All 20 core checks pass** with Swift 6.1 (`swift:6.1-noble` image), including the new ones: image references with digests, Compose directory following file order, Terminal script quoting (executed through `/bin/sh` in a directory whose name has a space and a quote), streamed output, early stop at the 2 MB limit, POSIX backslashes in double quotes, minimal shell quoting. They were not re-run on macOS.
- `Store.swift` was type-checked against small stand-ins for the Combine/AppKit symbols it uses and exercised with fake `socktainer`/`docker` executables: streamed output, nonzero exit and cancel reporting, Socktainer launch, cleanup when it exits early, stop on the quit notification, and decoding of a project's `compose ps` rows.
- The SwiftUI views were not compiled at the time. CI later built this version on a macOS 26.6 runner (Xcode 26.6, Swift 6.3.3), and the 20 checks passed there too.
- `scripts/check-docker-adapter.py` now runs the real Docker CLI 29.8.2 with Compose 5.6.0 against the fake Engine API and checks the `compose ps --format json` fields the app decodes. Compose 5.6.0 `config --quiet` passes on the bundled example.

## Update: 0.3 UI redesign for macOS 27

Same date. The app layer was rewritten (split view, glass activity capsule, concurrent jobs, inspector, parsed resource tables), and the minimum is now macOS 27.

- **CI builds the app with zero compiler warnings** on GitHub's macOS runner. Xcode 27 was not on that image, and a `macos-27` job was never picked up by a runner, so the build used Xcode 26.6 and the macOS 26.5 SDK with a macOS 27 deployment target. Building against the macOS 27 SDK is still to be confirmed.
- **All 21 core checks pass** on Linux (Swift 6.1, locally and in CI). The new checks cover `TextTable` parsing, port links, the per-entry Run Container validation, `example(naming:)` and pretty JSON. A macOS 26 runner cannot launch binaries built for macOS 27, so the checks were built but not run on macOS.
- `Store.swift` (now `@Observable`) was type-checked on Linux against stand-ins for the AppKit symbols it uses. It was exercised with fake executables: concurrent jobs, refusal of a second job on the same resource, banners for failures and successes, cancel, output shown only when requested, and `--help`-gated features.
- **The redesigned UI has not been launched or looked at.** Layout, Liquid Glass rendering, animations and the sheet hand-offs need a run on macOS 27.

## Update: guided installation

Same date, on Linux:

- **All 22 core checks pass.** The new check ensures the installer package is only taken from apple/container's own HTTPS release downloads: it rejects other repositories, plain HTTP, and the unsigned package when a signed one exists, and returns nothing for an error response.
- The Homebrew route ran end to end against fake `brew` and `container` executables in a Linux container. The steps were: missing CLI → `brew install container` with streamed output → CLI found and adopted → `system start --enable-kernel-install` → engine running. Starting an installed but stopped engine was also run. `Setup.swift` was type-checked against stand-ins for sysctl, quarantine keys and URLSession.
- **Not exercised:** a real Homebrew install, the GitHub download, `pkgutil`, quarantine, the Installer hand-off and its wait, and the setup guide's appearance. These need a Mac with macOS 27.

## Update: 0.4 features

Same date, on Linux, against the upstream 1.5.0 source:

- **The JSON parsers follow the 1.5.0 encoders read from the upstream source** (tag 1.5.0, containerization 0.47.0), not from running a CLI. These are: ISO 8601 dates, mount types and users as enum objects, addresses with a prefix length, and cumulative `stats` counters (CPU in microseconds, so the percentage comes from two samples). Flag names for the run form, build, network and volume forms, `copy`, `image load/save/push` and `stats` come from the 1.5.0 command reference.
- **All 27 core checks pass** on Linux (Swift 6.1). The new checks cover:
  - container details, image dates and stats from 1.5.0-shaped JSON;
  - the run form's optional flags, including that it never emits a flag it does not gate on the help;
  - the build, network and volume forms;
  - per-service Compose arguments;
  - the container file listing and paths, and `container copy` arguments;
  - Docker image import parsing and its explicit socket.
- `scripts/check-docker-adapter.py` now also asserts the `Service` field that per-service Compose actions use; it passes with the real Docker CLI 29.8.2.
- The app icon is generated by `scripts/make-icon.py` and was checked at 16, 32 and 1024 px.
- **Not exercised:** the new views, the menu bar extra, notifications and drag and drop were built by CI only. The following also need a real runtime: stats sampling, the file browser, `container copy`, builds, push, import from OrbStack or Docker Desktop, and the new Compose actions.

## Update: Aurora Ice and hybrid glass

The look was chosen from a canvas of browser mockups that compared four glass materials and five palettes. The app version uses SwiftUI materials, gradients and the system's clear Liquid Glass.

- **Built by CI only.** Two earlier builds were checked on a Mac from screenshots. They led to:
  - a see-through window and a hidden toolbar background;
  - no panel shadow, which made the inspector animation smooth;
  - system Liquid Glass panels sized to their content, over faint container stacks and waves.

  The latest version has not been looked at on a Mac yet, nor have the clear-glass setting, the transparency slider, dark mode and the Reduce Transparency fallback.
- **Contrast was checked by calculation, not on screen.** Measured against the panel tint over a light backdrop, violet text is 4.8:1 and mint text 4.9:1; against the dark tint, 7.2:1 and 10.7:1. Now that the window is see-through, the real backdrop depends on the desktop. A busy or dark wallpaper behind a light-mode window can lower contrast; the Background slider and Reduce Transparency are the remedies. White button text on the violet fill measures 5.4:1 in light mode and 5:1 in dark mode, and violet icons keep 3:1 on the dark backdrop.
- The app icon was regenerated in the new colors and checked at 16, 32 and 1024 px.

## Update: the design's floating shell

Screenshots showed the app still far from the chosen design: system split view, the sidebar collapsing while the inspector opened, a gray selection, and glass that barely showed. The shell was rebuilt from the design's source values.

- **What changed:** no title bar, with the system's own window buttons moved into the sidebar pane; floating panes for sidebar, page and inspector; a custom list with violet selection; a clear window (the design's harbor is its desktop wallpaper), with panes that blur what is behind the window under the design's tint, glow, sheen and edges; Core Animation pane shadows. A first version drew the harbor inside the window; a screenshot showed that reads as an app background, so it was removed.
- **Built by CI only.** None of it has been looked at on a Mac yet. Still to check there: the traffic lights' hover symbols and states, window dragging from gaps and titles, the inspector slide, keyboard selection in lists, clicks and dragging in the window's clear gaps, how the panes look over different desktops, dark mode, the clear-glass setting and Reduce Transparency.

## Not yet verified

Apple Container / Socktainer are not formally installed on the test machine, so none of the following count as completed end-to-end tests:

- Creating, starting, stopping and deleting real containers; pulling, building and pushing images; copying files.
- Network traffic, DNS, published ports, volume persistence, resource stats.
- Linux machine creation, mounts and interactive login.
- Kubernetes cluster creation, CNI, kubeconfig merge and image loading.
- Socktainer version matching, service startup, and Compose up/stop, builds and service discovery.
- Terminal automation permission, administrator DNS authorization and interactive registry login.
- Live output of the real CLIs in the Activity sheet, for example whether image pull progress is written line by line when not attached to a terminal.

Command help verification only proves that entry points and argument descriptions belong to the real CLI. It does not mean those operations were executed, nor does it prove full OrbStack / Docker compatibility.

## Reproduce

```sh
swift run HarborChecks
python3 scripts/check-native-catalog.py
python3 scripts/check-docker-adapter.py
```

CLI paths can be set with `HARBOR_CONTAINER`, `HARBOR_K8S_PLUGIN` (standalone plugin test only) and `HARBOR_DOCKER` respectively. The checks never pull images, create containers or change the default Docker context.
