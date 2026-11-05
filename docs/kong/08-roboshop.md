# 08 — RoboShop behind Kong (prepared, inactive)

RoboShop does **not** run on mk4. Its manifests (roboshop-ai `services/*`, `argocd-eks/`) were built for the
`roboshop-demo` EKS cluster (Istio, NLB), deleted on 2026-11-02; the `roboshop-demo-*` Argo CD Applications on mk4
still point at it and show `Unknown`. The `roboshop-ai` namespace on mk4 holds only the `otel-collector`
ExternalName Service. It had no Traefik route, so there was nothing to back up or replace.

What is prepared so that RoboShop is served by Kong the day it runs on mk4:

| Piece | Where | What |
|---|---|---|
| Kong entities | tools `kong-config/seed/roboshop.yaml` (select tag `seed:roboshop-v1`) | Service `roboshop-web` → `web.roboshop-ai.svc.cluster.local:8080`; route `roboshop` (`/roboshop/`, prefix stripped); route `roboshop-slash` (`~/roboshop$` → 308 to `/roboshop/`) |
| Kong egress | tools `deploy/minikube/kong/kong-networkpolicy.yaml` | Kong may reach `roboshop-ai` pods `app=web` on 8080 |
| Storefront ingress | roboshop-ai `services/web/web-kong-networkpolicy.yaml` (in `services/web/kustomization.yaml`) | `web` accepts 8080 from `kong` pods `app.kubernetes.io/name=kong` only |

## Mapping from EKS

| EKS (Istio VirtualService `istio-ingress/roboshop`, tools `deploy/eks/manifests/ingress/`) | Kong |
|---|---|
| hosts `eks.jithendar.com`, `jithendar.com` | host `jithendar.com` (the EKS name belonged to the deleted cluster) |
| exact `/roboshop` → redirect `/roboshop/`, 308 | route `roboshop-slash` + `redirect` plugin, 308. Query strings are dropped on this one redirect |
| prefix `/roboshop/` → rewrite `/` → `web:8080` | route `roboshop`, `strip_path: true` |
| TLS at the Istio gateway (cert-manager, EKS issuers) | Kong's `jithendar.com` certificate (cert-sync), already covering the host |
| Kiali at `/kiali` | not carried over (no Istio on mk4) |
| `allow-mesh-apps` admits `istio-ingress` | `web-from-kong` admits `kong` |

Timeouts: connect 10 s, read/write 60 s (web's own nginx gives the API 35 s). Responses unbuffered (web proxies the
API unbuffered). Body limit: Kong's 16 MiB is above web's own (64 KiB, 2 MiB for product images).

## When RoboShop runs on mk4

1. RoboShop needs an mk4 deployment first (Argo CD Applications for mk4, no Istio, hostPath-pinned data stores).
   That is separate work; nothing here creates it.
2. Check the storefront is up: `kubectl --context mk4 -n roboshop-ai rollout status deploy/web`.
3. Import, tunnel open (03):
   ```bash
   cd tools/kong-config/seed
   deck file validate roboshop.yaml
   deck gateway validate --kong-addr http://localhost:8001 roboshop.yaml
   deck gateway diff     --kong-addr http://localhost:8001 roboshop.yaml   # creations only: 1 service, 2 routes, 1 plugin
   deck gateway apply    --kong-addr http://localhost:8001 roboshop.yaml
   deck gateway diff     --kong-addr http://localhost:8001 roboshop.yaml   # Created: 0 Updated: 0 Deleted: 0
   ```
4. Verify:

   | Check | Pass |
   |---|---|
   | `curl -s -o /dev/null -w '%{http_code} %{redirect_url}\n' https://jithendar.com/roboshop` | `308 https://jithendar.com/roboshop/` |
   | `curl -s -o /dev/null -w '%{http_code}\n' https://jithendar.com/roboshop/` | `200` |
   | `curl -s https://jithendar.com/roboshop/health` | `{"status":"ok","service":"web"}` |
   | `curl -s -o /dev/null -w '%{http_code}\n' https://jithendar.com/roboshopx` | the site's 404 (not RoboShop) |
   | browse a product, add to cart, check out | works; API calls go to `/roboshop/api/…` |
5. Export a reviewed dump (05).

Known gap: web's nginx sets `X-Forwarded-For $remote_addr`, i.e. Kong's pod address, so RoboShop logs Kong's IP,
not the visitor's. Fixing that means trusting Kong in web's nginx (`set_real_ip_from 10.244.0.0/16;
real_ip_header X-Forwarded-For;`, see `services/web/nginx/http/05-trusted-load-balancer.conf`), which is a web
image change, left for the mk4 deployment work.
