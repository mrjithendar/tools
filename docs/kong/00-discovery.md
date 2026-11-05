# 00 — Discovery (read-only, 2026-11-05)

Sources: the four repositories on `master` (all clean at the start), and read-only `kubectl --context mk4` and
`helm --kube-context mk4` queries. Exports of the live objects, cleaned of cluster-generated fields, are in
`traefik-backup-conf/live-mk4/`. Assumptions are marked **[A]**.

## 1. Traefik inventory

Traefik v3.7.14 (Helm chart `traefik` 42.0.0), one replica in namespace `traefik`, Service `traefik` of type
NodePort. Gateway API is not installed (no `HTTPRoute`, no `Gateway`). No `ServersTransport`,
`TraefikService`, `IngressRouteUDP` or `ServersTransportTCP` exists.

### Entrypoints (from the live Deployment's arguments)

| Entrypoint | Container port | NodePort | Notes |
|---|---|---|---|
| `web` | 8000 | 30080 | PROXY protocol trusted from `192.168.49.0/24` |
| `websecure` | 8443 | 30443 | `http.tls=true`, PROXY protocol trusted from `192.168.49.0/24` |
| `traefik` | 8080 | — | dashboard disabled (`ingressRoute.dashboard.enabled: false`) |
| `metrics` | 9100 | — | Prometheus metrics |

Traefik accepts connections without a PROXY header too ("connections without it are still accepted",
`deploy/minikube/traefik/values.yaml`). Kong's PROXY-protocol listeners do not (see 02, Networking).

### HTTP routes

Host is `jithendar.com` unless stated. "HTTPS only" means the route is on `websecure`; plain HTTP to that path
falls to the site's `jithendar-com-http` router and gets a 301 to HTTPS.

| # | Object (namespace/name) | Owner (Git) | Match | Backend Service:port | Middlewares / behaviour |
|---|---|---|---|---|---|
| 1 | Ingress `jithendar/jithendar-com` | jithendar.com `minikube/60-ingress.yaml` | `/` Prefix, HTTPS | `jithendar-com.jithendar:80` (pod 3000) | `strip-trace-headers` (removes `traceparent`, `tracestate`, `baggage`), `compress` (zstd, br, gzip; text types; ≥1024 B); TLS secret `jithendar-com-tls` |
| 2 | Ingress `jithendar/jithendar-com-http` | same | `/` Prefix, HTTP | same | `https-redirect` (redirectScheme https, permanent) |
| 3 | Ingress `jithendar/jithendar-com-www` | same | host `www.jithendar.com`, `/`, HTTPS | same | `www-redirect`: regex `^https?://www\.jithendar\.com/(.*)` → `https://jithendar.com/${1}`, permanent |
| 4 | Ingress `jithendar/jithendar-com-www-http` | same | host `www.jithendar.com`, `/`, HTTP | same | `www-redirect` |
| 5 | Ingress `jithendar/jithendar-db-ui` | jithendar.com `minikube/db-access-20-adminer.yaml` | `/db` Prefix, HTTPS | `jithendar-db-ui.jithendar:80` (pod 8080) | `db-allowlist` (ipAllowList `122.177.247.138/32`, `46.224.38.14/32`), `db-slash` (regex `^https://jithendar\.com/db$` → `/db/`, **302**), `db-headers` (nosniff, frame DENY, `Referrer-Policy: no-referrer`, `Cache-Control: no-store`, `X-Robots-Tag: noindex, nofollow`) |
| 6 | Ingress `moks/moks` | moks `deploy/helm/moks/templates/ingress.yaml` (Argo app `moks-routing`) | `/moks/api/terminal` Prefix, `/moks` Prefix, HTTPS | `moks-terminal.moks:8080`, `moks-api.moks:8080` | no stripping; no compression (SSE); WebSocket on the terminal path; TLS from TLSStore default |
| 7 | Ingress `moks/moks-http` | same | `/moks` Prefix, HTTP | `moks-api.moks:8080` | `moks/https-redirect` (permanent) |
| 8 | IngressRoute `moks/opensearch` | same | `Path(/opensearch) \|\| PathPrefix(/opensearch/)` and (GET, HEAD, or POST matching `^/opensearch(/[^/]+)?/_(search\|msearch\|count)$`), websecure | `moks-opensearch.moks:9200` | `opensearch-auth` (basicAuth, Secret `moks-opensearch-auth`, removeHeader), `opensearch-strip-prefix` (`/opensearch`). Other methods fall through to route 1 |
| 9 | IngressRoute `moks/opensearch-dashboards` | moks `templates/opensearch-dashboards.yaml` | `Path(/opensearch-dashboards) \|\| PathPrefix(/opensearch-dashboards/)`, websecure | `moks-opensearch-dashboards.moks:5601` | `opensearch-dashboards-auth` (basicAuth, Secret `moks-opensearch-dashboards-auth`, removeHeader); no stripping |
| 10 | Ingress `argocd/argocd` | tools `deploy/minikube/argocd/argocd-ingress.yaml` (applied by `scripts/argocd/bootstrap.py`) | `/argocd` Prefix, HTTPS | `argocd-server.argocd:80` (pod 8080) | Argo CD `server.rootpath=/argocd`, `server.insecure=true`; no stripping |
| 11 | Ingress `argocd/argocd-http` | tools `argocd-http-ingress.yaml` | `/argocd` Prefix, HTTP | same | `argocd-https` (permanent) |
| 12 | Ingress `monitoring/grafana` | tools `observability/grafana/values.yaml` (Argo app `grafana`) | `/grafana` Prefix, HTTPS | `grafana.monitoring:80` (pod 3000) | Grafana serves the sub-path itself; WebSockets (Grafana Live) |
| 13 | Ingress `monitoring/prometheus` | tools `observability/prometheus/templates/prometheus-ingress.yaml` (Argo app `prometheus`) | `/prometheus` Prefix, HTTPS | `prometheus.monitoring:9090` | `prometheus-auth` (basicAuth, Secret `monitoring-auth`, removeHeader) |
| 14 | Ingress `monitoring/prometheus-remote-write` | tools `…/prometheus-remote-write-ingress.yaml` | `/prometheus/api/v1/write` Exact, HTTPS | same | `prometheus-remote-write-auth` (Secret `prometheus-remote-write-auth`) |
| 15 | Ingress `monitoring/loki-push` | tools `observability/loki/loki-push-ingress.yaml` (Argo app `loki`) | `/loki/api/v1/push` Exact, HTTPS | `loki.monitoring:3100` | `loki-push-auth` (Secret `loki-push-auth`) |
| 16 | Ingress `monitoring/loki-read` | tools `…/loki-read-ingress.yaml` | Exact `/loki/api/v1/query_range`, `/labels`, `/format_query`; Prefix `/loki/api/v1/label`, HTTPS | same | `loki-read-auth` (Secret `loki-read-auth`) |

### TCP route

| Object | Owner | Match | Backend | Behaviour |
|---|---|---|---|---|
| IngressRouteTCP `jithendar/jithendar-db` | jithendar.com `minikube/db-access-30-postgres-tls.yaml` | `HostSNI(db.jithendar.com)` on websecure (port 443, shared with HTTPS) | `jithendar-postgres.jithendar:5432` | TLS terminated with Secret `db-jithendar-com-tls`; TLSOption `db-postgres` (ALPN `postgresql`, min TLS 1.2, for libpq `sslnegotiation=direct`); MiddlewareTCP `db-allowlist` (same two IPs) |

### Other Traefik objects

- TLSStore `jithendar/default`: default certificate `jithendar-com-tls` for every route without its own secret
  (routes 6–16).
- Middlewares listed above, plus the identical `jithendar/https-redirect`.

### Request policies across all routes

| Policy | Where | Value |
|---|---|---|
| Redirects | 2, 4, 7, 11 (HTTP→HTTPS, 301); 3, 4 (www→apex, 301); 5 (`/db`→`/db/`, 302) | |
| Rewrites / strip prefix | 8 only (`/opensearch`) | |
| Basic auth | 8, 9, 13, 14, 15, 16 (six Secrets, htpasswd format) | |
| IP allowlist | 5 and the TCP route | `122.177.247.138/32`, `46.224.38.14/32` |
| Forward auth | none | |
| Header changes | 1 (request), 5 (response) | |
| Rate limits | none in Traefik (the site rate-limits in its own code) | |
| Timeouts | none configured; Traefik defaults apply | |
| Body-size limits | none in Traefik. Applications: jithendar.com server actions 11 MB (`www/next.config.ts`), MOKS knowledge upload 2,000,000 bytes (`backend/moks/config.py`) | |
| WebSocket | `/moks/api/terminal` (terminal gateway), `/grafana` (Live) | |
| SSE / streaming | `/moks/.../investigations/{id}/events` (`text/event-stream`, `X-Accel-Buffering: no`), Argo CD event streams, Next.js streaming responses | |
| Compression | route 1 only | |

Not live, but in Git: `tools/deploy/minikube/jfrog/*` and `vault/*` Ingresses (no `jfrog`/`vault` namespace on
mk4). roboshop-ai has no mk4 route: RoboShop's routing was Istio on the `roboshop-demo` EKS cluster, deleted
2026-11-02; the 33 `roboshop-demo-*` Argo CD Applications still point at that cluster.

## 2. TLS today

- **Issuer:** cert-manager (CRDs since 2026-10-26) with ClusterIssuers `letsencrypt-prod` and `letsencrypt-staging`
  (jithendar.com `minikube/45-jithendar-letsencrypt.yaml`), ACME **HTTP-01 through Traefik**
  (`ingressClassName: traefik`). No Traefik ACME resolver, no Cloudflare proxy certificates.
- **Certificates:** `jithendar/jithendar-com` (apex + www → Secret `jithendar-com-tls`) and
  `jithendar/db-jithendar-com` (→ `db-jithendar-com-tls`). The served certificate on 2026-11-05: Let's Encrypt
  `YR2`, `CN=jithendar.com`, SAN apex + www, valid 2026-10-27 to 2027-01-25.
- **Termination:** in Traefik (websecure). HAProxy forwards TCP and never sees keys.
- **Renewal:** cert-manager renews at two thirds of the lifetime (about 2026-12-26 for the current certificate).
  HTTP-01 needs a working Traefik Ingress for `/.well-known/acme-challenge/`, so **renewal breaks when Traefik is
  removed** unless the solver changes. That is why this branch moves the issuers to DNS-01 (02, TLS).

## 3. External traffic path

```
Browser ──DNS (Cloudflare, "DNS only": A jithendar.com, www, db → 46.224.38.14)──▶ host 46.224.38.14
  ──▶ HAProxy container roboshop-ingress-edge-<uid> (haproxy:3.2-alpine, TCP mode, host ports 80/443)
        send-proxy-v2 ──▶ mk4:30080 / mk4:30443 (NodePort, kube-proxy) ──▶ Traefik pod
```

- Configured by `tools/deploy/minikube/expose-ingress.sh`, run on the host. Cloudflare does not proxy (no orange
  cloud), so Cloudflare is not a TLS terminator here.
- **What must point at Kong at cutover:** only HAProxy's backends (`expose-ingress.sh INGRESS_TARGET=kong`). DNS
  does not change.
- The host is described as Hetzner in `jithendar.com/minikube/DB_ACCESS.md` and as Vultr in the tools scripts'
  messages. **[A]** It is one Linux host running Docker; SSH as root from this Mac was refused, so nothing on the
  host was inspected.

## 4. GitOps layout

| Component | Deployed by | Sync policy |
|---|---|---|
| Traefik | Helm release `traefik` from `tools/deploy/minikube/deploy-traefik.sh` (not Argo CD). Revision 2 (2026-11-04) is in state **failed** in Helm's history, although the running pod has the PROXY-protocol arguments | n/a (manual script) |
| Argo CD | Helm release `argocd` (argo-cd 10.10.5), state `pending-install` in Helm's history | n/a |
| jithendar.com routes | `.github/workflows/deploy-minikube.yml` on push to `master` when `MINIKUBE_DEPLOY=true`: server-side dry run, diff, apply, **never deletes**. ClusterIssuers and TLSStore are applied by a person (`./deploy.sh`) | push-triggered apply, no prune |
| MOKS routes | Argo CD `moks-routing` (child of `moks-root`), annotation `Prune=false,Delete=false` | manual, no automated sync, no self-heal, no prune |
| tools routes (Loki, Prometheus, Grafana) | Argo CD `loki`, `prometheus`, `grafana` | manual, no automated sync, no self-heal; `FailOnSharedResource`, `PruneLast`, `CreateNamespace` |
| Argo CD's own Ingress | `scripts/argocd/bootstrap.py` (`kubectl apply -k deploy/minikube/argocd`) | manual |

No Application on mk4 has `automated`, `prune` or `selfHeal` set (checked live).

## 5. Secret management

No Sealed Secrets, SOPS, External Secrets or Vault CRDs exist on mk4 (`tools/deploy/minikube/deploy-vault.sh`
exists, but there is no `vault` namespace). The mechanism in use is **Secrets created by a person with
per-repository scripts, never committed**: `jithendar.com/scripts/create-secrets.sh`, tools `credentials.py`,
MOKS's secret scripts; every AppProject blacklists `Secret`. This change follows the same mechanism
(`deploy/minikube/kong/create-secrets.sh`, `jithendar.com/scripts/create-dns01-secret.sh`). **Open question:**
confirm this counts as the mechanism you meant (README, Open questions).

## 6. Storage

| StorageClass | Provisioner | Reclaim | Binding | Expansion |
|---|---|---|---|---|
| `standard` (default) | `k8s.io/minikube-hostpath` | **Delete** | Immediate | no |

hostPath volumes have no node affinity; existing databases pin their pods (`jithendar-postgres` → `mk4-m03`,
`moks-postgres` → `mk4-m04`). Two PVs were switched to `Retain` by hand (`moks/data-moks-postgres-0`,
`monitoring/grafana`). The tools validator already requires a `kubernetes.io/hostname` nodeSelector on any workload
with a PVC, and `Prune=false,Delete=false` on PVCs.

## 7. Capacity

All five nodes are Docker containers on one host, and each reports the same allocatable resources: **16 CPU,
31689856Ki (≈30.2 GiB)**. **[A]** These are the host's totals, seen five times, not five machines: the host has
about 16 vCPU and 30 GiB. Kubernetes does not know this and would schedule up to 80 CPU of requests.

| Node | CPU requests | CPU limits | Memory requests | Memory limits | CPU used | Memory used |
|---|---|---|---|---|---|---|
| mk4 (control plane) | 975m | 900m | 412Mi | 732Mi | 274m | 2049Mi |
| mk4-m02 | 790m | 6850m | 3218Mi | 6322Mi | 139m | 3387Mi |
| mk4-m03 | 670m | 5100m | 1170Mi | 3122Mi | 112m | 1599Mi |
| mk4-m04 | 750m | 5600m | 1842Mi | 4658Mi | 126m | 2894Mi |
| mk4-m05 | 940m | 8350m | 1746Mi | 4786Mi | 167m | 2109Mi |
| **Total** | **4125m** | **26800m** | **8388Mi** | **19620Mi** | **818m** | **12038Mi** |

Free headroom against the host **[A: 16 vCPU, 30.2 GiB]**: CPU requests 11.9 cores, used 15.2 cores free; memory
requests ≈22.0 GiB, limits ≈11.1 GiB, used (`kubectl top`, includes per-node overhead) ≈18.4 GiB free. CPU
limits are already overcommitted 1.7× against the host. Traefik itself requests 100m/128Mi (limits 500m/256Mi).

## 8. Existing PostgreSQL

| Instance | Namespace | Purpose | Why Kong does not share it |
|---|---|---|---|
| `jithendar-postgres` (StatefulSet, PV reclaim Delete) | jithendar | the site's data | It is published to the internet at `db.jithendar.com`, through the very gateway Kong would be. Kong's database holds credentials and keys; a site restore or schema change must never touch the gateway |
| `moks-postgres` (PV Retain) | moks | MOKS | MOKS owns its schema, backups and restore runbooks; a MOKS restore would roll back the gateway |
| `shipping-postgres` | roboshop-ai | stale RoboShop data | unused workload namespace |

Decision: the default, a **dedicated** instance (`kong/kong-postgres`).
