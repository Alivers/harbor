# Native command coverage

Based on the actual CLI help in the official Apple Container 1.5.0 release; all 67 leaf commands have been checked.

The table lists the actions the app provides an entry point for. Not every action has a dedicated form, and listing an action does not mean it has been run against a real runtime. Every action lets you edit the full native arguments, read the local help, choose a working directory and hand off to Terminal.

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
| Kubernetes | Create Cluster (Experimental) | `container k8s create` |
| Kubernetes | Delete Cluster | `container k8s delete` |
| Kubernetes | List Clusters | `container k8s list` |
| Kubernetes | Load Image into Cluster | `container k8s load-image` |
| Kubernetes | Write kubeconfig | `container k8s write-config` |
