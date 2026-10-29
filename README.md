# tools

Two things live in this repository:

1. **`labauto`**: one-command installers for common DevOps tools (`setup.sh` + `devops/`).
2. **RoboShop cluster tooling**: the Minikube cluster, ingress/TLS, platform services and
   observability stack that [roboshop-ai](https://github.com/mrjithendar/roboshop-ai) runs on,
   plus the Argo CD bootstrap/deploy scripts.

## 1. labauto: DevOps tool installers

```bash
curl -s https://raw.githubusercontent.com/mrjithendar/tools/master/setup.sh | bash -s -- terraform
# or install it as a command
git clone https://github.com/mrjithendar/tools.git /tmp/tools
sudo ln -s /tmp/tools/setup.sh /usr/bin/labauto
labauto            # pick from a numbered menu
labauto helm       # install directly by name
```

`setup.sh` clones or updates the repo in `/tmp/tools`, then runs `devops/<tool>.sh`.
Config files the installers copy into place (systemd units, Prometheus/Loki/Promtail
config, Vault policy, …) are in `devops/dependencies/`.

Available tools: alert-manager, argocd, aws-iam-authenticator, awscli, docker,
docker-compose, eks-node-viewer, eksctl, githubcli, gitlab-runner, grafana, helm, jenkins,
k6, k9s, kubectl, letsencrypt, load-gen, loki, mongodb-client, nexus, nexus-ssl,
node_exporter, packer, prometheus, promtail, python, rabbitmq, redis, rs-project-gh,
sonar-qube-docker, sonar-scanner, sonarqube, terraform, trivy, vault.

To add a tool, drop a `devops/<name>.sh` script in; the menu picks it up automatically.

## 2. RoboShop cluster tooling

### Layout

| Path | Contents |
|---|---|
| `minikube/` | Cluster install/reset, kubeconfig, Traefik, shared TLS, cert-manager, namespaces, shared config (`roboshop/`), MongoDB (incl. the catalogue ConfigMap), WordPress, JFrog, Vault, ECR credential refresh. See [minikube/README.md](minikube/README.md). |
| `observability/` | Prometheus, Grafana, Loki/Alloy, OpenTelemetry collector, Jaeger. See [observability/README.md](observability/README.md). |
| `scripts/argocd/` | `bootstrap.py` (install controllers in order), `deploy.py` (register and sync Applications), `validate.py` (render the whole catalog and check ownership). |
| `scripts/setup/` | Host initialization (`initialize.py`, pinned `versions.json`) and Kubernetes secret creation ([SECRETS.md](scripts/setup/SECRETS.md)). |
| `scripts/data/` | `generate-secrets.py` (local credential files), `seed-minikube-demo.py` (opt-in demo data). |
| `scripts/maintenance/` | `delete-branches.sh` (stale Dependabot branches), `squash-history.py` ([notes](scripts/maintenance/squash-history.md)), `reset-test-checkout.py`. |
| `scripts/dev/kubectl.sh` | `kubectl` against the downloaded cluster kubeconfig. |
| `scripts/lib/` | Shared helpers: supported-host check, Argo CD ownership check, repository paths. |
| `tests/` | Tests for the configuration and scripts above. |

### Entry points

All of these resolve paths from their own location, so they can be run from anywhere.
Most accept `--help`.

| Command | Does |
|---|---|
| `./init.sh [--profile dev\|docker\|minikube\|aws] [--check]` | Install host prerequisites (no cluster or cloud changes). |
| `./deploy-minikube.sh` | Create or update the Minikube cluster (`minikube/install.sh`). |
| `./deploy-traefik.sh` | Install Traefik ingress (`minikube/deploy-traefik.sh`). |
| `./patch-ssl.sh` | Configure the shared TLS certificate (`minikube/setup-shared-tls.sh`). |
| `./bootstrap-cluster.sh` | Install cert-manager and Traefik (Helm) in order and refresh ECR pull secrets. |
| `./create-secrets.sh [--apply]` | Create missing installation credentials (never rotates existing ones); previews by default. |
| `./deploy-argocd.sh [app\|all\|roboshop\|list\|status]` | Register and sync Argo CD Applications. |
| `./kubectl.sh ARGS` | `kubectl` with the cluster kubeconfig (`scripts/dev/kubectl.sh`). |

Typical first run on a fresh host:

```bash
./init.sh --profile minikube
./deploy-minikube.sh
./bootstrap-cluster.sh
./create-secrets.sh --apply
./deploy-argocd.sh roboshop
```

### Working with roboshop-ai

The Argo CD catalog (`argocd/`), the microservices and their manifests live in roboshop-ai.
Its Applications point at this repository for `minikube/*` and `observability/*` sources
and Helm `$values`. Clone both side by side; the scripts find roboshop-ai at
`../roboshop-ai`, or at `$ROBOSHOP_AI_DIR`:

```text
Work/
  roboshop-ai/   microservices, service manifests, Argo CD catalog, docs, Terraform
  tools/         this repository
```

Argo CD deploys the **pushed** Git revision, so commit and push changes here before running
`./deploy-argocd.sh`.

The product catalogue ConfigMap (`minikube/mongodb/mongodb-catalog-configmap.yaml`) is
generated from roboshop-ai's `services/mongodb/catalog.js` with `npm run catalog:configmap`
there; `tests/test_mongodb_catalog.py` fails if it is stale.

Operations docs (`docs/operations/scripts.md` and friends) are in roboshop-ai.

### Tests

Needs Python 3.9+ with `pytest` and `PyYAML`, plus a roboshop-ai checkout for the catalog tests.

```bash
python3 scripts/argocd/validate.py          # render every Application from both checkouts
python3 -m pytest -q tests minikube/test-*.py minikube/shared-tls
```

The Vault chart test only runs when given a rendered chart:

```bash
helm template vault vault --repo https://helm.releases.hashicorp.com --version 0.34.1 \
  -f minikube/vault/values.yaml > /tmp/vault.yaml
python3 tests/test_vault_chart.py /tmp/vault.yaml
```
