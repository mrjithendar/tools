# 04 — Kong Manager OSS walkthrough

A first exercise: a Gateway Service, a Route, a Consumer with a key-auth credential, then plugins. It uses a
made-up host, `kong-demo.test`, which has no public DNS, so nothing you do here can affect a live site. The
backend is Kong's own read-only Status API on the pod's loopback (`127.0.0.1:8007/status`), so no other workload
is touched and no NetworkPolicy change is needed.

Menu names are those of Kong Manager OSS 3.9 and may differ slightly. Every step has an Admin API equivalent and
a `curl` check.

## Before you start

```bash
# Terminal 1: Kong Manager and the Admin API (03-admin-access.md)
kubectl --context mk4 -n kong port-forward deploy/kong 8001:8001 8002:8002
# Terminal 2: Kong's plain test proxy port (no PROXY protocol needed)
kubectl --context mk4 -n kong port-forward deploy/kong 8180:8180
```

Open <http://localhost:8002>. The overview page shows the node, its version (3.9.4) and the database (postgres).

## 1. Gateway Service

Kong Manager → **Gateway Services** → **New gateway service**:

| Field | Value |
|---|---|
| Name | `demo-status` |
| Full URL | `http://127.0.0.1:8007/status` |
| Tags | `demo` |

Save. Admin API equivalent:

```bash
curl -s -X POST http://localhost:8001/services --data name=demo-status \
  --data url=http://127.0.0.1:8007/status --data tags[]=demo
```

**Verify:** `curl -s http://localhost:8001/services/demo-status | python3 -m json.tool` shows `host 127.0.0.1`,
`port 8007`, `path /status`. A Service alone receives no traffic.

## 2. Route

Open the service → **Routes** → **New route**:

| Field | Value |
|---|---|
| Name | `demo-status` |
| Protocols | `http` |
| Hosts | `kong-demo.test` |
| Paths | `/demo` |
| Strip path | on |
| Tags | `demo` |

Admin API: `curl -s -X POST http://localhost:8001/services/demo-status/routes --data name=demo-status
--data protocols[]=http --data hosts[]=kong-demo.test --data paths[]=/demo --data strip_path=true --data tags[]=demo`

**Verify** (the change is live immediately, no reload):

```bash
curl -s -H 'Host: kong-demo.test' http://localhost:8180/demo | python3 -m json.tool | head
# 200 with {"database": {"reachable": true}, "server": {...}}
curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: other.test' http://localhost:8180/demo
# 404 {"message":"no Route matched with those values"}
```

## 3. Consumer with a key-auth credential

**Consumers** → **New consumer**: Username `demo-user`, Tags `demo`. Then open it → **Credentials** →
**Key Authentication** → **New key auth credential**. Leave Key empty so Kong generates one, and copy it from the
page into a shell variable without saving it anywhere:

```bash
read -r -s DEMO_KEY   # paste the generated key, Enter
```

Admin API: `curl -s -X POST http://localhost:8001/consumers --data username=demo-user --data tags[]=demo` and
`curl -s -X POST http://localhost:8001/consumers/demo-user/key-auth` (the response contains the generated key;
treat it as a secret).

**Verify:** `curl -s http://localhost:8001/consumers/demo-user/key-auth | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["data"]), "credential")'`
prints `1 credential`. The route is still open: a credential does nothing until a plugin asks for it.

## 4. Plugins

### 4a. key-auth on the route

Route `demo-status` → **Plugins** → **New plugin** → **Key Authentication**. Key names `apikey`, Hide
credentials on. Admin API: `curl -s -X POST http://localhost:8001/routes/demo-status/plugins --data name=key-auth
--data config.key_names[]=apikey --data config.hide_credentials=true --data tags[]=demo`

**Verify:**

```bash
curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: kong-demo.test' http://localhost:8180/demo                     # 401
curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: kong-demo.test' -H "apikey: $DEMO_KEY" http://localhost:8180/demo # 200
```

### 4b. rate-limiting

Same route → **New plugin** → **Rate Limiting**: Minute `5`, Policy `local`, Limit by `consumer`. Admin API:
`curl -s -X POST http://localhost:8001/routes/demo-status/plugins --data name=rate-limiting --data config.minute=5
--data config.policy=local --data config.limit_by=consumer --data tags[]=demo`

`local` keeps counters in the node's memory; correct here because there is one Kong node with one worker.

**Verify:**

```bash
for i in 1 2 3 4 5 6 7; do
  curl -s -o /dev/null -w '%{http_code} ' -H 'Host: kong-demo.test' -H "apikey: $DEMO_KEY" http://localhost:8180/demo
done; echo   # 200 200 200 200 200 429 429
curl -sI -H 'Host: kong-demo.test' -H "apikey: $DEMO_KEY" http://localhost:8180/demo | grep -i ratelimit
# RateLimit-Limit: 5, RateLimit-Remaining: …, X-RateLimit-Limit-Minute: 5
```

## 5. See it persist, then clean up

```bash
kubectl --context mk4 -n kong rollout restart deploy/kong && kubectl --context mk4 -n kong rollout status deploy/kong
# re-run the port-forwards, then:
curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: kong-demo.test' -H "apikey: $DEMO_KEY" http://localhost:8180/demo  # 200: it lives in PostgreSQL
```

Delete in reverse order (Kong Manager → each entity → Delete, or):

```bash
curl -s -X DELETE http://localhost:8001/routes/demo-status      # also deletes the route's plugins
curl -s -X DELETE http://localhost:8001/services/demo-status
curl -s -X DELETE http://localhost:8001/consumers/demo-user      # also deletes its credentials
unset DEMO_KEY
curl -s 'http://localhost:8001/services?tags=demo' # {"data":[],...}
```

## Doing it for real: the basic-auth logins

The seed routes for OpenSearch, OpenSearch Dashboards, Prometheus and Loki answer 401 until their Consumers
exist. For each row, create a Consumer, a **Basic Authentication** credential (username and password from your
password manager or the source the old Traefik Secret was made from; never written to a file) and an **ACL**
group membership (Consumer → Credentials → ACL):

| Consumer (suggested) | ACL group | Route(s) it opens | Old Traefik Secret |
|---|---|---|---|
| `opensearch-reader` | `opensearch-readers` | `/opensearch` (GET/HEAD, POST search) | `moks/moks-opensearch-auth` |
| `opensearch-dashboards-user` | `opensearch-dashboards-users` | `/opensearch-dashboards` | `moks/moks-opensearch-dashboards-auth` |
| `prometheus-reader` | `prometheus-readers` | `/prometheus` | `monitoring/monitoring-auth` |
| `prometheus-remote-writer` | `prometheus-remote-write` | `/prometheus/api/v1/write` | `monitoring/prometheus-remote-write-auth` |
| `loki-pusher` | `loki-push` | `/loki/api/v1/push` | `monitoring/loki-push-auth` |
| `loki-reader` | `loki-read` | Loki read API | `monitoring/loki-read-auth` |

Traefik's Secrets hold htpasswd hashes, which Kong cannot import: Kong needs the plaintext once to store its own
salted hash. If a password is lost, create a new one and update the client that uses it. Clients that already send
these logins (Alloy, remote-write senders, Grafana data sources) keep working only if the Kong credential has the
same username and password.

Admin API pattern, reading the password from the terminal so it is never in shell history or a file:

```bash
read -r -s -p 'password: ' PW; echo
curl -s -X POST http://localhost:8001/consumers --data username=loki-pusher --data tags[]=credentials
# printf (a shell builtin) adds no newline; a here-string would make the newline part of the password.
printf '%s' "$PW" | curl -s -X POST http://localhost:8001/consumers/loki-pusher/basic-auth --data username=loki-pusher --data-urlencode "password@-" >/dev/null
curl -s -X POST http://localhost:8001/consumers/loki-pusher/acls --data group=loki-push >/dev/null
unset PW
```

Check: `curl -s -o /dev/null -w '%{http_code}\n' -u loki-pusher:<FROM-PASSWORD-MANAGER> https://jithendar.com/loki/api/v1/push -X POST` →
204/400 (Loki answered) rather than 401/403.

## Changing a seeded route

Edit it in Kong Manager like any other entity (it keeps its `seed:v1` tag). Then export a reviewed dump (05) so Git
records the change. Do not edit `kong-config/seed/kong.yaml` and re-import it: the seed is a historical reference.
