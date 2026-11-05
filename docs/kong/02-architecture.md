# 02 — Architecture and ownership

Standalone Kong Gateway OSS 3.9.4 in database mode, backed by its own PostgreSQL 17, with **no Kong Ingress
Controller**. Evidence for every version: 01-compatibility.md.

```
                          Cloudflare DNS (DNS only) → 46.224.38.14
                                          │
                     host: HAProxy (TCP, send-proxy-v2), ports 80 / 443
              ┌───────────────┬───────────┴───────────────┐
           :80 → mk4:31080   :443, any SNI → mk4:31443   :443, SNI db.jithendar.com → mk4:31543
              └───────────────┴───────────┬───────────────┘
                     Service kong/kong-proxy (NodePort)   ← the only public endpoint
                                          │
        ┌─────────────────────── pod kong (namespace kong) ───────────────────────┐
        │ container kong 3.9.4                                                     │
        │   proxy 8000 (PROXY), 8443 (TLS, PROXY), stream 9443 (TLS, PROXY)        │
        │   test 8180 / 8543 (no PROXY; port-forward only)   status 8007           │
        │   Admin API 127.0.0.1:8001   Kong Manager 127.0.0.1:8002  (loopback)     │
        │ container cert-sync  → PUT /certificates/{2 fixed ids} on 127.0.0.1:8001 │
        │   mounts Secrets jithendar-com-tls, db-jithendar-com-tls (cert-manager)  │
        └──────────────┬───────────────────────────────────────────────────────────┘
                       │ 5432 (NetworkPolicy: Kong + migration Jobs only)
            StatefulSet kong-postgres (postgres:17.11-alpine, node mk4-m03)
            PVC kong-postgres-data → StorageClass standard-retain (Retain)

  Upstreams: jithendar-com, jithendar-db-ui, jithendar-postgres (tcp), moks-api, moks-terminal,
             moks-opensearch, moks-opensearch-dashboards, argocd-server, grafana, prometheus, loki
             (+ web.roboshop-ai, prepared in kong-config/seed/roboshop.yaml; RoboShop does not run on mk4 yet)
             — all <svc>.<ns>.svc.cluster.local

  Operator (Mac) ── kubectl port-forward 8001, 8002 ──▶ loopback of the Kong pod ──▶ browser: Kong Manager
```

## Ownership model

| Layer | Owner | Tool |
|---|---|---|
| Namespace `kong`, StorageClass `standard-retain`, PostgreSQL StatefulSet/Service/PVC/init ConfigMap, Kong Deployment/ConfigMap/Services, NetworkPolicies, bootstrap Job, cert-manager Certificates in `kong` | Git (`tools/deploy/minikube/kong`, a local Helm chart: the manifests in `templates/`; namespace created by `create-secrets.sh`) | Terraform Helm release `kong` (`tools/minikube-infrastructure/kong.tf`), applied by a person |
| Secrets `kong/kong-postgres`, `cert-manager/cloudflare-api-token` | a person | `create-secrets.sh`, `jithendar.com/scripts/create-dns01-secret.sh` |
| Kong Services, Routes, Upstreams, Plugins, Consumers, credentials | **Kong's database** | Kong Manager / Admin API |
| Kong Certificates `2bc41d85-…7345` (jithendar.com, www) and `81abe1c9-…be1` (db.jithendar.com) with their SNIs | **cert-sync sidecar only** | `cert-sync.yaml` |
| Initial entity seed | Git, **reference copy only** (`kong-config/seed/kong.yaml`) | decK, run once by hand |
| Upgrade migrations (`up`, `finish`) | a person, during an upgrade | `deploy/minikube/kong/upgrade/*.yaml` |

Rules:

1. **With no controller present, Kubernetes `Ingress`, `HTTPRoute`, Traefik CRDs (`IngressRoute`, `Middleware`,
   …) and Kong CRDs (`KongPlugin`, `KongConsumer`, …) do nothing.** Nothing reads them. Creating one changes no
   traffic. The release installs no Kong CRDs.
2. **Kubernetes reconciliation and Kong Manager never manage the same entity.** The Helm release manages
   Kubernetes objects; it cannot see Kong entities. The only automation that writes Kong entities is cert-sync, and it owns
   exactly two Certificates by id (tag `managed-by:cert-sync`). Do not edit those two in Kong Manager.
3. **No automatic decK, Admin API or GitOps sync of Kong entities may run.** No CronJob, CI job, Helm or Argo CD hook or
   controller runs decK. The seed is imported once by a person (06, step 6). After that, `deck gateway sync`
   against the live gateway is forbidden except during a deliberate restore (05). Git keeps reviewed exports
   (`deck gateway dump`, 05), which are records, not desired state.

What this means day to day: a route change is made in Kong Manager, takes effect immediately, and is not in Git
until you export it. Rolling back a route is done in Kong Manager or from a backup, not with `git revert`.

## Why no KIC, no Helm chart, no DB-less

- KIC would translate Kubernetes objects into Kong entities and keep them in line, which is exactly the second
  owner rule 2 forbids, and it is not needed to proxy (01).
- DB-less mode has no Admin API writes, so Kong Manager would be read-only, which defeats the goal.
- The upstream `kong/kong` chart's bootstrap Job is an Argo CD Sync hook that runs on every sync, and its
  PostgreSQL subchart image no longer exists (01). Terraform installs the reviewed manifests instead, unchanged, as
  the local chart `deploy/minikube/kong` (no values, no templating).

## PostgreSQL persistence

| Layer | Protects against |
|---|---|
| PVC `kong-postgres-data` is a standalone object with `helm.sh/resource-policy: keep` (so is the StorageClass) | `helm uninstall` / `terraform destroy` deleting it with the release |
| StorageClass `standard-retain` (`k8s.io/minikube-hostpath`, `reclaimPolicy: Retain`) | `kubectl delete pvc` removing the PV and its directory |
| `nodeSelector: kubernetes.io/hostname: mk4-m03` | the pod starting on another node with an empty hostPath directory (minikube hostPath PVs have no node affinity) |
| Data under `PGDATA=/var/lib/postgresql/data/pgdata`, an init container hands the directory to uid 70 | permission failures on hostPath (same pattern as `moks-postgres`) |
| Namespace `kong` created by `create-secrets.sh`, not by the release (`create_namespace = false`) | the release ever owning (and deleting) the namespace |

Not protected: losing the mk4-m03 node container or the host disk. One PostgreSQL on one minikube host has **no
high availability** (05).

Tuning for the 512Mi limit: `shared_buffers=128MB`, `effective_cache_size=320MB`, `work_mem=4MB`,
`maintenance_work_mem=32MB`, `max_connections=40`, `huge_pages=off`, `/dev/shm` 64Mi in memory. Kong runs one
worker with a small connection pool, well under 40 connections.

## Migrations

- **Bootstrap, once:** Job `kong-migrations-bootstrap-3-9-4`, an ordinary resource of the release. Helm creates
  everything at once; order comes from the pods: the Job's init container waits for PostgreSQL, Kong's init
  container waits for the bootstrapped schema.
  - Not a Helm hook, so Helm creates it once and leaves it alone while its manifest is unchanged. A completed Job
    is not re-run by `terraform apply`.
  - No `ttlSecondsAfterFinished`: a garbage-collected Job would be recreated by the next upgrade.
  - The name carries the version; a later version never reuses it.
  - Kong itself: `bootstrap` takes the database cluster mutex and is a no-op on an initialised schema. `--force`
    (which resets) is never used.
- **Kong waits:** the Deployment's init container loops on `kong migrations list` and lets Kong start only on
  exit 0 (current) or 4 (`finish` pending, the normal state during an upgrade).
- **Upgrades:** `kong migrations up` (Job template `upgrade/migrations-up-job.yaml`), roll Kong to the new image,
  then `kong migrations finish` (`upgrade/migrations-finish-job.yaml`). Both are applied by hand with the version
  substituted, never by Argo CD. Steps in 05.

## Networking

- Public: only `Service kong/kong-proxy` (NodePort 31080, 31443, 31543). The ports differ from Traefik's
  30080/30443, so both can run during the cutover and rollback is a HAProxy switch.
- **PROXY protocol is required** on 8000, 8443 and 9443 (nginx rejects a connection without the header, unlike
  Traefik). `trusted_ips=192.168.49.0/24` (the minikube Docker network, as for Traefik), `real_ip_header=proxy_protocol`.
  Ports 8180/8543 accept plain connections, for `kubectl port-forward` tests only (ClusterIP Service
  `kong-proxy-test`, no NetworkPolicy allow).
- **Forwarded headers:** Kong 3.9.4 appends to a client's `X-Forwarded-For` and trusts client `X-Forwarded-*`
  from `trusted_ips`. Because every connection comes from HAProxy's network, a visitor could choose the first
  `X-Forwarded-For` entry, which jithendar.com logs and rate-limits on. The seed's global `pre-function` removes
  client-sent `X-Forwarded-*`, `X-Real-IP` and `Forwarded` in the rewrite phase, before Kong computes its own.
- **Admin API and Kong Manager** listen on `127.0.0.1` inside the pod. `kubectl port-forward` reaches the pod's
  loopback; no Service, pod or node can. ClusterIP Services `kong-admin`/`kong-manager` exist only as
  port-forward names. TLS on 8444/8445 is off (03 explains why HTTP over the tunnel is acceptable here).
- **NetworkPolicy:** default deny in `kong`; Kong ingress only on 8000/8443/9443 (and 8007 from `monitoring`);
  Kong egress to DNS, PostgreSQL and the listed upstream ports; PostgreSQL ingress only from Kong and the
  migration Jobs. mk4's kindnet (v20260820) **does enforce NetworkPolicy**: jithendar.com recorded a blocked flow
  on 2026-11-02 (`jithendar.com/minikube/practice-executor-50-networkpolicies.yaml`). MOKS's docs still call it
  unproven; the kong policies were not exercised live (README, Unverified).
- **Upstream NetworkPolicies** in `jithendar` and `moks` admitted only `kubernetes.io/metadata.name: traefik`.
  They now admit `kong` as well. `traefik` stays until the cutover is accepted so that rollback needs no
  application change.

## TLS without a controller

Kong cannot read cert-manager Secrets. Options considered:

| Option | Verdict |
|---|---|
| Terminate before Kong at Cloudflare | Rejected: the zone is DNS only today; proxying would change every client's path, put Cloudflare in front of `db.jithendar.com` (which Cloudflare's proxy does not carry on 443 as raw TCP) and is a bigger change than the gateway swap |
| Kong `acme` plugin with `kong` storage | Rejected as the only mechanism: HTTP protocols only (01), so `db.jithendar.com` (a TLS stream route) would still need another source; certificates and the ACME account key would live in the gateway database |
| **cert-manager + narrowly scoped upload** | **Chosen** |

How it works:

1. cert-manager issues `kong/jithendar-com-tls` (apex + www) and `kong/db-jithendar-com-tls`
   (`deploy/minikube/kong/*-certificate.yaml`) from the existing ClusterIssuer `letsencrypt-prod`.
2. The issuers move from HTTP-01 (which created Traefik Ingresses for each challenge) to **DNS-01 through
   Cloudflare** (`jithendar.com/minikube/45-jithendar-letsencrypt.yaml`), so issuance and renewal no longer
   depend on any gateway. Same issuer names and ACME account keys. Needs the token Secret first.
3. The `cert-sync` sidecar in the Kong pod mounts both Secrets read-only, and every 5 minutes PUTs the pair to
   two Kong Certificates with fixed ids and their SNIs, only when the certificate text changed. It is the **only
   automation allowed to write Kong entities**, owns Certificates/SNIs exclusively, and uses the loopback Admin
   API, so it needs no RBAC, no Kubernetes token and no network path.
4. **Renewal:** cert-manager renews ~30 days before expiry → the kubelet refreshes the mounted Secret files
   (about a minute) → cert-sync uploads within 5 minutes → Kong serves the new certificate without a restart.

The Traefik-era Certificates in `jithendar` stay (they renew through DNS-01 too) until the cutover is accepted,
because a Traefik rollback needs `jithendar-com-tls` and `db-jithendar-com-tls` there. Requests without SNI get
Kong's built-in default certificate (Traefik served `jithendar-com-tls`); every browser and libpq sends SNI.

## Behaviour differences from Traefik

| Area | Traefik | Kong | Effect |
|---|---|---|---|
| Compression | zstd, br, gzip, jithendar.com only | gzip, all proxied responses of the listed types (nginx OSS has no br/zstd) | slightly larger text responses for jithendar.com; Prometheus/Loki/Argo JSON now compressed too; SSE never |
| Body size | no limit | 16 MiB (`nginx_http_client_max_body_size`) | larger uploads get 413 |
| Timeouts | Traefik defaults, no response timeout | connect 10 s; read/write 300 s, 1 h for MOKS, terminal, Dashboards, Argo CD, Grafana and the PostgreSQL stream | a single response that stays silent longer than that is cut |
| Connections without PROXY header | accepted | refused on public ports | anything that skipped HAProxy stops working; use 8180/8543 for tests |
| Gateway headers | none added | none (`headers=off`, `headers_upstream=off`) | same |
| No-SNI clients | site certificate | Kong default certificate | none expected |
| Basic auth | one htpasswd Secret per route | Consumers with basic-auth credentials + an ACL group per route | credentials must be re-created (04, 05); until then those routes answer 401 |
