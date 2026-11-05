# Kong Gateway OSS on mk4 (database mode)

Infrastructure only: a local Helm chart (`Chart.yaml`, manifests in `templates/`, no values), installed by
Terraform as the release `kong` (`../../../minikube-infrastructure/kong.tf`). Routes, plugins and consumers are **not** here: they live in Kong's PostgreSQL
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
| `upgrade/` | `migrations up` / `finish` Job templates, applied by hand during an upgrade; not in the chart (`.helmignore`) |

Every row but the last two is in `templates/`. The namespace is created by `create-secrets.sh`, which must run before
the first `terraform apply` (the pods need its Secret); `../namespaces/kong.yaml` still lists it for the ECR
pull-secret refresh. Render the chart with `helm template kong deploy/minikube/kong -n kong`.
