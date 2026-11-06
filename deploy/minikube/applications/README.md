# Argo CD catalog: observability stack

Applications for the shared observability stack, whose sources live in this repository under `observability/`.
All five are in the AppProject `mk-observability` (`project-observability.yaml`); `metrics-server` stays in `mk-platform`.
`deploy.py` creates a missing project and moves an existing Application to the project Git names, but it does not
update an AppProject that already exists: `kubectl --context mk4 apply -f deploy/minikube/applications/project-observability.yaml`.

| Application | Project | Source | Namespace |
|---|---|---|---|
| `grafana` | `mk-observability` | grafana-community chart 14.0.1 + `deploy/minikube/observability/grafana/values.yaml` + `deploy/minikube/observability/grafana/dashboards` | `monitoring` |
| `prometheus` | `mk-observability` | `deploy/minikube/observability/prometheus` (local chart) | `monitoring` |
| `loki` (Loki + Alloy) | `mk-observability` | `deploy/minikube/observability/loki` | `monitoring` |
| `otel-collector` | `mk-observability` | `deploy/minikube/observability/otel-collector` (Kustomize; also the `roboshop-ai/otel-collector` ExternalName Service) | `observability` |
| `jaeger` | `mk-observability` | `deploy/minikube/observability/jaeger` (Kustomize) | `observability` |

RoboShop runs on EKS: its Applications are in `roboshop-ai/argocd-eks`. `scripts/argocd/deploy.py`
and `validate.py` read both catalogs together (`scripts/lib/repos.py`: `CATALOGS`), so ownership, project and
workload-inventory checks still cover the whole cluster; a name defined in both catalogs is an error.
`workload-inventory.json` lists the workloads these apps must render.

Applications are created or aligned from Git and synced without prune:

```bash
python3 scripts/argocd/deploy.py grafana prometheus loki otel-collector jaeger --context mk4   # aligns live specs with Git, then syncs
python3 scripts/argocd/validate.py --external-charts                     # also run by roboshop-ai's CI daily
```

None of these Applications sync automatically; never sync them with prune.

## Opt-in: `optional/`

`optional/` holds Applications that `deploy.py` offers only by name, never for `all`, and whose workloads are not in
`workload-inventory.json`. `validate.py` checks them with the catalog above.

| Application | Project | Source | Namespace |
|---|---|---|---|
| `harbor` | `mk-registry` (`optional/project-registry.yaml`) | harbor chart 1.19.4 + `deploy/minikube/harbor/values.yaml` + `deploy/minikube/harbor/manifests` | `harbor` |

```bash
python3 scripts/argocd/deploy.py harbor --context mk4   # prerequisites first: deploy/minikube/harbor/README.md
```
