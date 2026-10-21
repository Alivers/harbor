# Harbor

A native Swift + SwiftUI manager for Apple Container. **Native features come first; Docker / Compose is only an optional extension.** No Electron, WebView or Node.js.

This is the **0.4 preview** and requires **macOS 27** on Apple silicon. The app calls the official `container` CLI directly and does not implement its own virtual machine, container engine or Docker API.

## Using Harbor

- **Floating glass panes.** No title bar: the sidebar, the page and its details are separate panes of glass floating over a colorful backdrop, with the window's buttons inside the sidebar. A sidebar groups Workloads, Resources, Environments and System (⌘1–⌘9 jump between pages). Each page has its title, search and actions at the top and opens details in a pane beside it.
- **Aurora Ice, in clear glass.** Ice, lilac and mint by day, deep indigo by night, with violet for selection and actions.
  - Glass needs something behind it, so Harbor draws its own backdrop: soft aurora blocks by default. Settings › Appearance offers the harbor from the design, your desktop picture lined up with the screen, or a picture you choose.
  - Panes are clear glass: the backdrop lightly blurred under a lilac tint strong enough for small text, bright edges, a slanted sheen and a soft shadow. Settings switches them to whiter crystal glass with more blur and an inner glow.
  - Floating controls, such as the header buttons and the activity capsule, are the system's clear Liquid Glass. With Reduce Transparency on, the panes are solid.
- **Nothing blocks.** Starting, stopping, pulling or composing runs in the background, and several jobs can run at once; only the resource a job changes is locked. The capsule at the bottom of the window shows what is running, then how it ended. A failure stays until you dismiss it or open its output. The clock button at the foot of the sidebar lists recent jobs with their full output.
- **Output where it matters.** Logs, inspect output, reports and raw catalog commands open their output right away. Lifecycle actions don't open anything unless they fail.
- **Containers.** Filter by running or stopped and sort by name, image, state or age. Click a published port to open it in the browser. Rows show actions on hover, and right-click gives you the rest; select several rows to start, stop, restart or delete them together. Double-click a row, or use the details button (⌥⌘I), for:
  - **Overview**: command, working directory, user, networks with their addresses, mounts, environment (values hidden until you show them) and labels.
  - **Logs**: recent output, followed live when the CLI supports `--follow`.
  - **Stats**: live CPU, memory and network charts.
  - **Files**: browse the container's folders, download files, and upload by picking or dropping files.
  - **Inspect**: the raw JSON.

  Deleting a running container stops it first, after you confirm.
- **Run Container form.** Pick a network and named volumes from lists, mount a folder, and set Delete-when-stopped, architecture (to run amd64 images), init process, read-only root, entrypoint, working directory, user and labels. Each option appears only when your CLI's `container run --help` lists it.
- **Images.** Build from a Dockerfile, tag, push, save to and load from archives, and remove dangling or unused images. Each image shows when it was created and which containers use it. **Import from Docker** copies images from OrbStack, Docker Desktop or Colima.
- **Networks and volumes.** Create them with a form; the list shows which containers use each one.
- **Compose.** Up, Stop, Restart, Pull, Build and Down (optionally deleting volumes) per project, and start, stop, restart, logs, pull and build per service.
- **Drag and drop.** Drop Compose files to import a project, `.tar` archives to load images, or a folder or Dockerfile to open the Build Image form.
- **Menu bar.** The Harbor menu shows the engine and running containers, with quick actions, while the window is closed. Turn it off in Settings.
- **Notifications.** A job that fails or takes more than a few seconds while Harbor is in the background posts a notification. Turn it off in Settings.
- **First run.** If the CLI is missing, Harbor offers the install command and the installer link. If the engine is stopped, a single button starts it.
- **Keyboard.** ⌘N runs a container, ⇧⌘P pulls an image, ⇧⌘B builds one, ⌘O imports a Compose project, ⌘R refreshes, and ⌘F inside any output finds text.

## Feature coverage

Checked against the actual help output of the official Apple Container **1.5.0** CLI: all 67 leaf subcommands have an entry point.

| Category | Current implementation |
| --- | --- |
| Containers | Native JSON list with filter, sort and search, run form, start/stop/restart and delete for one or many, port links, inspector with details, live logs, live stats charts, file browser with download/upload, inspect JSON, Terminal shell; export and prune go through the command panel |
| Images | Native list with search, creation date and in-use badge, background pull, build form, tag, push, save, load, prune, import from another Docker engine, run from image, multi-select delete; inspect goes through the command panel |
| Build | Build form (context, Dockerfile, tags, build arguments, target, platform), BuildKit status, builder start/stop/delete |
| Networks, volumes | Lists read from the CLI and shown as tables with a Used By column, inspect/delete per row, create forms, prune |
| Registries | Login list, log in/out; interactive credentials are entered in Terminal |
| Linux machines | Create, run, list, inspect, configure, default machine, logs, stop and delete |
| System | Engine start/stop, status, version, logs, disk usage, DNS, kernel, properties |
| Kubernetes | Official experimental `k8s` plugin: create, delete, list, load-image, write-config |
| Native commands | Searchable command catalog, custom arguments, working directory, live local help, Terminal mode |
| Compose (optional) | Multi-file import (or drop) with override order, validate, build, pull, up, stop, restart, down, logs and status, per-service actions, and each project's containers listed in place; runs the real Docker CLI / Compose against a dedicated Socktainer socket |

**"Has an entry point" does not mean every command has its own graphical form.** The network, volume, machine, registry and Kubernetes pages show the official CLI listing as a table, with per-row actions and a generic argument panel; advanced options are passed straight through to the CLI. If a listing is not an aligned table, it is shown verbatim. There is no embedded PTY terminal; interactive shells open in Terminal.

Every command panel first reads the local `--help` and checks that the help belongs to the selected subcommand. An unsupported version, a plugin that is not running or a missing CLI shows an error and disables execution. A custom command entry is still available for commands added in future versions.

## Getting started

Open `Harbor.app` (macOS 27, Apple silicon). Until the engine runs, the Containers and Images pages show a three-step setup guide; the Engine page keeps it as a checklist afterwards.

1. **Install Apple Container.** Harbor does not bundle the runtime, but it installs it when you ask:
   - **Install with Homebrew** (offered when Homebrew is present) runs `brew install container` inside Harbor, with its output in the activity list. No password is needed.
   - **Download Official Installer** fetches the newest release from [apple/container](https://github.com/apple/container/releases). It only accepts a `.pkg` served from that repository's own release downloads, saves it to Downloads marked as a download (so Gatekeeper checks it), stops if `pkgutil --check-signature` fails, and opens it in Installer. macOS asks for your administrator password there; Harbor never sees it.
   - **Other Options** runs the Homebrew install in Terminal (for setups where it asks for a password), opens the releases page, or lets you point Settings at an existing CLI.

   Harbor finds the CLI in `/opt/homebrew/bin`, `/usr/local/bin` or `/usr/bin`, including one installed outside Harbor while it runs.
2. **Start the engine.** After an install from Harbor, the engine starts by itself; otherwise click **Start Engine**. The first start downloads the recommended Linux kernel.
3. **Run your first container.** Press **⌘N**, or pick a native action from any page.

Arguments in the command panel are examples (row actions prefill the resource you picked); check names and paths before running. Single and double quotes are supported; there is no shell expansion, piping or redirection.

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

- On the **Compose** page, **Start Service** launches Socktainer, and **Setup and diagnostics** shows the configured paths and checks.
- Install the Compose plugin as `brew info docker-compose` describes, merging `cliPluginsExtraDirs` into your existing Docker config without overwriting credentials.
- In-app Docker commands always pass the dedicated Unix socket and clear inherited Docker context/TLS environment variables; the default Docker context is never switched automatically.
- After clicking **Create harbor-apple Context** you can run `docker --context harbor-apple compose up -d`.
- If your Docker CLI comes from OrbStack, install a standalone client and update the path before uninstalling OrbStack.
- Quitting Harbor stops the Socktainer instance this app session started; external services are unaffected. The native engine and containers keep running.

The bundled `Examples/web-stack/compose.yaml` is an optional nginx + Redis example. It passes the official Compose config validation but has not been started against a real runtime.

## Build and checks

With Xcode 27 or the matching Command Line Tools (macOS 27 SDK, Swift 6.2 or later) installed, run from the project directory:

```sh
bash scripts/build-app.sh
swift run HarborChecks
```

You can also open `Package.swift` in Xcode. There are no external Swift package dependencies. The command-line tests are a standalone executable, so they run with only the Command Line Tools installed; XCTest is not required.

The UI-free `HarborCore` library and its checks also build on Linux with a Swift 6 toolchain, which is handy for CI; the app itself needs macOS:

```sh
docker run --rm -v "$PWD":/src -w /src swift:6.1-noble swift run HarborChecks
```

- `HARBOR_BUILD_DIR` sets the build cache directory.
- `HARBOR_CONFIGURATION=debug` produces a debug build; the script defaults to release.
- `python3 scripts/check-native-catalog.py` checks the command catalog against the local CLI help; `HARBOR_CONTAINER` selects the executable.
- `python3 scripts/check-docker-adapter.py` runs the real Docker CLI and Compose plugin against a fake Engine API to check the `compose ps` JSON the app decodes; `HARBOR_DOCKER` selects the Docker path.
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
- User-triggered commands run as background jobs, concurrently except on the same resource. Output streams in line by line and stays in the Activity list.
- Views observe only the state they read (`@Observable`), the 6-second refresh skips unchanged data, and output views append text instead of redrawing it. In the background Harbor reads state every 30 seconds only while the menu bar extra is shown, and not at all otherwise.
- The file browser lists folders with the container's own `ls` and copies with `container copy`. Images without `ls` (distroless, scratch) cannot be browsed, though a known path can still be downloaded.
- Importing from another Docker engine names that engine's socket explicitly, like every Docker command Harbor runs, and only reads there (`image ls`, `image save`).
- Timeouts and cancellation are supported; canceling the CLI does not guarantee that work already submitted to the engine is undone, so refresh to check state.
- A command that writes more than 2 MB is stopped and you are asked to use Terminal. The service log view shows the last 256 KB.
- The app stores tool paths, Compose file paths and two preferences; it does not persist environment variables entered when creating a container. The container overview hides environment values until you choose to show them. Logs and inspect output may contain sensitive data; review them before sharing.

## Open-source references

The public features and architecture notes of these projects were studied for ideas on category navigation, using the CLI as the source of truth, native interaction and version adaptation. No source code, icons or UI assets were copied:

- [sembsa/ContainerDesktop](https://github.com/sembsa/ContainerDesktop): native command categories, runtime tools and CLI architecture.
- [capsule-native/capsule](https://github.com/capsule-native/capsule): Swift module boundaries and native backend design.
- [PenningLabs/container-desktop](https://github.com/PenningLabs/container-desktop): container details and system feature organization.

Runtime references: [Apple Container 1.5.0](https://github.com/apple/container/releases/tag/1.5.0), [Socktainer](https://github.com/socktainer/socktainer), [Docker Compose](https://docs.docker.com/reference/cli/docker/compose/). These tools are installed separately; no third-party implementation is merged into this project.

## Validation scope

See `VALIDATION.md`. Compilation, the native command catalog, local help, process invocation and parsing have been checked. The runtime is not installed on the test machine, so real containers, networks, volumes, Linux machines, Kubernetes and Compose still need end-to-end verification. Command entry coverage should not be read as full production readiness.

Images can be copied from OrbStack or Docker Desktop with Import from Docker; volumes, databases and credentials are not migrated. Before switching for real, verify data persistence, networking and builds with your own projects.

## License

[MIT](LICENSE)
