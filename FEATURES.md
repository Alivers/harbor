# Native command coverage

The catalog has 68 leaf commands. The 67 of Apple Container 1.5.0 were checked against the help of its official release; `container commit`, new in 1.6.0, and the 1.6.0 changes below were checked against the upstream 1.6.0 source, not against a running 1.6.0 CLI.

The table lists the actions the app provides an entry point for. Not every action has a dedicated form, and listing an action does not mean it has been run against a real runtime. Dedicated forms or views exist for running, starting, stopping, deleting, logs, stats, inspect, copying files, exporting and committing (containers); pulling, building, tagging, pushing, saving, loading, inspecting, pruning, deleting and loading into a Kubernetes cluster (images); creating networks, volumes and Kubernetes clusters; and updating Apple Container itself. Every action lets you edit the full native arguments, read the local help, choose a working directory and hand off to Terminal.

What 1.6.0 changed, and what Harbor does about it:

- `build` and `builder` are CLI plugins now. Like the Kubernetes plugin, they print their own name in their help (`USAGE: builder start`) and only load while the engine runs, so their command panels verify help once the engine is up.
- `container commit` makes an image from a container's filesystem: **Commit to Image…** in a container's menu, offered when the local CLI has it.
- `--network name,alias=…` gives a container extra DNS names: **DNS Aliases** in the Run Container form, and the aliases in the container's overview.
- `k8s create --workers` and `--cni NONE`, and `k8s load-image --node`: the **Create Cluster** form on the Kubernetes page and **Load into Kubernetes Cluster…** on an image, each option shown when the local help lists it.
- `image list` lists the images it can read and then fails if it skipped any: Harbor shows the readable ones with a warning instead of keeping the old list.
- `machine create --user/--uid/--gid/--home` go through the command panel; the Linux Machines page now says how much less isolated a machine is than a container.

1.6.1 renamed the Kubernetes plugin from `container k8s` to `container cluster` (same subcommands and options; the default cluster is now `cluster-dev`). The catalog uses the new name, and Harbor reads which one the local CLI has once the engine runs, so the Kubernetes page and forms work with either.

| Category | Action | Native command |
| --- | --- | --- |
| Containers | Run Container | `container run` |
| Containers | Create Without Starting | `container create` |
| Containers | Start | `container start` |
| Containers | Stop | `container stop` |
| Containers | Send Signal | `container kill` |
| Containers | Delete | `container delete` |
| Containers | List | `container list` |
| Containers | Exec | `container exec` |
| Containers | Export Filesystem | `container export` |
| Containers | Commit to Image (1.6.0) | `container commit` |
| Containers | Reclaim Filesystem Space | `container clean` |
| Containers | Logs | `container logs` |
| Containers | Inspect | `container inspect` |
| Containers | Stats | `container stats` |
| Containers | Copy Files | `container copy` |
| Containers | Prune Stopped Containers | `container prune` |
| Images | List | `container image list` |
| Images | Pull | `container image pull` |
| Images | Push | `container image push` |
| Images | Save Archive | `container image save` |
| Images | Load Archive | `container image load` |
| Images | Tag | `container image tag` |
| Images | Delete | `container image delete` |
| Images | Prune Unused Images | `container image prune` |
| Images | Inspect | `container image inspect` |
| Build | Build Image | `container build` |
| Build | Start Builder | `container builder start` |
| Build | Builder Status | `container builder status` |
| Build | Stop Builder | `container builder stop` |
| Build | Delete Builder | `container builder delete` |
| Networks | Create Network | `container network create` |
| Networks | Delete Network | `container network delete` |
| Networks | Prune Networks | `container network prune` |
| Networks | List Networks | `container network list` |
| Networks | Inspect Network | `container network inspect` |
| Volumes | Create Volume | `container volume create` |
| Volumes | Delete Volume | `container volume delete` |
| Volumes | Prune Volumes | `container volume prune` |
| Volumes | List Volumes | `container volume list` |
| Volumes | Inspect Volume | `container volume inspect` |
| Registries | Log In | `container registry login` |
| Registries | Log Out | `container registry logout` |
| Registries | List Logins | `container registry list` |
| Linux Machines | Create Machine | `container machine create` |
| Linux Machines | Run / Log In | `container machine run` |
| Linux Machines | List Machines | `container machine list` |
| Linux Machines | Inspect Machine | `container machine inspect` |
| Linux Machines | Change Settings | `container machine set` |
| Linux Machines | Set Default Machine | `container machine set-default` |
| Linux Machines | Machine Logs | `container machine logs` |
| Linux Machines | Stop Machine | `container machine stop` |
| Linux Machines | Delete Machine | `container machine delete` |
| System | Start Engine | `container system start` |
| System | Stop Engine | `container system stop` |
| System | Engine Status | `container system status` |
| System | Version | `container system version` |
| System | Service Logs | `container system logs` |
| System | Disk Usage | `container system df` |
| System | Create DNS Domain (Admin) | `container system dns create` |
| System | Delete DNS Domain (Admin) | `container system dns delete` |
| System | List DNS Domains | `container system dns list` |
| System | Install Recommended Kernel | `container system kernel set` |
| System | System Properties | `container system property list` |
| Kubernetes | Create Cluster (Experimental) | `container cluster create` (`k8s create` before 1.6.1) |
| Kubernetes | Delete Cluster | `container cluster delete` (`k8s delete` before 1.6.1) |
| Kubernetes | List Clusters | `container cluster list` (`k8s list` before 1.6.1) |
| Kubernetes | Load Image into Cluster | `container cluster load-image` (`k8s load-image` before 1.6.1) |
| Kubernetes | Write kubeconfig | `container cluster write-config` (`k8s write-config` before 1.6.1) |
