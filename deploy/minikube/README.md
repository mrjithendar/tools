# Minikube (`mk4`)

The self-hosted cluster: Argo CD hub, Traefik, cert-manager and the monitoring stack. Every path below is from the repository root. Everything here stays on `mk4`; AWS resources belong in [`../eks`](../eks/).

| Path | Contents | Applied by |
|---|---|---|
| `install.sh`, `kubeconfig.sh`, `expose-ingress.sh`, `tunnel-endpoint.sh`, `host-limits.sh`, `reset.sh` | Cluster lifecycle | Root wrappers or directly |
| `applications/` | Argo CD catalog: AppProjects, Grafana, Prometheus, Loki, metrics-server | `./deploy-argocd.sh` |
| `observability/` | Prometheus chart, Grafana values and dashboards, Loki and Alloy, OpenTelemetry collector, Jaeger | Argo CD, through `applications/` |
| `argocd/`, `cert-manager/`, `traefik/`, `metrics-server/`, `namespaces/` | Controller values and manifests | `./bootstrap-cluster.sh`, Argo CD |
| `vault/`, `jfrog/`, `ecr-refresh/` | Optional components | Their own scripts and READMEs |
| `harbor/` | Opt-in private registry ([README](harbor/README.md)) | Argo CD, `applications/optional/harbor.yaml`, by name only |
| `examples/` | Templates. Nothing applies them. | By hand |

Kustomize stays here: `kubectl apply -k deploy/minikube/argocd` and the catalog in `applications/kustomization.yaml` are part of how this cluster is deployed.

## Prerequisites

Docker, `kubectl` and Helm (`./init.sh --profile minikube`), AWS credentials that can read ECR for pull secrets, and the roboshop-ai and jithendar.com checkouts beside this repository.

## Deploy

```bash
./init.sh --profile minikube
./deploy-minikube.sh                        # create or update the cluster
./bootstrap-cluster.sh --context mk4        # cert-manager, Traefik, Argo CD and its ingress, ECR pull secrets
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
