# tools

- **[labauto](#labauto)**: one-command installers for DevOps tools (`setup.sh`, `devops/`).
- **[Cluster tooling](#cluster-tooling)**: the Minikube cluster, ingress/TLS, platform services
  and observability that [roboshop-ai](https://github.com/mrjithendar/roboshop-ai) runs on.

## labauto

```bash
git clone https://github.com/mrjithendar/tools.git /tmp/tools
sudo ln -s /tmp/tools/setup.sh /usr/bin/labauto

labauto          # numbered menu
labauto helm     # install by name
```

Each run updates `/tmp/tools` and executes `devops/<tool>.sh`. Config files the installers
copy into place (systemd units, Prometheus/Loki/Promtail config, Vault policy) are in
`devops/dependencies/`. To add a tool, add `devops/<name>.sh`; it appears in the menu
automatically.

## Cluster tooling

### Quick start

```bash
./init.sh --profile minikube     # host prerequisites: Docker, kubectl, Helm, Minikube
./deploy-minikube.sh             # create the cluster
./bootstrap-cluster.sh           # cert-manager, Traefik, Argo CD, ECR pull secrets
./create-secrets.sh --apply      # missing installation credentials
./deploy-argocd.sh roboshop      # register and sync the RoboShop applications
```

Every entry point can run from any directory, and most accept `--help`.

| Command | Does |
|---|---|
| `./init.sh [--profile dev\|docker\|minikube\|aws] [--check]` | Install host prerequisites. No cluster or cloud changes. |
| `./deploy-minikube.sh` | Create or update the Minikube cluster (`minikube/install.sh`). |
| `./bootstrap-cluster.sh` | Install cert-manager and Traefik with Helm, then Argo CD and its ingress; refresh ECR pull secrets. `--schedule-pull-secrets` adds a six-hourly refresh CronJob ([details](minikube/ecr-refresh/README.md)). |
| `./create-secrets.sh [--apply] [--all]` | Create missing installation credentials. Never rotates existing ones. |
| `./deploy-argocd.sh [app\|all\|roboshop\|list\|status]` | Register and sync Argo CD Applications. |
| `./deploy-traefik.sh` | Install or upgrade Traefik on its own (`minikube/deploy-traefik.sh`). |
| `./patch-ssl.sh` | Reuse the ready `jithendar.com` certificate for all Traefik routes ([details](minikube/shared-tls/README.md)). |
| `./kubectl.sh ARGS` | `kubectl` with the downloaded cluster kubeconfig. |

Less common operations in `minikube/`:

| Script | Does |
|---|---|
| `kubeconfig.sh` | Copy the remote cluster's kubeconfig over SSH and validate it. |
| `tunnel-endpoint.sh` | SSH-forward the Kubernetes API when it is not directly reachable. |
| `expose-ingress.sh` | Forward host ports 80/443 to the Minikube ingress. |
| `host-limits.sh` | Raise Linux inotify limits (run automatically by `install.sh`). |
| `deploy-vault.sh` | Install persistent Vault with Helm ([details](minikube/vault/README.md)). |
| `reset.sh` | **Destructive**: delete the Minikube clusters and installer state. Asks for confirmation. |

### Layout

| Path | Contents |
|---|---|
| `minikube/` | Cluster scripts and per-component config: [argocd](minikube/argocd/README.md), [cert-manager](minikube/cert-manager/README.md), [traefik](minikube/traefik/README.md), [shared-tls](minikube/shared-tls/README.md), [vault](minikube/vault/README.md), [jfrog](minikube/jfrog/README.md), [metrics-server](minikube/metrics-server/README.md), [ecr-refresh](minikube/ecr-refresh/README.md), `namespaces/`, and shared RoboShop ingress/config in [roboshop](minikube/roboshop/README.md). |
| `observability/` | Prometheus, Grafana, Loki/Alloy, OpenTelemetry collector, Jaeger. See [observability/README.md](observability/README.md). |
| `scripts/argocd/` | `bootstrap.py`, `deploy.py`, and `validate.py` (renders the whole catalog and checks ownership). |
| `scripts/setup/` | Host initialization (`initialize.py`, pinned `versions.json`) and secrets ([SECRETS.md](scripts/setup/SECRETS.md)). |
| `scripts/data/` | `generate-secrets.py` (local credential files), `seed-minikube-demo.py` (opt-in demo data). |
| `scripts/maintenance/` | `delete-branches.sh` (stale Dependabot branches), `squash-history.py` ([notes](scripts/maintenance/squash-history.md)), `reset-test-checkout.py`. |
| `scripts/lib/` | Shared helpers: supported-host check, Argo CD ownership check, repository paths. |
| `tests/`, `minikube/test-*.py` | Tests for everything above. |

Supported hosts: CentOS Stream 9/10, Amazon Linux 2023, Ubuntu 22.04/24.04, and macOS for
client-side commands. x86_64 and ARM64 only.

### Working with roboshop-ai

The Argo CD catalog (`argocd/`), the microservices, their manifests, Terraform and the
operations docs live in roboshop-ai. Its Applications read `minikube/*` and
`observability/*` from this repository. Clone both side by side, or set `ROBOSHOP_AI_DIR`:

```text
Work/
  roboshop-ai/
  tools/
```

Argo CD deploys the **pushed** revision of `master`. Commit and push changes here before running
`./deploy-argocd.sh`.

### Tests

Needs Python 3.9+ with `pytest` and `PyYAML`, and a roboshop-ai checkout.

```bash
python3 scripts/argocd/validate.py
python3 -m pytest -q tests minikube/test-*.py minikube/shared-tls
```

The Vault chart test runs only against a rendered chart:

```bash
helm template vault vault --repo https://helm.releases.hashicorp.com --version 0.34.1 \
  -f minikube/vault/values.yaml > /tmp/vault.yaml
python3 tests/test_vault_chart.py /tmp/vault.yaml
```
