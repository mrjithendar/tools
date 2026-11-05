# 06 — Cutover runbook (maintenance window)

Every step has a **check** and a **pass** criterion. Stop at the first failure and use 07 (rollback). Nothing in this
branch has been deployed; you run every command. `K="kubectl --context mk4"` throughout; use a kubectl within one
minor of the cluster's 1.37.

Downtime: none expected until step 7 (traffic switch), then the seconds HAProxy takes to restart. Traefik keeps
running until step 11, so rollback before then is a HAProxy switch.

## Before the window (days ahead)

Argo CD Applications track `master`, and jithendar.com's CI applies `minikube/` on push to `master`. The branches
must therefore be merged before their parts can be applied (Kong itself is applied with Terraform from your checkout). Each merge is safe on its own: nothing on mk4 prunes or
deletes, so Traefik's live objects stay and keep serving.

| # | Action | Check | Pass |
|---|---|---|---|
| P1 | Cloudflare token (Zone:DNS:Edit, Zone:Zone:Read, zone jithendar.com), then `jithendar.com/scripts/create-dns01-secret.sh` | `$K -n cert-manager get secret cloudflare-api-token -o jsonpath='{.data.api-token}' \| wc -c` | > 0 |
| P2 | Merge jithendar.com `feat/kong-db-migration`; CI applies the NetworkPolicies (now admitting `kong` too). Apply the ClusterIssuers by hand: `cd jithendar.com && kubectl --context mk4 apply -f minikube/45-jithendar-letsencrypt.yaml` | `$K get clusterissuer letsencrypt-prod -o jsonpath='{.status.conditions[0].type}={.status.conditions[0].status} {.spec.acme.solvers[0].dns01.cloudflare.apiTokenSecretRef.name}'` | `Ready=True cloudflare-api-token` |
| P3 | Prove DNS-01 before relying on it: force one renewal with cert-manager's CLI (`brew install cmctl`): `cmctl renew --context mk4 -n jithendar jithendar-com` | `$K -n jithendar get certificate jithendar-com -o jsonpath='{.status.conditions[?(@.type=="Ready")].status} {.status.renewalTime}'`; `$K get challenges -A` | `True`, a new renewal time; no stuck challenges; site still serves a valid certificate |
| P4 | Merge moks `feat/kong-db-migration`; sync `moks-root`, `moks-foundation`, `moks-opensearch` **without prune** | `$K -n moks get networkpolicy moks -o jsonpath='{.spec.ingress[*].from[*].namespaceSelector.matchLabels}'` | lists both `kong` and `traefik`; `moks-routing` still exists (`$K -n argocd get application moks-routing`) |
| P5 | Merge tools `feat/kong-db-migration`. Do **not** sync `loki`, `prometheus`, `grafana` yet (harmless, but keep changes small) | `git -C tools log -1 origin/master --oneline` | contains the merge |
| P6 | `bash tools/deploy/minikube/kong/create-secrets.sh` | `$K -n kong get secret kong-postgres -o jsonpath='{.data}' \| python3 -c 'import json,sys; print(sorted(json.load(sys.stdin)))'` | `['kong-password', 'superuser-password']` |
| P7 | Move metrics-server, cert-manager and Argo CD to Terraform: `tools/minikube-infrastructure/README.md`, steps 1–6. Kong is not installed yet | `helm --kube-context mk4 list -A` | `metrics-server`, `cert-manager`, `argocd` `deployed`; no `kong` |

## In the window

Steps 3–5 are one Helm release, `kong` (`tools/minikube-infrastructure/kong.tf`), off until `kong_enabled = true`. Helm creates all of its objects
at once; the pods keep the order: the bootstrap Job's init container waits for PostgreSQL, and Kong's init container
waits for the bootstrapped schema. At step 3, set `kong_enabled = true` in `tools/minikube-infrastructure/vars/mk4.tfvars` and
start the apply in a second terminal (it waits up to 15 minutes for everything to be ready), then work through the
checks of 3, 4 and 5 in order. If a check fails, stop there. Push the tfvars change afterwards, so CI agrees with the
cluster; if `MINIKUBE_TERRAFORM_APPLY` is on, pushing it instead of applying by hand also works (Actions shows
progress).

```bash
terraform -chdir=tools/minikube-infrastructure apply -var-file=vars/mk4.tfvars
```

### 1. Pre-checks and backups

| Check | Pass |
|---|---|
| Baseline through Traefik, saved for comparison: `for u in / /moks /db /opensearch /opensearch-dashboards/ /argocd /grafana/ /prometheus/ /loki/api/v1/labels; do printf '%s %s\n' "$u" "$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' https://jithendar.com$u)"; done \| tee ~/kong-baseline.txt` | the codes you expect today (200/30x/401/403) |
| `$K -n traefik get deploy traefik` and `$K get ingress -A \| wc -l` | Traefik 1/1; 15 lines (14 Ingresses + header) |
| Traefik objects backed up: `ls tools/traefik-backup-conf/live-mk4/` | 8 files present |
| Backups of the application databases you would not want to lose if something goes wrong (jithendar's own procedure; MOKS `moks backup`) | completed |
| Capacity: `$K top nodes` | no node above 80 % memory |
| Certificates in `kong` can be issued (step 5 needs them): nothing to check yet | — |

### 2. Stop Traefik?

**Not required, and not done.** Kong + PostgreSQL add 305m CPU and 792Mi memory of requests (limits 1.6 CPU,
1.6 GiB) against ≈11.9 cores and ≈22 GiB of request headroom and ≈11.1 GiB of memory-limit headroom (00 §7,
assumed 16 vCPU / 30.2 GiB host). Traefik uses 100m/128Mi. Kong's NodePorts (31080/31443/31543) do not collide
with Traefik's (30080/30443). Keeping Traefik up makes rollback a HAProxy switch until step 11.

### 3. Start PostgreSQL

Start the `terraform apply` above.

| Check | Pass |
|---|---|
| `$K -n kong rollout status sts/kong-postgres --timeout=300s` | `rolled out` |
| `$K -n kong exec kong-postgres-0 -c postgres -- pg_isready -U postgres` | `accepting connections` |
| `$K -n kong exec kong-postgres-0 -c postgres -- psql -U postgres -Atc "select rolname from pg_roles where rolname='kong'; select datname from pg_database where datname='kong'"` | `kong` twice |
| `$K get pv $($K -n kong get pvc kong-postgres-data -o jsonpath='{.spec.volumeName}') -o jsonpath='{.spec.persistentVolumeReclaimPolicy}'` | `Retain`. If it says `Delete` (the provisioner ignored the class), patch it: `$K patch pv <name> -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'` |
| `$K -n kong get pod kong-postgres-0 -o jsonpath='{.spec.nodeName}'` | `mk4-m03` |

### 4. Run the migration Job

Created by the same apply; nothing to run.

| Check | Pass |
|---|---|
| `$K -n kong wait --for=condition=complete job/kong-migrations-bootstrap-3-9-4 --timeout=600s` | `condition met` |
| `$K -n kong logs job/kong-migrations-bootstrap-3-9-4 -c bootstrap \| tail -3` | `Database is up-to-date` / `… migrations processed` |
| Re-apply proof (the Job must not run again), after the apply has finished: run the same `terraform apply` again, then `$K -n kong get job kong-migrations-bootstrap-3-9-4 -o jsonpath='{.metadata.creationTimestamp} {.status.succeeded}'` | `No changes`; same creation time as before, `1` |

### 5. Start Kong

Started by the same apply. Wait for it to finish without errors.

| Check | Pass |
|---|---|
| `$K -n kong rollout status deploy/kong --timeout=300s` | `successfully rolled out` |
| `$K -n kong exec deploy/kong -c kong -- kong health` | `Kong is healthy` |
| `$K -n kong get certificate` | both `READY True` (DNS-01, can take a few minutes) |
| `$K -n kong logs deploy/kong -c cert-sync \| tail -2` | `uploaded for jithendar.com,www.jithendar.com -> HTTP 200` and the same for `db.jithendar.com` |
| `helm --kube-context mk4 -n kong status kong \| grep STATUS`; the apply's last line | `STATUS: deployed`; `Apply complete!` |
| Admin API not on the network. From `monitoring` (allowed to reach Kong's status port only): `IP=$($K -n kong get pod -l app.kubernetes.io/name=kong -o jsonpath='{.items[0].status.podIP}'); $K -n monitoring run probe --rm -i --restart=Never --image=busybox:1.37 -- sh -c "wget -T 3 -qO- http://$IP:8007/status >/dev/null && echo status-ok; wget -T 3 -qO- http://$IP:8001/status && echo ADMIN-REACHABLE \|\| echo admin-closed"` | `status-ok` then `admin-closed`. Without `status-ok` the probe itself was blocked and the test says nothing |

### 6. Import the seed (decK)

Tunnel open (`$K -n kong port-forward deploy/kong 8001:8001 8002:8002`, 03).

```bash
cd tools/kong-config/seed
deck file validate kong.yaml                                        # offline schema check
deck gateway validate --kong-addr http://localhost:8001 kong.yaml   # against Kong 3.9.4's schemas; creates nothing
deck gateway diff     --kong-addr http://localhost:8001 kong.yaml   # read it: only creations, 11 services, 16 routes, plugins
deck gateway apply    --kong-addr http://localhost:8001 kong.yaml   # creates/updates, never deletes
deck gateway diff     --kong-addr http://localhost:8001 kong.yaml   # second diff
```

| Check | Pass |
|---|---|
| validate | no errors |
| the first diff | creations only (`creating service …`, `creating route …`, `creating plugin …`), no `deleting` |
| the second diff | `Summary: Created: 0 Updated: 0 Deleted: 0` |
| `curl -s 'http://localhost:8001/routes?tags=seed:v1&size=100' \| python3 -c 'import json,sys; print(len(json.load(sys.stdin)["data"]))'` | `16` |
| `curl -s http://localhost:8001/certificates \| python3 -c 'import json,sys; print([c["snis"] for c in json.load(sys.stdin)["data"]])'` | the two cert-sync certificates are still there |

`apply` is used because Kong is not empty after step 5 (cert-sync's certificates exist); `sync` would be scoped
to `seed:v1` and would not touch them either, but `apply` cannot delete anything at all. After this step,
`deck gateway sync` against the live gateway is forbidden except for a deliberate restore (05).

Then create the basic-auth Consumers (04, "Doing it for real") and take the first backup and reviewed export (05).

Test through Kong **before** switching (plain test listener, real hostnames):

```bash
$K -n kong port-forward deploy/kong 8543:8543 &
for u in / /moks /db/ /opensearch /argocd /grafana/ /prometheus/ /loki/api/v1/labels; do
  printf '%s %s\n' "$u" "$(curl -sk --resolve jithendar.com:8543:127.0.0.1 -o /dev/null -w '%{http_code} %{redirect_url}' https://jithendar.com:8543$u)"; done
```

Pass: the same codes as `~/kong-baseline.txt`, except `/db/` (403 here: the test client is `127.0.0.1`, not an
allowlisted address).

### 7. Switch external traffic

On the host, from the tools checkout that contains this branch:

```bash
INGRESS_TARGET=kong bash deploy/minikube/expose-ingress.sh
```

The script refuses unless Kong is rolled out, accepts the PROXY protocol, is healthy and has the seeded
`jithendar-com` route; it checks the HAProxy configuration (`haproxy -c`) before restarting the container.

| Check | Pass |
|---|---|
| `docker exec roboshop-ingress-edge-$(id -u) cat /usr/local/etc/haproxy/haproxy.cfg \| grep server` (on the host) | `mk4:31080`, `mk4:31443`, `mk4:31543` |
| `curl -sI https://jithendar.com/ \| head -1` (from the Mac) | `HTTP/2 200` |
| `$K -n kong logs deploy/kong -c kong --since=1m \| tail -3` | requests with your **public** IP, not `192.168.49.x` |

### 8. Verify each application

| What | Command (from the Mac) | Pass |
|---|---|---|
| Site | `curl -s -o /dev/null -w '%{http_code}\n' https://jithendar.com/` | `200` |
| HTTP→HTTPS | `curl -s -o /dev/null -w '%{http_code} %{redirect_url}\n' http://jithendar.com/blog` | `301 https://jithendar.com/blog` |
| www → apex, path and query kept | `curl -s -o /dev/null -w '%{http_code} %{redirect_url}\n' 'http://www.jithendar.com/blog?x=1'` and the same with `https://` | `301 https://jithendar.com/blog?x=1` both |
| TLS certificate | `echo \| openssl s_client -connect jithendar.com:443 -servername jithendar.com 2>/dev/null \| openssl x509 -noout -issuer -enddate -ext subjectAltName` | Let's Encrypt, `jithendar.com, www.jithendar.com`, future end date; same for `-servername www.jithendar.com` |
| Compression | `curl -s -H 'Accept-Encoding: gzip' -D - -o /dev/null https://jithendar.com/ \| grep -i content-encoding` | `gzip` |
| Trace headers stripped, real IP | `curl -s -H 'traceparent: 00-0123456789abcdef0123456789abcdef-0123456789abcdef-01' -H 'X-Forwarded-For: 1.2.3.4' https://jithendar.com/ -o /dev/null`, then the site's log line for that request (`$K -n jithendar logs deploy/jithendar-com --since=1m \| tail`) | trace id is not `0123…`; client IP is your public IP, not `1.2.3.4` |
| Upload (body size) | sign in and save a post with an image of a few MB (server action, limit 11 MB in the app) | saves; a 20 MB body gets `413` from Kong |
| MOKS | `curl -s -o /dev/null -w '%{http_code} %{redirect_url}\n' http://jithendar.com/moks` then open https://jithendar.com/moks | `301 https://…/moks`; UI loads, sign-in works |
| SSE | start an investigation in MOKS and watch the live stream; or `curl -sN --cookie <FROM-BROWSER> https://jithendar.com/moks/api/investigations/<id>/events \| head` | events arrive as they happen, not in one burst at the end |
| WebSocket | open a MOKS terminal session; idle 5 minutes; type | shell responds; no disconnect |
| `/moksfoo` not MOKS | `curl -s -o /dev/null -w '%{http_code}\n' https://jithendar.com/moksfoo` | the site's 404 page |
| OpenSearch read-only | `curl -s -o /dev/null -w '%{http_code}\n' https://jithendar.com/opensearch`; with `-u <user>:<FROM-PASSWORD-MANAGER>`; `-X DELETE …/opensearch/x` with the login | `401`; `200`; site's 404/405 (never OpenSearch) |
| OpenSearch search POST | `curl -s -u <user>:<FROM-PASSWORD-MANAGER> -X POST -H 'Content-Type: application/json' -d '{"size":0}' https://jithendar.com/opensearch/_search` | JSON with `hits` |
| Dashboards | open https://jithendar.com/opensearch-dashboards/ | login prompt, then the app |
| Argo CD | https://jithendar.com/argocd/ ; `argocd login jithendar.com --grpc-web --grpc-web-root-path /argocd` | UI and CLI work, application list updates live |
| Grafana | https://jithendar.com/grafana/ | dashboards load; live panels update |
| Prometheus | `curl -s -o /dev/null -w '%{http_code}\n' https://jithendar.com/prometheus/graph` with and without the reader login; remote-write login on `/prometheus/graph` | `401` / `200` / `403` |
| Loki | push and read logins on their own paths and on each other's | own path not `401`/`403`; other path `403` |
| Adminer | from an allowlisted IP: https://jithendar.com/db → `/db/`; from a phone off Wi-Fi | `302` then login form; `403` |
| PostgreSQL TLS | `psql "host=db.jithendar.com port=443 dbname=jithendar user=jithendar_remote sslmode=verify-full sslrootcert=system sslnegotiation=direct" -c 'select 1'` from an allowlisted IP; from elsewhere | `1`; connection closed |
| Metrics | `$K -n monitoring logs deploy/alloy --since=5m \| grep -ci error` | no new push errors to `/loki/api/v1/push` |

### 9. Persistence

```bash
$K -n kong delete pod kong-postgres-0 && $K -n kong rollout status sts/kong-postgres --timeout=300s
$K -n kong rollout restart deploy/kong && $K -n kong rollout status deploy/kong --timeout=300s
```

| Check | Pass |
|---|---|
| `curl -s 'http://localhost:8001/routes?tags=seed:v1&size=100' \| python3 -c 'import json,sys; print(len(json.load(sys.stdin)["data"]))'` (tunnel reopened) | `16` |
| `curl -s http://localhost:8001/consumers \| python3 -c 'import json,sys; print(len(json.load(sys.stdin)["data"]))'` | the number you created |
| `curl -s -o /dev/null -w '%{http_code}\n' https://jithendar.com/` | `200` |
| Pod on the same node: `$K -n kong get pod kong-postgres-0 -o jsonpath='{.spec.nodeName}'` | `mk4-m03` |

### 10. Kong Manager access

| Check | Pass |
|---|---|
| Tunnel open, http://localhost:8002 | overview shows 3.9.4, database `postgres`; Gateway Services lists 11 |
| `curl -s -H 'Origin: https://evil.example' -D - -o /dev/null http://localhost:8001/status \| grep -i access-control-allow-origin` | `http://localhost:8002`, not the evil origin |
| From outside: `curl -m 5 http://46.224.38.14:8001/` and `:8002` | connection refused / timeout |

### 11. After acceptance (a later day, once you have confirmed traffic)

| # | Action | Check | Pass |
|---|---|---|---|
| 11.1 | `helm --kube-context mk4 -n traefik uninstall traefik` | `$K -n traefik get pods` | none |
| 11.2 | Delete the Traefik routing objects left live (no controller reads them now): the Ingresses and Traefik CRs listed in `traefik-backup-conf/live-mk4/`, the `moks-routing` Application (`$K -n argocd delete application moks-routing`; it has no finalizer, so its objects stay; delete them with the same list) | `$K get ingress -A`; `$K get middlewares.traefik.io,ingressroutes.traefik.io,ingressroutetcps.traefik.io -A` | none |
| 11.3 | Remove `traefik` from NetworkPolicies: MOKS `values-minikube.yaml` `ingressNamespaces: [kong]`; jithendar.com the three policies | rendered policies | only `kong` |
| 11.4 | Sync `loki`, `prometheus`, `grafana` (no prune) so their live specs match Git | `$K -n argocd get application loki prometheus grafana` | `Synced` |
| 11.5 | Retire the `jithendar/jithendar-com` and `jithendar/db-jithendar-com` Certificates (Kong uses its own in `kong`), and the `traefik` namespace and CRDs, when you no longer want a fast rollback | — | — |
| 11.6 | Decide the open questions in README (bootstrap.py, jfrog/vault ingresses) | — | — |

From 11.1 on, rollback means reinstalling Traefik (07, "late rollback").
