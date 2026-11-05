# 03 — Kong Manager and Admin API access

**Kong OSS has no login on Kong Manager or the Admin API.** Whoever can open a TCP connection to port 8001 can
change or delete every route, read every credential and certificate key, and point any hostname anywhere. Access
control is therefore only:

1. **Network isolation:** both listen on `127.0.0.1` inside the Kong pod (`KONG_ADMIN_LISTEN`,
   `KONG_ADMIN_GUI_LISTEN` in `deploy/minikube/kong/kong-config.yaml`). No Service, pod, node or NodePort can
   reach them; the NetworkPolicy has no allow for them either.
2. **Who holds kubeconfig access** to mk4 with `pods/portforward` (or `pods/exec`) in namespace `kong`. Today that
   is the cluster-admin kubeconfig on this Mac. CI's ServiceAccounts (`github-ci-applier`, `github-ci-deployer`)
   are namespaced to `jithendar` and cannot reach `kong`.

Never add an Ingress, NodePort, LoadBalancer, tunnel, HAProxy backend or Kong route that points at 8001, 8002,
8444 or 8445.

## How Kong Manager talks to the Admin API

Kong Manager is a single-page app served from port 8002. The **browser** then calls the Admin API directly, at
`admin_gui_api_url`. So both ports must be reachable from the browser, and:

| Setting | Value | Must match |
|---|---|---|
| `admin_gui_url` | `http://localhost:8002` | the address in the browser's address bar. Kong derives the only allowed CORS origin from it |
| `admin_gui_api_url` | `http://localhost:8001` | the address the browser can reach the Admin API at |
| `admin_gui_path` | `/` | — |
| `admin_listen` | `127.0.0.1:8001` (HTTP only) | — |
| `admin_gui_listen` | `127.0.0.1:8002` (HTTP only) | — |

CORS: the Admin API answers with `Access-Control-Allow-Origin: http://localhost:8002` and
`Access-Control-Allow-Credentials: true`. With `admin_gui_url` unset, Kong 3.9.4 would reflect **any** Origin
(`kong/api/api_helpers.lua`), letting any web page you visit read the Admin API while the tunnel is open; that is
why it is set.

## Open it

```bash
# Terminal 1: both ports, bound to this Mac's loopback only (the kubectl default; never add --address 0.0.0.0)
kubectl --context mk4 -n kong port-forward deploy/kong 8001:8001 8002:8002
```

Then open <http://localhost:8002>. Use exactly `localhost` (not `127.0.0.1`): `127.0.0.1` is a different origin,
and the Admin API would refuse it under CORS. If you must use another local port, change both
`KONG_ADMIN_GUI_URL`/`KONG_ADMIN_GUI_API_URL` in Git and roll Kong, or the Manager's API calls fail.

Command line instead of the browser:

```bash
curl -s http://localhost:8001/status | python3 -m json.tool
curl -s 'http://localhost:8001/routes?tags=seed:v1' | python3 -c 'import json,sys; [print(r["name"]) for r in json.load(sys.stdin)["data"]]'
```

`kubectl port-forward svc/kong-admin 8001:8001` also works; the Service exists only as a name for that.

## HTTP or TLS?

HTTP over `localhost` is acceptable here, and 8444/8445 are not enabled:

- The hop from this Mac to the cluster is the Kubernetes API server's TLS connection (port-forward is tunnelled
  through it, authenticated by the kubeconfig).
- Inside the pod the hop is loopback. Nothing else can listen in.
- The browser treats `http://localhost` as a secure context.

What TLS would **not** fix: there is no login either way. If Kong Manager is ever exposed beyond loopback, TLS
alone is not enough; it would need an authenticating proxy in front, which is out of scope.

## Safe use

- Open the port-forward only while you use it, and stop it (Ctrl-C) afterwards. While it is open, any local
  process on this Mac can change the gateway.
- Use a separate browser profile for Kong Manager. CORS blocks other sites from **reading** responses, but a
  malicious page can still **send** a form POST to `http://localhost:8001/...` (a "simple" cross-origin request
  needs no preflight, and the Admin API accepts `application/x-www-form-urlencoded`). Do not browse other sites in
  that profile while the tunnel is open.
- Remember there is no audit log in OSS. Kong's own logs (`kubectl -n kong logs deploy/kong -c kong`) show Admin
  API requests from `127.0.0.1`; export a decK dump after each change session (05) so Git records what changed.
- Credentials are visible in the Admin API (key-auth keys are stored as given; basic-auth passwords are hashed).
  Treat a full `deck gateway dump` as a secret (05).
