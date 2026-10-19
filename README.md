# Harbor

A native Swift + SwiftUI manager for Apple Container. **Native features come first; Docker / Compose is only an optional extension.** No Electron, WebView or Node.js.

This is the **0.2 preview**. The app calls the official `container` CLI directly and does not implement its own virtual machine, container engine or Docker API.

## Feature coverage

Checked against the actual help output of the official Apple Container **1.5.0** CLI: all 67 leaf subcommands have an entry point.

| Category | Current implementation |
| --- | --- |
| Containers | Native JSON list, search, create form, start/stop, delete confirmation, details, logs, stats and a Terminal entry; advanced options, copy, export and prune go through the command panel |
| Images | Native list, pull, delete; push, tag, save, load, inspect and prune go through the command panel |
| Build | BuildKit status, image builds, builder start/stop/delete |
| Networks, volumes | Native lists read from the CLI; create, inspect, delete and prune entries |
| Registries | Login list, log in/out; interactive credentials are entered in Terminal |
| Linux machines | Create, run, list, inspect, configure, default machine, logs, stop and delete |
| System | Engine start/stop, status, version, logs, disk usage, DNS, kernel, properties |
| Kubernetes | Official experimental `k8s` plugin: create, delete, list, load-image, write-config |
| Native commands | Searchable command catalog, custom arguments, working directory, live local help, Terminal mode |
| Compose (optional) | Multi-file import with override order, validate, build, up, stop, logs and status; runs the real Docker CLI / Compose against a dedicated Socktainer socket |

**"Has an entry point" does not mean every command has its own graphical form.** The network, volume and machine pages currently show the official table output plus a generic argument panel; advanced options are passed straight through to the CLI. There is no embedded PTY terminal, file browser, live resource chart or streaming output yet. Run commands in Terminal when you need continuous logs or interaction.

Every command panel first reads the local `--help` and checks that the help belongs to the selected subcommand. An unsupported version, a plugin that is not running or a missing CLI shows an error and disables execution. A custom command entry is still available for commands added in future versions.

## Getting started

1. Install Apple's official runtime. Requires Apple Silicon and macOS 26 or later:

   ```sh
   brew install container
   ```

   You can also use the [official Apple installer](https://github.com/apple/container/releases). Harbor does not bundle or auto-install the system runtime.

2. Open `Harbor.app` and confirm the CLI path under **Runtime**. Common paths are `/usr/local/bin/container` and `/opt/homebrew/bin/container`.
3. Click **Start Engine**. The first run lets the official CLI download the recommended kernel.
4. Use **Create Container**, or pick a native action from a category. Arguments in the command panel are examples; replace resource names and paths before running. Single and double quotes are supported; there is no shell expansion, piping or redirection.

All native pages read state directly from `container`. Quitting the app does not stop Apple Container or any containers. The Terminal entry runs `container exec -it … /bin/sh` in the system Terminal, which needs `/bin/sh` in the image; first use may trigger a macOS automation permission prompt.

DNS create/delete runs `sudo container system dns …` in Terminal, where the system asks for the administrator password. The app never reads or stores passwords.

### About Kubernetes

Early Apple Container releases had no Kubernetes support. 1.5.0 ships an official experimental plugin that can create local development clusters; this is a native capability and does not depend on Socktainer. 1.5.0 has no `k8s start`, so Harbor has no invented start button.

Creating a cluster and writing config update kubeconfig as the official CLI does. The local help and the [official documentation](https://github.com/apple/container/blob/1.5.0/docs/kubernetes.md) define what is supported. Harbor never creates clusters automatically.

### Docker / Compose is optional

The native workflow needs no Docker, Socktainer or Compose. Only configure this extension when you actually need an existing Compose project:

```sh
brew install socktainer docker docker-compose
```

Socktainer must be compatible with your Apple Container version; do not skip its version check. It provides partial Docker API compatibility, and Harbor does not promise full Docker Engine behavior.

- Expand the compatibility settings under **Compose · Optional** to see diagnostics and configured paths and to start Socktainer.
- Install the Compose plugin as `brew info docker-compose` describes, merging `cliPluginsExtraDirs` into your existing Docker config without overwriting credentials.
- In-app Docker commands always pass the dedicated Unix socket and clear inherited Docker context/TLS environment variables; the default Docker context is never switched automatically.
- After clicking **Create harbor-apple Context** you can run `docker --context harbor-apple compose up -d`.
- If your Docker CLI comes from OrbStack, install a standalone client and update the path before uninstalling OrbStack.
- Quitting Harbor stops the Socktainer instance this app session started; external services are unaffected. The native engine and containers keep running.

The bundled `Examples/web-stack/compose.yaml` is an optional nginx + Redis example. It passes the official Compose config validation but has not been started against a real runtime.

## Build and checks

With the Swift 6+ Command Line Tools or Xcode installed, run from the project directory:

```sh
bash scripts/build-app.sh
swift run HarborChecks
```

You can also open `Package.swift` in Xcode. There are no external Swift package dependencies. The command-line tests are a standalone executable, so they run with only the Command Line Tools installed; XCTest is not required.

- `HARBOR_BUILD_DIR` sets the build cache directory.
- `HARBOR_CONFIGURATION=debug` produces a debug build; the script defaults to release.
- `python3 scripts/check-native-catalog.py` checks the command catalog against the local CLI help; `HARBOR_CONTAINER` selects the executable.
- `python3 scripts/check-docker-adapter.py` tests the optional Docker adapter; `HARBOR_DOCKER` selects the Docker path.
- The build script produces a locally ad-hoc signed `.app` that is not notarized. Sign it with a developer identity and notarize it before distributing to other Macs.

## Design and implementation

```text
SwiftUI pages → HarborCore → Foundation.Process → official container CLI
                                                └─ Apple Container services
Optional Compose → Docker CLI → dedicated Socktainer socket → Apple Container
```

- Processes are launched with an executable path and an argument array; user arguments are never evaluated by a shell.
- The only shell interface is Terminal; each argument is quoted individually and the working directory is escaped separately.
- The main views parse the official JSON; unsupported JSON shapes produce an explicit error instead of fake empty resources.
- Commands run in the background; stdout and stderr are written to separate temporary files to avoid pipe blocking.
- Timeouts and cancellation are supported; canceling the CLI does not guarantee that work already submitted to the engine is undone, so refresh to check state.
- CLI output is shown after the command finishes; output over 2 MB asks you to use Terminal. The service log view shows the last 256 KB.
- The app stores tool paths and Compose file paths; it does not persist environment variables entered when creating a container. Logs and inspect output may contain sensitive data; review them before sharing.

## Open-source references

The public features and architecture notes of these projects were studied for ideas on category navigation, using the CLI as the source of truth, native interaction and version adaptation. No source code, icons or UI assets were copied:

- [sembsa/ContainerDesktop](https://github.com/sembsa/ContainerDesktop): native command categories, runtime tools and CLI architecture.
- [capsule-native/capsule](https://github.com/capsule-native/capsule): Swift module boundaries and native backend design.
- [PenningLabs/container-desktop](https://github.com/PenningLabs/container-desktop): container details and system feature organization.

Runtime references: [Apple Container 1.5.0](https://github.com/apple/container/releases/tag/1.5.0), [Socktainer](https://github.com/socktainer/socktainer), [Docker Compose](https://docs.docker.com/reference/cli/docker/compose/). These tools are installed separately; no third-party implementation is merged into this project.

## Validation scope

See `VALIDATION.md`. Compilation, the native command catalog, local help, process invocation and parsing have been checked. The runtime is not installed on the test machine, so real containers, networks, volumes, Linux machines, Kubernetes and Compose still need end-to-end verification. Command entry coverage should not be read as full production readiness.

Images, volumes, databases and credentials from OrbStack are not migrated automatically. Before switching for real, verify data persistence, networking and builds with your own projects.
