# tools

- **[labauto](#labauto)**: one-command installers for DevOps tools (`labauto.sh`, `devops-tools/`).
- **[Cluster tooling](#cluster-tooling)**: the Minikube cluster, ingress/TLS, platform services
  and observability that [roboshop-ai](https://github.com/mrjithendar/roboshop-ai) runs on.

## labauto

```bash
git clone https://github.com/mrjithendar/tools.git
cd tools
sudo ln -s $(pwd)/labauto.sh /usr/bin/labauto

labauto          # numbered menu
labauto helm     # install by name
```

Each run updates `/tmp/tools` and executes `devops-tools/<tool>.sh`. Config files the
installers copy into place (systemd units, Prometheus/Loki/Promtail config, Vault policy) are
in `devops-tools/dependencies/`. To add a tool, add `devops-tools/<name>.sh`; it appears in
the menu automatically.

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
| `minikube/` | Cluster scripts and per-component config: [argocd](minikube/argocd/README.md), [cert-manager](minikube/cert-manager/README.md), [traefik](minikube/traefik/README.md), [vault](minikube/vault/README.md), [jfrog](minikube/jfrog/README.md), [metrics-server](minikube/metrics-server/README.md), [ecr-refresh](minikube/ecr-refresh/README.md), `namespaces/`, and shared RoboShop ingress/config in [roboshop](minikube/roboshop/README.md). |
| `infrastructure/` | Terraform for the lab AWS account: VPC, ECR, SES, Bedrock role, the `roboshop-demo` EKS cluster and its add-ons ([details](infrastructure/README.md)). |
| `eks/` | EKS Applications, RoboShop ingress (AWS Load Balancer Controller, Istio, mTLS) and its [runbook](eks/RUNBOOK.md) ([details](eks/README.md)). |
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

The shop's Argo CD catalog, the microservices, their manifests and the operations docs live in
roboshop-ai; `argocd/` here holds the monitoring stack's catalog. Its Applications read `minikube/*` and
`observability/*` from this repository. The shared jithendar.com certificate, the default
Traefik TLSStore and `patch-ssl.sh` live in
[jithendar.com](https://github.com/mrjithendar/jithendar.com). Clone all three side by side,
or set `ROBOSHOP_AI_DIR` / `JITHENDAR_COM_DIR`:

```text
Work/
  roboshop-ai/
  jithendar.com/
  tools/
```

Argo CD deploys the **pushed** revision of `master`. Commit and push changes here before running
`./deploy-argocd.sh`.

### Tests

Needs Python 3.9+ with `pytest` and `PyYAML`, and the roboshop-ai and jithendar.com checkouts.

```bash
python3 scripts/argocd/validate.py
python3 -m pytest -q tests minikube/test-*.py
```

The Vault chart test runs only against a rendered chart:

```bash
helm template vault vault --repo https://helm.releases.hashicorp.com --version 0.34.1 \
  -f minikube/vault/values.yaml > /tmp/vault.yaml
python3 tests/test_vault_chart.py /tmp/vault.yaml
```

## License

Copyright (c) 2026 Jithendar Dharmapuri. All rights reserved. This is proprietary software; no use, copying, modification or distribution is permitted without written permission. See [LICENSE](LICENSE).
