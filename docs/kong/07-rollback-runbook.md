# 07 — Rollback runbook

Goal: traffic back on Traefik, Kong scaled to zero, **no Kong or PostgreSQL data deleted**. Never delete the
`kong` namespace, PVC `kong-postgres-data`, its PV, the `kong` Application with cascade, or the bootstrap Job.

`K="kubectl --context mk4"`.

## Which rollback?

| Situation | Path |
|---|---|
| Before step 11 of 06 (Traefik still installed, its objects still live) | **Fast rollback**: HAProxy switch only |
| After 11.1 (Traefik uninstalled) or 11.2 (Traefik objects deleted) | **Late rollback**: reinstall Traefik and its objects from `traefik-backup-conf/` and Git, then the fast rollback |

## Fast rollback (minutes)

| # | Action | Check | Pass |
|---|---|---|---|
| 1 | Confirm Traefik is serving: `$K -n traefik get deploy traefik`; `$K get ingress -A \| wc -l` | | `1/1`; 15 lines |
| 2 | On the host: `INGRESS_TARGET=traefik bash deploy/minikube/expose-ingress.sh` | `docker exec roboshop-ingress-edge-$(id -u) grep server /usr/local/etc/haproxy/haproxy.cfg` | `mk4:30080`, `mk4:30443`, no 31543 |
| 3 | Verify through Traefik: re-run the baseline loop of 06 step 1 into `~/rollback.txt`; `diff ~/kong-baseline.txt ~/rollback.txt` | | no differences |
| 4 | PostgreSQL TLS: Traefik's TLS route and `db-jithendar-com-tls` in `jithendar` are still live; `psql … sslnegotiation=direct` as in 06 step 8 | | `1` |
| 5 | Scale Kong to zero (keeps PostgreSQL, the PVC and every entity): `$K -n kong scale deploy/kong --replicas=0` | `$K -n kong get deploy kong -o jsonpath='{.spec.replicas}'`; `$K -n kong get pvc kong-postgres-data` | `0`; `Bound` |
| 6 | Optional: keep PostgreSQL running (no traffic) or scale it too: `$K -n kong scale sts/kong-postgres --replicas=0` | `$K get pv \| grep kong-postgres-data` | PV `Bound`/`Released` with `Retain`, never deleted |

Until you retry the cutover, do not change the Kong chart (`deploy/minikube/kong`) and do not apply it: a Helm upgrade
of `kong` would set the replicas back to 1. CI applies on pushes to master, so pause it first:
`gh variable set MINIKUBE_TERRAFORM_APPLY --repo mrjithendar/tools --body false`. Leave `kong_enabled` as it is:
`false` would uninstall the release (PostgreSQL included; the PVC stays).

Why this works without touching the applications: MOKS and jithendar.com NetworkPolicies admit both `traefik` and
`kong` until 06 step 11.3; the ClusterIssuers solve DNS-01, which does not depend on either gateway; Traefik's
Certificates in `jithendar` kept renewing.

## Late rollback (after Traefik was removed)

Restore order matters: controller first, then its objects, then traffic.

| # | Action | Check | Pass |
|---|---|---|---|
| L1 | NetworkPolicies must admit `traefik` again if 11.3 was done: revert that change (MOKS `values-minikube.yaml` to `[kong, traefik]`, sync `moks-foundation` and `moks-opensearch`; jithendar.com's three policies from Git history or `jithendar.com/traefik-backup-conf/minikube/`, applied by CI or `scripts/manifests.sh … \| kubectl apply -f -`) | `$K -n moks get networkpolicy moks -o yaml \| grep -c traefik` | ≥ 1 |
| L2 | Certificates for Traefik in `jithendar`, if 11.5 removed them: `$K apply -f jithendar.com/minikube/50-certificate.yaml` and the Certificate from `jithendar.com/minikube/db-access-30-postgres-tls.yaml` | `$K -n jithendar get certificate` | both `READY True` |
| L3 | Traefik itself, same chart and values as before (kept in Git for this): `bash tools/deploy/minikube/deploy-traefik.sh` (chart 42.0.0, `deploy/minikube/traefik/values.yaml`; copies in `tools/traefik-backup-conf/deploy/minikube/`) | `$K -n traefik rollout status deploy/traefik`; `$K -n traefik get deploy traefik -o jsonpath='{.spec.template.spec.containers[0].args}' \| grep -c proxyProtocol` | rolled out; ≥ 1 |
| L4 | Traefik's objects. From Git backups (verbatim sources): `kubectl apply -f jithendar.com/traefik-backup-conf/minikube/40-middlewares.yaml -f …/55-tlsstore.yaml -f …/60-ingress.yaml -f …/db-access-10-allowlist.yaml`, and the Traefik documents of `…/db-access-20-adminer.yaml` and `…/db-access-30-postgres-tls.yaml`; tools `traefik-backup-conf/deploy/minikube/argocd/` (`kubectl apply -k`), `observability/loki/*-middleware.yaml`, `*-ingress.yaml`; Prometheus's four templates (render with `helm template` from the backed-up chart files, or apply the live copies below). Simplest and complete: the cleaned live exports, `kubectl apply -f tools/traefik-backup-conf/live-mk4/traefik-crs.yaml -f tools/traefik-backup-conf/live-mk4/ingresses.yaml` | `$K get ingress -A \| wc -l`; `$K get middlewares.traefik.io -A \| wc -l` | 15; 17 (16 + header) |
| L5 | MOKS: re-create `moks-routing` from `moks/traefik-backup-conf/deploy/argocd/minikube/apps/moks-routing.yaml` and set `ingress.controller: traefik` in `values-minikube.yaml` on a branch, or keep the objects from L4 unmanaged until you decide | `$K -n moks get ingress,ingressroute` | `moks`, `moks-http`, `opensearch`, `opensearch-dashboards` |
| L6 | Then the fast rollback, steps 2–6 | as above | as above |

The Basic-auth Secrets the Traefik Middlewares reference (`moks-opensearch-auth`, `monitoring-auth`, `loki-*-auth`,
`prometheus-remote-write-auth`, `moks-opensearch-dashboards-auth`) were never touched by this change; if they were
deleted later, recreate them with their original scripts before L4.

## Afterwards

- Kong's database still has every route, consumer and certificate. To try again: fix the cause, `terraform apply
  -var-file=vars/mk4.tfvars` in `minikube-infrastructure` (or `scale deploy/kong --replicas=1`), and resume at 06 step 7.
- To abandon Kong for good, take a final encrypted backup (05) before deleting anything; deleting the PVC keeps the
  PV and directory (`Retain`), which you then remove by hand on `mk4-m03` if you want the space.
