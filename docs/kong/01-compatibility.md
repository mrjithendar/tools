# 01 — Compatibility and version evidence

Every claim below was checked on **2026-11-05** against the source named next to it. Where the source is a file in
a Git repository, the tag is given so the claim can be re-checked.

## Decision summary

| Item | Pinned | Why |
|---|---|---|
| Kong Gateway | **OSS 3.9.4**, image `kong:3.9.4` (Docker Official Image), Apache-2.0 | newest OSS release; nothing newer is published as OSS |
| Kong Manager | Kong Manager OSS, bundled in 3.9.4 | bundled since 3.4.0 |
| PostgreSQL | **17.11**, image `postgres:17.11-alpine` (Docker Official Image) | Kong 3.9 supports 13–17; 17 is the newest supported; same image MOKS already runs on mk4 (arm64) |
| Helm chart | **not used to deploy**; `kong/kong` 3.4.1 evaluated | its bootstrap Job is an Argo CD Sync hook that re-runs on every sync; its PostgreSQL subchart image no longer exists |
| Kong Ingress Controller | **none** | not required; would own entities and fight Kong Manager |
| decK | 1.69.0 (newest), `_format_version: "3.0"` | |

No licensed feature is needed. The one licence-adjacent fact is that Kong's own lifecycle data marks 3.9 as past
end of life for its commercial support (below); there is no OSS line newer than 3.9.

## Kong Gateway OSS availability

| Claim | Evidence | URL |
|---|---|---|
| Newest release is 3.9.4, published 2026-10-12; earlier 3.9.3 (2026-06-17), 3.9.2 (2026-06-04), 3.9.1 (2025-06-04), 3.9.0 (2024-12-13) | GitHub releases API for Kong/kong | https://github.com/Kong/kong/releases |
| No 3.10 or later tag exists in Kong/kong; newest tag is 3.9.4 | GitHub tags API | https://github.com/Kong/kong/tags |
| Kong/kong is Apache License 2.0 | `LICENSE` at tag 3.9.4 | https://github.com/Kong/kong/blob/3.9.4/LICENSE |
| Docker Official Image `kong:3.9.4` exists (pushed 2026-10-27) for `amd64` and `arm64/v8` (mk4 is arm64) | Docker Hub API `library/kong/tags/3.9.4`, digest `sha256:c1f5fbb8…dd5` | https://hub.docker.com/_/kong |
| From 3.10, Kong published no OSS image or release branch; users asked and got no official statement | community reports, not a Kong announcement | https://github.com/Kong/kong/discussions/14405 , https://discuss.konghq.com/t/is-opensource-support-for-kong-ceased/13529 |
| Kong's product data lists 3.9 with `ce-version: "3.9.3"`, `eol: 2025-12-12`, `sunset: true`; it supports `arm` packages and Docker | `app/_data/products/gateway.yml` in Kong's docs repository (commit of 2026-11-04) | https://github.com/Kong/developer.konghq.com/blob/main/app/_data/products/gateway.yml |
| 3.9.4 fixes CVE-2026-1907 (SQL injection in the clustering RPC procedure); 3.9.3 CVE-2026-49975 (nginx header count); 3.9.2 six nginx CVEs | `CHANGELOG.md` on `release/3.9.x` | https://github.com/Kong/kong/blob/release/3.9.x/CHANGELOG.md |

Reading of the evidence: 3.9.x is the last OSS line. Kong still ships OSS patch releases for it (three in 2026),
but its lifecycle data calls 3.9 sunset. **Risk:** security fixes for OSS may stop without notice. Tags other than
`3.9.x`, such as `kong/kong-gateway:3.10+`, are Kong's Enterprise images (free mode or licensed) and are out of
scope by your rule; nothing here uses them.

## Kong Manager OSS

| Claim | Evidence | URL |
|---|---|---|
| First release of Kong Manager Open Source Edition: Kong 3.4.0 | `CHANGELOG.md` at tag 3.4.0, "Kong Manager — First release of the Kong Manager Open Source Edition." | https://github.com/Kong/kong/blob/3.4.0/CHANGELOG.md |
| "only compatible in Kong Gateway 3.4+", "bundled with Kong Gateway", "intended to be a local testing tool", keep 8001/8002 reachable only from your IP | Kong Manager README | https://github.com/Kong/kong-manager |
| `admin_gui_listen` default `0.0.0.0:8002, 0.0.0.0:8445 ssl`; `admin_gui_url` (comma list); `admin_gui_path` default `/`; `admin_gui_api_url` ("when disabled, Kong Manager will use the window protocol + host and append the resolved admin_listen HTTP/HTTPS port") | `kong.conf.default` at 3.9.4 | https://github.com/Kong/kong/blob/3.9.4/kong.conf.default |
| Kong Manager is served only when the Admin API also listens (`#admin_listeners > 0 and #admin_gui_listeners > 0`) | `kong/templates/nginx_kong.lua` at 3.9.4 | https://github.com/Kong/kong/blob/3.9.4/kong/templates/nginx_kong.lua |
| The Admin API's CORS: `Access-Control-Allow-Origin` is the request's Origin only if it is in `admin_gui_origin` (derived from `admin_gui_url`), else the first allowed origin; **with `admin_gui_url` unset it reflects any Origin** and always sends `Access-Control-Allow-Credentials: true` | `kong/api/api_helpers.lua` (`cors_filter`) and `kong/conf_loader/init.lua` at 3.9.4 | https://github.com/Kong/kong/blob/3.9.4/kong/api/api_helpers.lua |
| No authentication in OSS: `kong.conf.default` 3.9.4 has no `admin_gui_auth*` or RBAC settings (those exist only in Enterprise) | absence in `kong.conf.default` 3.9.4 | as above |

Lacking compared with Enterprise: login and admin authentication, and RBAC (verified by their absence from the
OSS configuration). Workspaces, audit logs, Dev Portal and analytics are also Enterprise features in Kong's
product line; that list is from Kong's general documentation and was not re-checked file by file. Only the first
two matter here: access control comes from the network alone (03).

## PostgreSQL

| Claim | Evidence | URL |
|---|---|---|
| Kong 3.9 supports PostgreSQL 17, 16, 15, 14, 13 | `third_party_support` of release "3.9" in Kong's product data (line 777 of the file on 2026-11-05) | https://github.com/Kong/developer.konghq.com/blob/main/app/_data/products/gateway.yml |
| Kong 3.10 LTS lists the same; 3.14/3.15 add 18 | Kong third-party support page (shows 3.10+ only) | https://developer.konghq.com/gateway/third-party-support/ |
| PostgreSQL 17: current minor 17.11, released 2024-09-26, EOL 2029-11-08 | PostgreSQL versioning policy | https://www.postgresql.org/support/versioning/ |
| `postgres:17.11-alpine` exists (pushed 2026-10-26); mk4 already runs it (moks-postgres, arm64) | Docker Hub API; live pod image | https://hub.docker.com/_/postgres |

PostgreSQL 18 is newer but not listed for 3.9, so it is not used.

## Helm chart

| Claim | Evidence | URL |
|---|---|---|
| `kong/kong` 3.4.1 (2026-07-02) is the newest, `appVersion: "3.9"`; depends on Bitnami `postgresql` 11.9.13 | `index.yaml` | https://charts.konghq.com/index.yaml |
| `kong/ingress` 0.24.0 (2026-04-03) wraps `kong` 3.2.0 twice (gateway + controller): it is the KIC bundle | `index.yaml` | as above |
| `kong/kong` 3.4.1 `templates/migrations.yaml` (the bootstrap Job `…-init-migrations`) carries `argocd.argoproj.io/hook: Sync` and `hook-delete-policy: BeforeHookCreation`; so does the pre-upgrade Job | chart source pulled with `helm pull kong --repo https://charts.konghq.com --version 3.4.1` | as above |
| The subchart's image `bitnami/postgresql:14.5.0-debian-11-r35` returns 404 on Docker Hub | Docker Hub API | https://hub.docker.com/r/bitnami/postgresql |
| Bitnami moved its catalog to `bitnamilegacy` (no updates) and limited `docker.io/bitnami` to a small set of `latest` tags from 2025-08-28 | Bitnami announcement | https://github.com/bitnami/containers/issues/83267 |

Decision: an Argo CD Sync hook is recreated and run on **every** sync, which is exactly what you asked to prevent
for `migrations bootstrap`, and the chart cannot drop those annotations (`migrations.jobAnnotations` only adds).
So Kong is deployed with plain manifests (`deploy/minikube/kong/`), the same way this repository deploys Jaeger and
the OpenTelemetry Collector, and the chart served as a reference for settings and probes. `helm lint` and
`helm template` of the chart were run during evaluation.

## Kong Ingress Controller

| Claim | Evidence | URL |
|---|---|---|
| KIC is at v3.5.14 (2026-10-22) and still supports DB-backed gateways (3.4.0 adds a diagnostic endpoint "only supported with Gateways running in DB mode") | KIC `CHANGELOG.md` | https://github.com/Kong/kubernetes-ingress-controller/blob/main/CHANGELOG.md |

KIC is not required for anything here. In DB mode it still reconciles the entities it creates from Kubernetes
objects, so entities edited in Kong Manager would be overwritten or deleted on its next sync; the ownership model
(02) forbids two owners. Not installed.

## Router and plugins (Kong 3.9.4 source)

| Fact used by the seed | File at tag 3.9.4 |
|---|---|
| Default `router_flavor = traditional_compatible`; route priority = matched-field count, then plain-host bit, then regex bit, then `regex_priority`, then longest prefix | `kong.conf.default`, `kong/router/transform.lua` (`get_priority`) |
| Bundled OSS plugins include `redirect`, `acl`, `basic-auth`, `ip-restriction`, `request-transformer`, `response-transformer`, `pre-function`, `request-size-limiting`, `rate-limiting`, `acme`, `prometheus` | `kong/constants.lua` |
| `redirect` plugin: `status_code` (default 301), `location`, `keep_incoming_path`; HTTP protocols only | `kong/plugins/redirect/schema.lua`, `handler.lua` |
| `acme` plugin: HTTP protocols only (`typedefs.protocols_http`), so it cannot provide the `db.jithendar.com` stream certificate | `kong/plugins/acme/schema.lua` |
| `ip-restriction` works on `tcp`/`tls` too | `kong/plugins/ip-restriction/schema.lua` |
| Upstream `X-Forwarded-For` = client header + `, ` + connecting address when the client sent one; forwarded proto/host/port are taken from the client when the connection comes from `trusted_ips` | `kong/runloop/handler.lua` (`access.before`, lines 1228–1350) |
| Global plugins run in the rewrite phase before `access.before` computes those headers | `kong/init.lua` (`Kong.rewrite`, `Kong.access`) |
| `nginx_sproxy_*` directives are injected into the TLS-terminating stream server block | `kong/templates/nginx_kong_stream.lua` |
| `kong migrations list` exits 0 (current), 3 (needs bootstrap), 4 (`finish` pending), 5 (`up` needed); `bootstrap` prints "Database already bootstrapped" and changes nothing when the schema exists; migrations take a database cluster mutex | `kong/cmd/migrations.lua`, `kong/cmd/utils/migrations.lua` |
| Kong Manager server block sets `client_max_body_size 10m` | `kong/templates/nginx_kong.lua` |

## decK

| Claim | Evidence | URL |
|---|---|---|
| decK 1.69.0 is the newest release; darwin build `deck_1.69.0_darwin_all.tar.gz` | GitHub releases API | https://github.com/Kong/deck/releases |
| `_format_version: "3.0"`; `_info.select_tags` limits a sync to entities with all those tags and adds them to entities in the file | decK docs source `app/deck/gateway/tags.md` | https://developer.konghq.com/deck/gateway/tags/ |
| `deck gateway apply` "creates or updates entities … without deleting any existing configuration"; `deck gateway sync` deletes whatever is not in the file | `app/deck/gateway/apply.md`, `sync.md` | https://developer.konghq.com/deck/gateway/apply/ |
| `deck gateway validate` checks against the Admin API and creates nothing; `deck file validate` is offline | `app/deck/gateway/validate.md` | https://developer.konghq.com/deck/gateway/validate/ |
| Custom `_info.defaults` apply to new **and existing** objects | `app/deck/gateway/defaults.md` | https://developer.konghq.com/deck/gateway/defaults/ |

The seed writes every value explicitly instead of using `_info.defaults` because of the last row.

## Kubernetes

| Claim | Evidence | URL |
|---|---|---|
| mk4 runs Kubernetes **v1.37.0** (all five nodes), containerd 2.3.4, arm64 | `kubectl version`, `kubectl get nodes -o wide` | — |
| The local `kubectl` is v1.30.2, outside the supported ±1 minor skew | Kubernetes version skew policy | https://kubernetes.io/releases/version-skew-policy/ |

Kong without KIC uses only GA workload APIs (`apps/v1`, `batch/v1`, `v1`, `networking.k8s.io/v1`,
`storage.k8s.io/v1`, `cert-manager.io/v1`), so there is no Kong-to-Kubernetes version coupling. Use a kubectl
within one minor of 1.37 for the runbook commands.
