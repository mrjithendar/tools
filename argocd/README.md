# Argo CD catalog: monitoring stack

Applications for the shared monitoring stack, whose sources live in this repository under `observability/`:

| Application | Project | Source | Namespace |
|---|---|---|---|
| `grafana` | `platform` | grafana-community chart 14.0.1 + `observability/grafana/values.yaml` + `observability/grafana/dashboards` | `monitoring` |
| `prometheus` | `platform` | `observability/prometheus` (local chart) | `monitoring` |
| `loki` (Loki + Alloy) | `logging` (defined here) | `observability/loki` | `monitoring` |

The `platform` AppProject and every RoboShop application stay in `roboshop-ai/argocd`. `scripts/argocd/deploy.py`
and `validate.py` read both catalogs together (`scripts/lib/repos.py`: `CATALOGS`), so ownership, project and
workload-inventory checks still cover the whole cluster; a name defined in both catalogs is an error.
`workload-inventory.json` lists the workloads these apps must render.

Applications are created or aligned from Git and synced without prune:

```bash
python3 scripts/argocd/deploy.py grafana prometheus loki --context mk4   # aligns live specs with Git, then syncs
python3 scripts/argocd/validate.py --external-charts                     # also run by roboshop-ai's CI daily
```

None of these Applications sync automatically; never sync them with prune.
