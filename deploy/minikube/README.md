# Minikube (`mk4`)

The self-hosted cluster: Argo CD hub, Traefik, cert-manager, Kong and the monitoring stack. Every path below is from the repository root. Everything here stays on `mk4`; AWS resources belong in [`../eks`](../eks/).

| Path | Contents | Applied by |
|---|---|---|
| `install.sh`, `kubeconfig.sh`, `expose-ingress.sh`, `tunnel-endpoint.sh`, `host-limits.sh`, `reset.sh` | Cluster lifecycle | Root wrappers or directly |
| [`../../minikube-infrastructure/`](../../minikube-infrastructure/README.md) | Terraform root: Helm releases for metrics-server, cert-manager, Argo CD and Kong, one `.tf` file each | `terraform -chdir=minikube-infrastructure apply` |
| `applications/` | Argo CD catalog: AppProjects, Grafana, Prometheus, Loki, OpenTelemetry Collector, Jaeger | `./deploy-argocd.sh` |
| `observability/` | Prometheus chart, Grafana values and dashboards, Loki and Alloy, OpenTelemetry collector, Jaeger | Argo CD, through `applications/` |
| `argocd/`, `cert-manager/`, `metrics-server/`, `kong/` | Values and the local Kong chart for the Terraform releases; Argo CD's Traefik Ingress | `minikube-infrastructure/`; the Ingress by `./bootstrap-cluster.sh` |
| `traefik/`, `namespaces/` | Traefik values, namespace manifests | `./bootstrap-cluster.sh`, `./deploy-argocd.sh` |
| `vault/`, `jfrog/`, `ecr-refresh/` | Optional components | Their own scripts and READMEs |
| `examples/` | Templates. Nothing applies them. | By hand |

Kustomize stays here: `kubectl apply -k deploy/minikube/argocd` and the catalog in `applications/kustomization.yaml` are part of how this cluster is deployed.

## Prerequisites

Docker, `kubectl` and Helm (`./init.sh --profile minikube`), AWS credentials that can read ECR for pull secrets, and the roboshop-ai and jithendar.com checkouts beside this repository.

## Deploy

```bash
./init.sh --profile minikube
./deploy-minikube.sh                        # create or update the cluster
terraform -chdir=minikube-infrastructure init
terraform -chdir=minikube-infrastructure apply -var-file=vars/mk4.tfvars   # or CI; Kong stays off until its cutover
./bootstrap-cluster.sh --context mk4        # checks those releases; Traefik, Argo CD's ingress, ECR pull secrets
./create-secrets.sh --context mk4 --apply   # missing credentials; never rotates existing ones
./deploy-argocd.sh --context mk4            # align and sync the catalog, without prune
```

## Verify

```bash
./deploy-argocd.sh status --context mk4
kubectl --context mk4 -n argocd get applications.argoproj.io
kubectl --context mk4 -n monitoring get pods,pvc
```

Expected: every app `Synced` and `Healthy`, no warnings from `status`, and every monitoring pod ready.

## Roll back

Revert the commit, push, and run `./deploy-argocd.sh <app> --context mk4`. It aligns the live spec with Git and syncs without prune. Never sync with prune: PVCs here use hostPath volumes that exist only on their node.
