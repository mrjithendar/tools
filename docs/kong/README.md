# Kong Gateway (database mode) replacing Traefik on mk4 — report

Status on 2026-11-05: **prepared, not deployed.** Nothing was applied, synced, committed or pushed. Whether the
migration works can only be confirmed by you, after deploying and checking traffic (06). Validation that was
possible offline is below; everything else is under "Unverified".

Later on 2026-11-05: Kong is no longer an Argo CD Application. `deploy/minikube/kong` is a local Helm chart (the same
20 manifests, now in `templates/`) installed by Terraform (`minikube-infrastructure/kong.tf`), like
metrics-server, cert-manager and Argo CD. The Application `kong` and AppProject `mk-gateway` were removed. Runbook
steps P7 and 3–5 changed accordingly.

| Document | Contents |
|---|---|
| [00-discovery.md](00-discovery.md) | Traefik inventory, TLS, traffic path, GitOps, secrets, storage, capacity, PostgreSQL |
| [01-compatibility.md](01-compatibility.md) | version evidence with URLs (accessed 2026-11-05) |
| [02-architecture.md](02-architecture.md) | ownership model, persistence, migrations, networking, TLS, behaviour differences |
| [03-admin-access.md](03-admin-access.md) | Kong Manager and Admin API access |
| [04-kong-manager-guide.md](04-kong-manager-guide.md) | Service → Route → Consumer + key-auth → plugins, with curl checks; creating the real logins |
| [05-backup-restore.md](05-backup-restore.md) | pg_dump, reviewed decK export, restore order, upgrades, no HA |
| [06-cutover-runbook.md](06-cutover-runbook.md) | maintenance-window steps, each with a check and a pass criterion |
| [07-rollback-runbook.md](07-rollback-runbook.md) | back to Traefik without touching Kong's data |
| [08-roboshop.md](08-roboshop.md) | RoboShop storefront route, prepared for when RoboShop runs on mk4 |

## Architecture and ownership

```
Cloudflare DNS (DNS only) ─▶ host 46.224.38.14 ─▶ HAProxy (TCP, PROXY v2)
      :80 ─▶ mk4:31080 ┐   :443 ─▶ mk4:31443 ┐   :443 SNI db.jithendar.com ─▶ mk4:31543
                       └──────── Service kong/kong-proxy (NodePort, the only public endpoint)
                                         │
        pod kong: Kong OSS 3.9.4 ─ proxy 8000/8443, stream 9443, Admin 127.0.0.1:8001, Manager 127.0.0.1:8002
                  cert-sync sidecar ─ cert-manager Secrets ─▶ 2 Kong Certificates (fixed ids)
                                         │ 5432
        StatefulSet kong-postgres (postgres:17.11-alpine, mk4-m03) ─ PVC (Retain, Prune=false, Delete=false)
                                         │
        upstreams <svc>.<ns>.svc.cluster.local: jithendar-com, jithendar-db-ui, jithendar-postgres (tcp),
        moks-api, moks-terminal, moks-opensearch(-dashboards), argocd-server, grafana, prometheus, loki
```

| Layer | Owner | Tool |
|---|---|---|
| Namespace, PostgreSQL/Kong workloads, Services, PVC, NetworkPolicies, bootstrap Job, Certificates in `kong` | Git (`tools/deploy/minikube/kong`, local Helm chart) | Terraform release `kong` (`minikube-infrastructure/kong.tf`), by hand |
| Kong Services, Routes, Upstreams, Plugins, Consumers | Kong's database | Kong Manager / Admin API |
| Kong Certificates/SNIs (two, fixed ids) | cert-sync sidecar, exclusively | the only automation that writes Kong entities |
| Initial seed | Git, reference copy (`kong-config/seed/kong.yaml`) | decK, once, by hand |
| Secrets | a person | `create-secrets.sh`, `create-dns01-secret.sh` |

No Kong Ingress Controller: Ingress, HTTPRoute, Traefik and Kong CRDs do nothing. Kubernetes reconciliation and
Kong Manager never manage the same entity. No automatic decK, Admin API or GitOps sync of Kong entities runs.

## Version evidence (details and URLs in 01)

- **Kong Gateway OSS 3.9.4** (2026-10-12), `kong:3.9.4` Docker Official Image, Apache-2.0, amd64 + arm64. No OSS
  release exists after 3.9.x ([releases](https://github.com/Kong/kong/releases),
  [discussion #14405](https://github.com/Kong/kong/discussions/14405)). Kong's lifecycle data marks 3.9 `sunset`,
  EOL 2025-12-12 ([gateway.yml](https://github.com/Kong/developer.konghq.com/blob/main/app/_data/products/gateway.yml)).
- **Kong Manager OSS**: first in 3.4.0 ([CHANGELOG](https://github.com/Kong/kong/blob/3.4.0/CHANGELOG.md)); no
  login, no RBAC; settings from [kong.conf.default 3.9.4](https://github.com/Kong/kong/blob/3.9.4/kong.conf.default).
- **PostgreSQL 17** (Kong 3.9 supports 13–17), `postgres:17.11-alpine`; PG 17 EOL 2029-11-08
  ([versioning](https://www.postgresql.org/support/versioning/)).
- **Helm**: `kong/kong` 3.4.1 evaluated, not used: its bootstrap Job is an Argo CD Sync hook (re-runs every sync)
  and its Bitnami PostgreSQL image is gone ([bitnami#83267](https://github.com/bitnami/containers/issues/83267)).
- **KIC** v3.5.14 still supports DB mode, but would co-own entities; not used.
- **Kubernetes** v1.37.0 on mk4; Kong uses only GA workload APIs. Local kubectl 1.30 is outside the skew policy.

## PostgreSQL persistence and backups

Standalone PVC `kong-postgres-data` (2Gi) with `Prune=false,Delete=false`, StorageClass `standard-retain`
(minikube-hostpath, `Retain`), pod pinned to `mk4-m03`, tuned for 512Mi. Backups: encrypted `pg_dump` outside the
repositories and the Google Drive folder; redacted decK export in Git for review (`kong-config/redact_export.py`).
One instance on one host: **no high availability** (05).

## Secure Manager / Admin API access

Both listen on the pod's loopback only. `kubectl --context mk4 -n kong port-forward deploy/kong 8001:8001 8002:8002`,
then <http://localhost:8002>. `admin_gui_url=http://localhost:8002`, `admin_gui_api_url=http://localhost:8001`, so
CORS allows only that origin. HTTP is acceptable because the tunnel is the API server's TLS and the far end is
loopback. Access control is network isolation plus kubeconfig holders; there is no login (03).

## Seed summary: Traefik → Kong mapping

11 Kong Services, 16 Routes, 1 global plugin, all tagged `seed:v1`. Every Kong route below is HTTPS-only with
`https_redirect_status_code: 301` unless stated, `preserve_host: true`, `strip_path: false`, unbuffered responses.

| Traefik (live 2026-11-05) | Kong route (service) | Paths / match | Plugins | Notes |
|---|---|---|---|---|
| Ingress `jithendar-com` + `-http`; Middlewares `strip-trace-headers`, `compress`, `https-redirect` | `jithendar-com` (`jithendar-com`) | `/` | request-transformer (remove `traceparent`, `tracestate`, `baggage`) | compression → nginx gzip (global); redirect → route attribute |
| Ingress `jithendar-com-www` + `-www-http`; `www-redirect` | `jithendar-com-www-redirect` (`jithendar-com`) | host `www.jithendar.com`, `/`, HTTP + HTTPS | redirect 301 → `https://jithendar.com`, keep path + query | one hop from HTTP, as Traefik |
| Ingress `jithendar-db-ui`; `db-allowlist`, `db-headers` | `jithendar-db-ui` (`jithendar-db-ui`) | `/db/` | service: ip-restriction (2 IPs, 403), response-transformer (5 headers) | |
| Middleware `db-slash` | `jithendar-db-ui-slash` (`jithendar-db-ui`) | `~/db$` | redirect 302 → `/db/` | allowlist runs first |
| IngressRouteTCP `jithendar-db`, TLSOption `db-postgres`, MiddlewareTCP `db-allowlist` | `jithendar-postgres-tls` (`jithendar-postgres`, tcp) | protocol `tls`, SNI `db.jithendar.com` | ip-restriction (tls) | stream listener 9443; ALPN `postgresql` via `nginx_sproxy_ssl_alpn`; HAProxy routes the SNI |
| Ingress `moks` (`/moks`) + `moks-http` | `moks` (`moks-api`) | `~/moks$`, `/moks/` | — | read/write 1 h (SSE) |
| Ingress `moks` (`/moks/api/terminal`) | `moks-terminal` (`moks-terminal`) | `/moks/api/terminal` | — | WebSocket, 1 h |
| IngressRoute `opensearch` (GET/HEAD) + `opensearch-auth`, `opensearch-strip-prefix` | `moks-opensearch-read` (`moks-opensearch`) | GET, HEAD; `~/opensearch$`, `/opensearch/`; strip | service: basic-auth (hide); route: acl `opensearch-readers` | |
| same, POST search | `moks-opensearch-search` (`moks-opensearch`) | POST; `~/opensearch((?:/[^/]+)?/_(?:search\|msearch\|count))$` | acl, request-transformer `replace.uri $(uri_captures[1])` | other methods fall to `/` like Traefik |
| IngressRoute `opensearch-dashboards` + auth | `moks-opensearch-dashboards` | `~/opensearch-dashboards$`, `/opensearch-dashboards/` | basic-auth, acl `opensearch-dashboards-users` | 1 h |
| Ingress `argocd` + `argocd-http`, `argocd-https` | `argocd` (`argocd-server`) | `~/argocd$`, `/argocd/` | — | 1 h (event streams) |
| Ingress `grafana` | `grafana` | `~/grafana$`, `/grafana/` | — | 1 h (Live) |
| Ingress `prometheus` + `prometheus-auth` | `prometheus` | `~/prometheus$`, `/prometheus/` | service: basic-auth; acl `prometheus-readers` | |
| Ingress `prometheus-remote-write` + auth | `prometheus-remote-write` | `~/prometheus/api/v1/write$` | acl `prometheus-remote-write` | regex beats the prefix |
| Ingress `loki-push` + auth | `loki-push` (`loki`) | `~/loki/api/v1/push$` | service: basic-auth; acl `loki-push` | |
| Ingress `loki-read` + auth | `loki-read` (`loki`) | `~/loki/api/v1/(?:query_range\|labels\|format_query)$`, `~/loki/api/v1/label$`, `/loki/api/v1/label/` | acl `loki-read` | |
| (no Traefik route; EKS Istio VirtualService `roboshop`) | `roboshop` + `roboshop-slash` (`roboshop-web`), separate file `kong-config/seed/roboshop.yaml` | `/roboshop/` stripped; `~/roboshop$` | redirect 308 → `/roboshop/` | import only once RoboShop runs on mk4 (08) |
| (none: Traefik overwrote client X-Forwarded-For) | global `pre-function` | rewrite phase | clears client `X-Forwarded-*`, `X-Real-IP`, `Forwarded` | Kong 3.9.4 would otherwise keep a spoofed first entry |

Not seeded: Consumers and credentials (04 "Doing it for real", 05), Certificates (cert-sync).
`tests/test_kong_seed.py` replays 27 Traefik-era requests through a model of Kong's router and checks each lands
on the same backend.

## Resource estimate

Host totals are an assumption (16 vCPU, 30.2 GiB: what each minikube node reports; the host was not reachable).

| Component | CPU req | CPU limit | Mem req | Mem limit |
|---|---|---|---|---|
| Kong | 200m | 1 | 512Mi | 1Gi |
| cert-sync sidecar | 5m | 100m | 24Mi | 64Mi |
| PostgreSQL (incl. 64Mi `/dev/shm`) | 100m | 500m | 256Mi | 512Mi |
| **Kong total (steady)** | **305m** | **1.6** | **792Mi** | **1.56Gi** |
| bootstrap Job (once) / init containers (start-up) | 100m / 50m | 500m | 256Mi / 128Mi | 512Mi |
| Free on mk4 today (00 §7) | ≈11.9 cores | (limits already 1.7× overcommitted) | ≈22.0 GiB | ≈11.1 GiB |
| Traefik (removed after acceptance) | 100m | 500m | 128Mi | 256Mi |

Traefik need not be stopped for capacity; it stays up as the rollback path until 06 step 11.

## Validation run (2026-11-05)

```
## kustomize (kubectl kustomize, built-in Kustomize v5.0.4)
ok tools/deploy/minikube/kong (20 objects)
ok tools/deploy/minikube/applications (10 objects)
ok tools/deploy/minikube/observability/loki (11 objects)
ok jithendar.com manifests.sh site (25 objects) / db-access (5) / practice-executor (21)
## helm lint / template
tools prometheus chart: 1 chart(s) linted, 0 chart(s) failed; template ok
moks chart (values-minikube): 1 chart(s) linted, 0 chart(s) failed; 9 groups render; routing renders 0 objects
kong/kong 3.4.1 (evaluation only): lint ok, template ok
## kubeconform 0.8.0 (-strict, Kubernetes 1.33.0 schemas + datreeio CRDs catalog)
Summary: 162 resources found in 16 files - Valid: 162, Invalid: 0, Errors: 0, Skipped: 0
## yamllint 1.37.1 (38 changed YAML files; line-length 160)
4 findings, all on lines this change did not touch (moks values.yaml 197, 233; values-minikube.yaml 45, missing
final newline at 164 — pre-existing on master)
## bash -n: create-secrets.sh, expose-ingress.sh, create-dns01-secret.sh, enable-db-access.sh ok
## Python: redact_export.py and the cert-sync script compile
## tools: pytest 292 passed, 4 skipped (includes tests/test_kong_seed.py, 51 tests, both seed files)
## roboshop-ai: tests/service-layout.test.mjs 9/9; web kustomization + Kong manifests kubeconform 23/23 valid
## tools: scripts/argocd/validate.py: Validated 7 Applications, 48 unique resources
## moks: tests/test_helm_render.py (--noconftest; conftest needs asyncpg): 63 passed, 3 failed —
   the same 3 terminal tests fail on clean master (test_terminals_are_off_by_default,
   test_a_tag_or_no_profile_is_refused, test_the_terminal_namespace_is_restricted_and_closed_by_default)
## moks: scripts/validate-argocd-split.py: 3 problems, identical to clean master (all EKS terminal)
## jithendar.com: scripts/ci-app-manifests.py selects objects for all three groups
## HAProxy config rendered for both targets (SNI backend only for kong); haproxy -c not run (no Docker here)
```

Not run, and what they would have checked:

| Tool | Why not | Would check |
|---|---|---|
| `deck file validate` / `deck gateway validate` | downloading decK into the scratch folder was blocked by the permission classifier | the seed against decK's schemas, then against Kong 3.9.4's real entity and plugin schemas (regex syntax, plugin fields, `instance_name`) |
| `kubectl --dry-run=client` | kubeconform covered schema checks; local kubectl 1.30 is outside skew | API mapping against the live server |
| `haproxy -c` | Docker daemon not running on this Mac | the generated HAProxy config (the script runs it before switching) |
| standalone `kustomize` | not installed; `kubectl kustomize` (v5.0.4) used | same build with a newer Kustomize |
| Kong locally | no Docker | Kong starting with this configuration, routes, plugins |

## Unverified (only a live deployment can confirm)

1. Kong 3.9.4 accepts the seed as written: regex paths under `traditional_compatible` (Rust regex), the
   unnamed capture used by `replace.uri $(uri_captures[1])`, the stripped path for `/opensearch/…`.
2. `KONG_NGINX_SPROXY_SSL_ALPN=postgresql` takes effect in the stream TLS server, and `psql … sslnegotiation=direct`
   works through Kong.
3. The global pre-function removes client `X-Forwarded-For` before Kong builds its own (read from source, not run).
4. minikube-hostpath honours `reclaimPolicy: Retain` from the StorageClass (06 step 3 checks and patches).
5. kindnet enforces the `kong` NetworkPolicies, and kubelet probes pass under default-deny.
6. HAProxy SNI routing to the stream port; Kong refusing non-PROXY connections on public ports.
7. cert-manager DNS-01 with the new Cloudflare token; cert-sync uploads; renewal reaching Kong without restart.
8. Kong Manager OSS UI labels and the browser CORS flow through port-forward.
9. Argo CD: `ignoreDifferences` keeps the completed Job in sync; selective sync via `operation`; waves.
10. Kong and PostgreSQL sizing under real traffic; timeouts long enough for real SSE/WebSocket sessions; gzip with
    unbuffered streaming responses.
11. `deck gateway dump -o -` writing to stdout; the restore procedure (never drilled).
12. The host's real CPU and memory.

## Branches and changed files (all uncommitted, nothing staged)

**tools** — `feat/kong-db-migration`
- New: `deploy/minikube/kong/` (20 manifests in the kustomization, `upgrade/migrations-{up,finish}-job.yaml`,
  `create-secrets.sh`, `README.md`), `deploy/minikube/namespaces/kong.yaml`,
  `deploy/minikube/applications/{kong,project-gateway}.yaml`, `kong-config/seed/kong.yaml`,
  `kong-config/redact_export.py`, `docs/kong/*` (9 files), `tests/test_kong_seed.py`, `traefik-backup-conf/`
  (22 verbatim copies + 8 cleaned live exports in `live-mk4/`).
- Modified: `deploy/minikube/applications/kustomization.yaml`, `applications/workload-inventory.json`,
  `deploy/minikube/expose-ingress.sh` (explicit `INGRESS_TARGET`, Kong backends, SNI routing),
  `observability/grafana/values.yaml` (Ingress off), `observability/loki/kustomization.yaml`,
  `observability/prometheus/Chart.yaml` (description), `scripts/argocd/validate.py` (StorageClass is
  cluster-scoped), `tests/test_argocd_catalog.py` (7 apps), `tests/test_loki.py` (routes now in the seed).
- Deleted (backed up): Loki's 2 Middlewares + 2 Ingresses, Prometheus's 2 Middleware + 2 Ingress templates.

**moks** — `feat/kong-db-migration`
- Modified: `deploy/helm/moks/values.yaml` (`ingress.controller: traefik` default), `values-minikube.yaml`
  (`controller: external`, `networkPolicy.ingressNamespaces: [kong, traefik]`), `templates/ingress.yaml`,
  `templates/opensearch-dashboards.yaml`, `templates/opensearch-secure-dashboards.yaml` (Traefik objects only when
  `controller: traefik`), `backend/tests/test_helm_render.py` (Traefik-mode tests pinned, mk4 Kong test added),
  `docs/ARGOCD_APP_SPLIT.md`.
- Deleted (backed up): `deploy/argocd/minikube/apps/moks-routing.yaml`.
- New: `traefik-backup-conf/` (8 files).

**jithendar.com** — `feat/kong-db-migration`
- Modified: `minikube/30-jithendar-com.yaml`, `db-access-20-adminer.yaml`, `db-access-30-postgres-tls.yaml`
  (NetworkPolicies admit `kong`; Traefik objects removed), `45-jithendar-letsencrypt.yaml` (DNS-01),
  `kustomization.yaml`, `README.md`, `DB_ACCESS.md`, `scripts/enable-db-access.sh`.
- Deleted (backed up): `minikube/40-middlewares.yaml`, `55-tlsstore.yaml`, `60-ingress.yaml`,
  `db-access-10-allowlist.yaml`.
- New: `scripts/create-dns01-secret.sh`, `traefik-backup-conf/` (14 files).

**roboshop-ai** — `feat/kong-db-migration` (no Traefik resources, so no `traefik-backup-conf/`)
- New: `services/web/web-kong-networkpolicy.yaml` (storefront accepts 8080 from Kong pods only).
- Modified: `services/web/kustomization.yaml` (lists it).

tools, for RoboShop: new `kong-config/seed/roboshop.yaml`, `docs/kong/08-roboshop.md`; `kong-networkpolicy.yaml`
egress to `roboshop-ai` `app=web`:8080; `tests/test_kong_seed.py` covers both seed files (292 tools tests pass).

Merging jithendar.com's branch to `master` triggers its CI deploy (NetworkPolicies only; it never deletes).

## Open questions and decisions for you

1. **Secret mechanism.** mk4 has no Sealed Secrets/SOPS/External Secrets; Secrets are created by scripts and never
   committed. I treated that as the existing mechanism and followed it. Confirm, or say which tool you want.
2. **Kong 3.9 is the last OSS line** and Kong lists it as sunset. Accept that patch releases may stop, and decide
   what you would move to if they do.
3. **Basic-auth passwords.** Traefik's Secrets are htpasswd hashes Kong cannot import. Do you have the plaintexts
   for the six logins? If not, new passwords mean updating their clients (Alloy, remote-write senders, Grafana data
   sources).
4. **Cloudflare token** for DNS-01: create a new, zone-scoped one (recommended) or reuse CI's.
5. **Fresh-cluster path:** `scripts/argocd/bootstrap.py` and `deploy-traefik.sh` still install Traefik and apply
   Argo CD's Traefik Ingress (kept as the rollback path, and its tests assert it). Convert bootstrap to Kong later?
6. `tools/deploy/minikube/jfrog/` and `vault/` Traefik Ingresses (not deployed): delete or port when needed?
7. Accept gzip-only compression (no br/zstd) and the 16 MiB body cap?
8. Enable Kong's `prometheus` plugin and a scrape job for gateway metrics?
9. RoboShop on mk4: the route is ready (08), but running RoboShop there (Argo apps for mk4, no Istio, data
   stores, real client IPs in web's nginx) is a separate project. Want it, and should the 33 stale
   `roboshop-demo-*` Applications be removed?
10. Helm reports `traefik` revision 2 as failed; `argocd`'s pending-install is cleared when Terraform takes over
    Argo CD (`minikube-infrastructure/README.md`, steps 3–4).
