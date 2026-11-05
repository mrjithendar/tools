# Kong Gateway OSS on mk4 (database mode)

Infrastructure only: Argo CD Application `kong` (`../applications/kong.yaml`, project `mk-gateway`) syncs this
folder by hand, never with prune. Routes, plugins and consumers are **not** here: they live in Kong's PostgreSQL
database and are managed in Kong Manager. Start with [`docs/kong/README.md`](../../../docs/kong/README.md).

| File | What |
|---|---|
| `storageclass-retain.yaml` | `standard-retain`: minikube-hostpath with `Retain` |
| `kong-postgres-*.yaml` | PostgreSQL 17.11 (PVC, init script, Service, StatefulSet pinned to `mk4-m03`) |
| `kong-config.yaml` | Kong settings as `KONG_*` variables |
| `migrations-bootstrap-job.yaml` | `kong migrations bootstrap`, once (why it never re-runs: comments in the file) |
| `kong-deployment.yaml`, `cert-sync.yaml` | Kong 3.9.4 and the certificate upload sidecar |
| `kong-*-service.yaml` | `kong-proxy` (NodePort, public), test, admin, manager, status (ClusterIP) |
| `*-networkpolicy.yaml` | default deny plus the allowed flows |
| `*-certificate.yaml` | cert-manager Certificates for Kong (DNS-01 issuer) |
| `create-secrets.sh` | Secret `kong-postgres`, once, by a person |
| `upgrade/` | `migrations up` / `finish` Job templates, applied by hand during an upgrade; not in the kustomization |

The namespace manifest is `../namespaces/kong.yaml`, like every app in this catalog.
