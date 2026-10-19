# Validation record

Date: 2026-10-19 (Asia/Shanghai).

## Verified

- **The native SwiftUI app compiles and packages as an arm64 macOS `.app`**; the Info.plist format and local ad-hoc signature were checked.
- **All 15 core checks pass**: native managed/legacy container JSON, image and registry port parsing, native backend independent of Docker, argument tokenizing, command catalog, help scoping, optional Docker socket isolation, Compose working directory/file order, Docker JSON, literal arguments, shell quoting, large stdout/stderr output, exit codes, timeout and cancellation.
- The CLI was extracted from Apple's official signed 1.5.0 installer and its help was read only inside the working directory, **without installing or starting the services**. **Scoped help was confirmed for 67/67 commands**; a recursive walk of the actual subcommand tree found 67 leaf commands, matching the app's catalog.
- The five Kubernetes subcommands were verified by reading help from the official `k8s` plugin inside the installer. The main CLI cannot discover plugins until the services are installed and started, so runtime plugin discovery is not claimed as verified.
- The real Docker CLI 29.8.2 was connected to an isolated temporary Unix socket to check the container/image JSON fields parsed by the optional compatibility layer; no OrbStack backend was connected or modified.
- Docker Compose 5.5.0 ran `config --quiet` successfully on the bundled nginx + Redis example.
- The macOS app was actually launched, and the home page, category navigation, networks page and native command argument panel were inspected through the native accessibility tree and screenshots; with the CLI missing, an error is shown and execution is disabled.

## Not yet verified

Apple Container / Socktainer are not formally installed on the test machine, so none of the following count as completed end-to-end tests:

- Creating, starting, stopping and deleting real containers; pulling, building and pushing images; copying files.
- Network traffic, DNS, published ports, volume persistence, resource stats.
- Linux machine creation, mounts and interactive login.
- Kubernetes cluster creation, CNI, kubeconfig merge and image loading.
- Socktainer version matching, service startup, and Compose up/stop, builds and service discovery.
- Terminal automation permission, administrator DNS authorization and interactive registry login.

Command help verification only proves that entry points and argument descriptions belong to the real CLI. It does not mean those operations were executed, nor does it prove full OrbStack / Docker compatibility.

## Reproduce

```sh
swift run HarborChecks
python3 scripts/check-native-catalog.py
python3 scripts/check-docker-adapter.py
```

CLI paths can be set with `HARBOR_CONTAINER`, `HARBOR_K8S_PLUGIN` (standalone plugin test only) and `HARBOR_DOCKER` respectively. The checks never pull images, create containers or change the default Docker context.
