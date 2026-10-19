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

- **CI builds the app with zero compiler warnings** on GitHub's macOS runner. Xcode 27 was not on that image, so the build used Xcode 26.6 and the macOS 26.5 SDK with a macOS 27 deployment target. Building against the macOS 27 SDK is still to be confirmed.
- **All 21 core checks pass** on Linux (Swift 6.1, locally and in CI). The new checks cover `TextTable` parsing, port links, the per-entry Run Container validation, `example(naming:)` and pretty JSON. A macOS 26 runner cannot launch binaries built for macOS 27, so the checks were built but not run on macOS.
- `Store.swift` (now `@Observable`) was type-checked on Linux against stand-ins for the AppKit symbols it uses. It was exercised with fake executables: concurrent jobs, refusal of a second job on the same resource, banners for failures and successes, cancel, output shown only when requested, and `--help`-gated features.
- **The redesigned UI has not been launched or looked at.** Layout, Liquid Glass rendering, animations and the sheet hand-offs need a run on macOS 27.

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
