# RoboShop on EKS: deployment runbook

Takes `https://jithendar.com/roboshop` from mk4 to EKS. Background and design: [README.md](README.md).

**This has never been run on EKS.** Each step says what to expect; stop and use [Troubleshooting](#troubleshooting) if the
output differs. Public traffic does not move until step 10, and until then the only effect on the website is the Traefik
restart in that step. An NLB is billed from step 4.

Never sync with prune. Never run `kubectl apply` for resources in `eks/` by hand; change Git and sync.

## Set up

Working directory for every command: the tools checkout. roboshop-ai must be next to it.

| Tool | Version |
|---|---|
| `aws`, `kubectl`, `dig`, `curl`, `openssl` | Current |
| `argocd` | 3.x, logged in with the commands below |
| `istioctl` | 1.30.7, to match the mesh |

```bash
cd tools
EKS=roboshop-demo     # kubectl context
MK4=mk4               # kubectl context
export AWS_REGION=us-east-1
aws eks update-kubeconfig --name roboshop-demo --region us-east-1 --alias roboshop-demo
argocd login jithendar.com --grpc-web --grpc-web-root-path /argocd --username admin
```

## 1. Preflight

```bash
kubectl --context $EKS get nodes
kubectl --context $EKS -n roboshop-ai get pods
curl -s -o /dev/null -w '%{http_code}\n' https://jithendar.com/roboshop/
git -C ../roboshop-ai log -1 --format=%h
```

Expected: two `Ready` nodes, every pod `Running` and ready, `200` from mk4, and `391b441` or a later commit that keeps
`argocd-eks` compatible.

Do not continue until the application is healthy without the mesh, or a mesh problem and an application problem will look
the same. Note that EKS has its **own databases**: mk4's accounts, carts and orders do not move with this runbook, so users sign
in again and see an empty history after step 10. Razorpay, SES and Turnstile values in `roboshop-secrets` must also be set on EKS.

## 2. Let's Encrypt token

Create a Cloudflare API token limited to **Zone → DNS → Edit** on `jithendar.com`. It stays out of Git and Terraform state.

```bash
read -rs CF_TOKEN
kubectl --context $EKS -n cert-manager create secret generic cloudflare-api-token --from-literal=api-token="$CF_TOKEN"
unset CF_TOKEN
kubectl --context $EKS wait clusterissuer letsencrypt-prod letsencrypt-staging --for=condition=Ready --timeout=3m
```

Expected: both `condition met`.

## 3. Publish the Git changes

You commit and push; do this with `eks_ingress_enabled = false` still in `infrastructure/vars/terraform.tfvars`. A push to
`master` that touches `infrastructure/` applies Terraform with no review step, so first check it is a no-op:

```bash
terraform -chdir=infrastructure plan -lock=false -var-file=vars/terraform.tfvars
```

Expected: no NLB, IAM or Helm changes from this work. Investigate anything else before pushing.

```bash
git add -A && git commit -m 'EKS ingress and mesh, disabled' && git push
git -C ../roboshop-ai apply ../tools/eks/roboshop-ai-catalog.patch
git -C ../roboshop-ai add -A argocd-eks services && git -C ../roboshop-ai commit -m 'EKS mesh identities' && git -C ../roboshop-ai push
```

Then register the Applications. This changes nothing on either cluster, because none of them sync automatically:

```bash
kubectl --context $MK4 apply -f argocd/project-platform.yaml
kubectl --context $MK4 apply -f eks/applications/
kubectl --context $MK4 apply -k ../roboshop-ai/argocd-eks
```

Expected: `configured` or `created`. **Do not sync `roboshop-demo-edge`.** After this, the 15 changed Applications show `OutOfSync`
until step 6, which is expected.

## 4. Install the controllers and the NLB

Billing for the NLB starts here. In `infrastructure/vars/terraform.tfvars` set `eks_ingress_enabled = true`, confirm your current
address is still in `eks_ingress_source_cidrs` (`curl -s https://checkip.amazonaws.com`), then commit and push. **Create
infrastructure** runs on the self-hosted runner.

```bash
gh run watch -R mrjithendar/tools $(gh run list -R mrjithendar/tools --workflow 'Create infrastructure' --limit 1 --json databaseId -q '.[0].databaseId')
```

Controller and IAM:

```bash
kubectl --context $EKS -n kube-system rollout status deployment/aws-load-balancer-controller
aws eks list-pod-identity-associations --cluster-name roboshop-demo --namespace kube-system \
  --service-account aws-load-balancer-controller --query 'associations[].associationId' --output text
kubectl --context $EKS -n kube-system logs deployment/aws-load-balancer-controller --tail=50 | grep -iE 'accessdenied|error' || echo clean
```

Expected: `successfully rolled out`, one association ID, `clean`.

Istio:

```bash
istioctl --context $EKS version
kubectl --context $EKS -n istio-system get pods
kubectl --context $EKS -n istio-ingress get pods,svc,pdb,hpa
```

Expected: 1.30.7 everywhere, 2 `istiod` pods, 2 gateway pods Ready, an `EXTERNAL-IP` ending in `elb.amazonaws.com`, PDB
`MIN AVAILABLE 1`, HPA `2` to `3`. Gateway pods may take a few minutes: the readiness gate holds them until the NLB
registers them.

NLB:

```bash
NLB_HOST=$(kubectl --context $EKS -n istio-ingress get svc istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
NLB_ARN=$(aws elbv2 describe-load-balancers --names roboshop-demo-ingress --query 'LoadBalancers[0].LoadBalancerArn' --output text)
aws elbv2 describe-load-balancers --load-balancer-arns "$NLB_ARN" --query 'LoadBalancers[0].[Scheme,State.Code,Type]' --output text
aws elbv2 describe-listeners --load-balancer-arn "$NLB_ARN" --query 'Listeners[].[Port,Protocol]' --output text
TG=$(kubectl --context $EKS -n istio-ingress get targetgroupbinding -o jsonpath='{.items[0].spec.targetGroupARN}')
aws elbv2 describe-target-health --target-group-arn "$TG" --query 'TargetHealthDescriptions[].[Target.Id,TargetHealth.State]' --output text
SG=$(aws elbv2 describe-load-balancers --load-balancer-arns "$NLB_ARN" --query 'LoadBalancers[0].SecurityGroups' --output text)
aws ec2 describe-security-groups --group-ids $SG --query 'SecurityGroups[].IpPermissions[].[FromPort,IpRanges[].CidrIp]' --output json
```

Expected: `internet-facing active network`; one listener, `443 TCP`; two `healthy` targets; the frontend group allows 443
from exactly your two CIDRs. No `15021`, no `80`, no `0.0.0.0/0`.

## 5. Certificate and gateway

```bash
argocd app sync argocd/roboshop-demo-ingress
kubectl --context $EKS -n istio-ingress wait certificate/jithendar-com --for=condition=Ready --timeout=10m
kubectl --context $EKS -n istio-ingress get secret jithendar-com-tls
NLB_IP=$(dig +short "$NLB_HOST" | tail -1)
openssl s_client -connect "$NLB_IP:443" -servername jithendar.com </dev/null 2>/dev/null | openssl x509 -noout -subject -issuer -enddate
```

Expected: `condition met`; a `kubernetes.io/tls` Secret; subject `jithendar.com`, a Let's Encrypt issuer, about 90 days ahead.
This request comes from your address, so it is in the allowed list.

## 6. Enroll the workloads

Order matters. Identities first, then data stores opt out, then the namespace gets its label, then the applications restart
into it. The mesh starts permissive with policies in dry run, so nothing can be blocked yet.

```bash
argocd app sync argocd/roboshop-demo-mesh
kubectl --context $EKS -n roboshop-ai get serviceaccounts
argocd app sync argocd/roboshop-demo-redis argocd/roboshop-demo-rabbitmq argocd/roboshop-demo-postgres argocd/roboshop-demo-kafka-bridge
argocd app sync argocd/roboshop-demo-roboshop-config
kubectl --context $EKS get namespace roboshop-ai -L istio-injection
for app in user-service catalogue-service cart-service payment-service shipping-service currency-service moks mcp-server ai-gateway web; do
  argocd app sync argocd/roboshop-demo-$app && argocd app wait argocd/roboshop-demo-$app --health --timeout 300
done
```

Expected: 10 new ServiceAccounts; `ISTIO-INJECTION` is `enabled`; every sync succeeds.

The sidecar is a native sidecar, so it is listed under init containers:

```bash
kubectl --context $EKS -n roboshop-ai get pods -o custom-columns='POD:.metadata.name,READY:.status.containerStatuses[*].ready,SA:.spec.serviceAccountName,INIT:.spec.initContainers[*].name'
istioctl --context $EKS proxy-status
```

Expected: the 10 application workloads each show `istio-proxy` and their own ServiceAccount; `mongodb`, `redis`, `rabbitmq`,
`shipping-db` and `kafka` show no `istio-proxy`. `proxy-status` lists 10 sidecars plus 2 gateways, all `SYNCED`.

## 7. Smoke test through the NLB

Public traffic is still on mk4. `--resolve` sends these straight to the NLB, with the real hostname:

```bash
H="--resolve jithendar.com:443:$NLB_IP"; B=https://jithendar.com
curl -s -o /dev/null -w '%{http_code} %{redirect_url}\n' $H "$B/roboshop?utm=x"
curl -s -o /dev/null -w '%{http_code} %{content_type}\n' $H "$B/roboshop/"
curl -s $H "$B/roboshop/" | grep -o 'src="/roboshop/[^"]*' | head -3
curl -s -o /dev/null -w '%{http_code} %{content_type}\n' $H "$B/roboshop/app.js"
curl -s -w '\n%{http_code}\n' $H "$B/roboshop/api/products?limit=1" | tail -c 200
curl -s -o /dev/null -w '%{http_code}\n' -c /tmp/rs.jar -b /tmp/rs.jar $H "$B/roboshop/api/cart"
curl -s -o /dev/null -w '%{http_code}\n' $H -X POST -H 'content-type: application/json' -H "Origin: $B" -d '{"email":"nobody@example.com","password":"wrong"}' "$B/roboshop/api/auth/login"
curl -s -w ' %{http_code}\n' $H -X POST -H 'content-type: application/json' -H "Origin: $B" -d '{"message":"hello"}' "$B/roboshop/moks/chat"
for p in /roboshop/metrics /roboshop/health/../metrics /grafana/ / /mcp; do curl -s --path-as-is -o /dev/null -w "%{http_code} $p\n" $H "$B$p"; done
curl -s -o /dev/null -w '%{http_code} chat\n' $H -X POST -d '{}' "$B/roboshop/api/chat"
rm -f /tmp/rs.jar
```

Expected, in order: `308 https://jithendar.com/roboshop/?utm=x`; `200 text/html`; `src="/roboshop/...` lines; `200` and a JavaScript type; a
JSON product with `200`; `200` for a guest cart; `401` or `400` for the bad login, proving web, gateway and user-service
connect; `{"code":"login-required",...} 401` from Moks; then `404` for all five paths and `403` for chat.

Now the full flow in a browser. Add `$NLB_IP jithendar.com` to `/etc/hosts` on this Mac only, open
`https://jithendar.com/roboshop/`, and check: products load, a product page refreshes, sign in, add to cart, the checkout page,
the currency selector, and a Moks question with an answer. Without an LLM configured, Moks correctly reports that one needs
connecting. **Remove the line afterwards.**

## 8. Enforce mTLS, then policies

**Stage 1: STRICT.** In `eks/roboshop-demo/mesh/default-peerauthentication.yaml` set `mode: STRICT`, commit, push.

```bash
argocd app sync argocd/roboshop-demo-mesh
kubectl --context $EKS -n roboshop-ai get peerauthentication default
```

Expected: `STRICT`. Repeat the step 7 curls. Sidecars then accept mesh traffic only; the data stores are unaffected.

**Stage 2: review the dry run.** Turn on logging, use the shop as in step 7 including a full checkout and a Moks question, then
read what would have been denied. Dry run is an Alpha Istio feature, so treat the result as a strong hint, and keep the fast
rollback below ready.

```bash
for d in web ai-gateway user-service catalogue-service cart-service payment-service shipping-service currency-service moks; do
  istioctl --context $EKS -n roboshop-ai proxy-config log deploy/$d --level rbac:debug >/dev/null
done
# ... use the shop ...
for d in web ai-gateway user-service catalogue-service cart-service payment-service shipping-service currency-service moks; do
  echo "== $d: $(kubectl --context $EKS -n roboshop-ai logs deploy/$d -c istio-proxy --since=30m | grep -c 'shadow denied')"
done
```

Expected: every count `0`. For a non-zero count, read the lines, and add the caller to that workload's policy and to `MATRIX` in
`tests/test_eks_ingress.py` if the call is legitimate. Do not continue until it is zero.

**Stage 3: enforce.** In `eks/roboshop-demo/mesh/kustomization.yaml` delete the whole `patches:` block and its comment, commit, push.

```bash
argocd app sync argocd/roboshop-demo-mesh
kubectl --context $EKS -n roboshop-ai get authorizationpolicy -o custom-columns='NAME:.metadata.name,DRYRUN:.metadata.annotations.istio\.io/dry-run'
for d in web ai-gateway user-service catalogue-service cart-service payment-service shipping-service currency-service moks; do
  istioctl --context $EKS -n roboshop-ai proxy-config log deploy/$d --level rbac:warning >/dev/null
done
```

Expected: 10 policies with `<none>` in `DRYRUN`. Repeat the step 7 curls and browser flow.

**Fast rollback:** returns both to the safe state within seconds, then fix Git before the next sync.

```bash
kubectl --context $EKS -n roboshop-ai annotate authorizationpolicy --all istio.io/dry-run=true --overwrite
kubectl --context $EKS -n roboshop-ai patch peerauthentication default --type merge -p '{"spec":{"mtls":{"mode":"PERMISSIVE"}}}'
```

## 9. Prove mTLS and identity

Workload identity:

```bash
istioctl --context $EKS -n roboshop-ai proxy-config secret deploy/web
kubectl --context $EKS -n roboshop-ai exec deploy/ai-gateway -c istio-proxy -- pilot-agent request GET /stats/prometheus \
  | grep 'istio_tcp_connections_opened_total' | grep -o 'connection_security_policy="[a-z_]*"' | sort | uniq -c
kubectl --context $EKS -n roboshop-ai exec deploy/payment-service -c istio-proxy -- pilot-agent request GET /stats/prometheus \
  | grep 'istio_requests_total' | grep -o 'source_principal="[^"]*"\|connection_security_policy="[a-z_]*"' | sort | uniq -c
```

Expected: `default` is a valid certificate; the ai-gateway line shows `mutual_tls`; payment-service shows `mutual_tls` and
`spiffe://cluster.local/ns/roboshop-ai/sa/ai-gateway` only. Payment needs one earlier checkout attempt.

Negative tests. An **allowed** call, then the same pod reaching something it may not:

```bash
kubectl --context $EKS -n roboshop-ai exec deploy/web -c web -- wget -qO- -T 5 http://currency-service:4111/health
kubectl --context $EKS -n roboshop-ai exec deploy/web -c web -- wget -qO- -T 5 http://payment-service:4105/health
```

Expected: the first prints a health response. The second fails with `403 Forbidden`, which is the mesh refusing web's identity:
web has no reason to call payment.

A meshed pod with no granted identity, and a pod outside the mesh:

```bash
kubectl --context $EKS -n roboshop-ai run authz-meshed --rm -i --restart=Never --image=curlimages/curl:8.16.0 --command -- \
  curl -s -m 5 -w '%{http_code}\n' http://payment-service:4105/health
kubectl --context $EKS -n roboshop-ai run authz-outside --rm -i --restart=Never --image=curlimages/curl:8.16.0 \
  --labels=sidecar.istio.io/inject=false --command -- \
  sh -c 'curl -sS -m 5 -o /dev/null -w "%{http_code}\n" http://payment-service:4105/health; echo exit=$?'
```

Expected: the first prints `RBAC: access denied403`, as the pod runs as `default`. The second shows `000` with a connection reset and
a non-zero exit: `STRICT` refused a client with no mesh certificate.

`mcp-server` has no callers at all, so it refuses everyone, while an operator session still works:

```bash
kubectl --context $EKS -n roboshop-ai port-forward deploy/mcp-server 4107:4107
```

## 10. Public cutover

Three changes, in order. Traefik's upgrade restarts its single replica, which briefly affects **all of jithendar.com**, so pick a
quiet moment. The commit to `minikube/traefik/values.yaml` is already pushed.

**DNS.** In Cloudflare, add this for the `jithendar.com` zone. Leave `jithendar.com` and `www` alone.

| Type | Name | Target | Proxy status |
|---|---|---|---|
| CNAME | `roboshop-origin` | the value of `$NLB_HOST` | **DNS only** |

```bash
dig +short roboshop-origin.jithendar.com
```

Expected: the NLB name, then its addresses. DNS only matters: if proxied, Cloudflare would terminate the connection.

**Traefik.**

```bash
KUBE_CONTEXT=$MK4 bash minikube/deploy-traefik.sh
curl -s -o /dev/null -w '%{http_code}\n' https://jithendar.com/
```

Expected: Helm upgrades to a new revision, and `200` from the website.

**Cutover.**

```bash
argocd app sync argocd/roboshop-demo-edge
kubectl --context $MK4 -n roboshop-ai get ingressroute roboshop-eks
```

This is the moment public traffic moves.

## 11. Public smoke test

```bash
B=https://jithendar.com
curl -s -o /dev/null -w '%{http_code} %{redirect_url}\n' "$B/roboshop?utm=x"
curl -sI "$B/roboshop/" | grep -iE '^(HTTP|server)'
curl -s -o /dev/null -w '%{http_code} home\n' "$B/"
curl -s -o /dev/null -w '%{http_code} grafana\n' "$B/grafana/login"
curl -s -o /dev/null -w '%{http_code} http\n' "http://jithendar.com/roboshop/"
kubectl --context $EKS -n roboshop-ai logs deploy/web -c web --since=2m | tail -3
```

Expected: `308 https://jithendar.com/roboshop/?utm=x`; `HTTP/2 200` with `server: istio-envoy`, where mk4 answers `server: nginx`; `200` home; `200` grafana; `308` or `301` to HTTPS; requests in the EKS web log. Then repeat the browser flow from step 7
without the `/etc/hosts` line.

A `200` here also proves Traefik verified the gateway's certificate. Keep the mk4 RoboShop running until you are satisfied.

## Rollback

Each level leaves the main website alone, because only `/roboshop` ever moved.

**Public traffic back to mk4.** Takes effect within seconds and needs no Git change:

```bash
kubectl --context $MK4 -n roboshop-ai delete ingressroute roboshop-eks
curl -sI https://jithendar.com/roboshop/ | grep -i '^server'
```

Expected: `server: nginx`. The mk4 Ingress was never removed, so it takes over. Do not sync `roboshop-demo-edge` again until ready.

**Mesh policy.** See the fast rollback in step 8.

**Remove the sidecars.** Reverse the patch and restart:

```bash
git -C ../roboshop-ai apply -R ../tools/eks/roboshop-ai-catalog.patch   # commit and push
kubectl --context $EKS label namespace roboshop-ai istio-injection-
kubectl --context $MK4 apply -k ../roboshop-ai/argocd-eks
argocd app sync --project eks
kubectl --context $EKS -n roboshop-ai rollout restart deployment
```

**Remove everything.** Sidecars first, as above, and public traffic must already be on mk4. Removing the CRDs before these
Applications would leave them failing.

```bash
kubectl --context $MK4 -n argocd delete application roboshop-demo-edge roboshop-demo-ingress roboshop-demo-mesh
kubectl --context $MK4 -n roboshop-ai delete service roboshop-eks-origin
kubectl --context $MK4 -n roboshop-ai delete serverstransport roboshop-eks-origin
kubectl --context $EKS -n istio-ingress delete virtualservice,gateway,certificate --all
kubectl --context $EKS -n roboshop-ai delete authorizationpolicy,peerauthentication --all
```

Set `eks_ingress_enabled = false`, then commit and push. Terraform removes the gateway first, so the controller can delete the NLB
and its security groups, then the controller and Istio. Delete the `roboshop-origin` record. Check nothing is left:

```bash
aws elbv2 describe-load-balancers --names roboshop-demo-ingress 2>&1 | grep -c LoadBalancerNotFound
```

Expected: `1`.

## Troubleshooting

Turn on gateway access logs while diagnosing. They include query strings, so delete the resource afterwards:

```bash
kubectl --context $EKS apply -f - <<'YAML'
apiVersion: telemetry.istio.io/v1
kind: Telemetry
metadata: {name: debug-access-logs, namespace: istio-ingress}
spec:
  accessLogging:
  - providers:
    - name: envoy
YAML
kubectl --context $EKS -n istio-ingress logs -l istio=ingressgateway --tail=20 -f
kubectl --context $EKS -n istio-ingress delete telemetry debug-access-logs
```

| Symptom | Likely cause | Check and fix |
|---|---|---|
| `404` with an empty body and no `x-envoy-upstream-service-time` header | The gateway has no route: wrong Host, or a path outside `/roboshop/`. | `istioctl -n istio-ingress proxy-config routes deploy/istio-ingressgateway`. Check Traefik sets `Host: jithendar.com`. |
| `404` with `x-envoy-upstream-service-time` | The request reached web with the wrong path, usually prefix not stripped or stripped twice. | The web log shows the path it got. It must have no `/roboshop`. A strip middleware on the IngressRoute would break this; there must be none. |
| Page loads with no styling or broken links | Assets requested without the prefix, or `FRONTEND_BASE_PATH` changed. | View source: `src` must start `/roboshop/`. A page opened at `/roboshop` without the slash should have been redirected. |
| `503` with `UF` or `URX`, TLS error in logs | Sidecar mismatch: a pod without a sidecar under STRICT, or passthrough to a meshed service. | `istioctl -n roboshop-ai x describe pod <pod>`. Restart pods created before the namespace label. |
| `503`, `no healthy upstream` | web has no ready pods. | `kubectl -n roboshop-ai get pods`, then `kubectl -n roboshop-ai describe pod`. |
| `502` or `504` on `/api/*`, and `web` not Ready | web cannot reach ai-gateway. The Service must have `appProtocol: tcp`. | `kubectl -n roboshop-ai get svc ai-gateway -o jsonpath='{.spec.ports[0].appProtocol}'`. Without it, `Host: jithendar.com` falls into passthrough and fails under STRICT. |
| `403 RBAC: access denied`, or resets on ai-gateway | A policy is missing a legitimate caller. | `istioctl -n roboshop-ai proxy-config log deploy/<dest> --level rbac:debug` and read the log. Fix in Git, or use the fast rollback. |
| `502` from Traefik, `tls: failed to verify` | The gateway serves no or the wrong certificate, or a staging one. | Step 5 `openssl` command. A staging issuer never passes. |
| `502`/`504` from Traefik, timeout | mk4's address changed or left `eks_ingress_source_cidrs`, or the CNAME is wrong. | `dig`, the security group from step 4. Test from mk4. |
| `ExternalName` errors in the Traefik log, `/roboshop` `404` | `allowExternalNameServices` not applied. | `kubectl --context mk4 -n traefik get deploy traefik -o yaml \| grep -i externalname`, then rerun `deploy-traefik.sh`. |
| TLS handshake resets at the gateway | No `Gateway` synced, or the Secret is absent, so Envoy has no 443 filter chain. | `istioctl -n istio-ingress proxy-config listeners deploy/istio-ingressgateway --port 443`, `kubectl -n istio-ingress get secret`. |
| Certificate stuck `False` | Issuer not ready or a DNS-01 failure. | `kubectl -n istio-ingress get certificaterequest,order,challenge`, `kubectl describe challenge`. `InvalidSolver` means the Cloudflare Secret is missing. A `403` from Cloudflare means the token lacks DNS edit on this zone. |
| Issuer `Ready=False`, `secrets not found` | Step 2 not done. | `kubectl -n cert-manager get secret cloudflare-api-token`. |
| Targets `unhealthy` or `initial` | Backend rule missing, or the gateway is not ready on 15021. | `kubectl -n kube-system logs deployment/aws-load-balancer-controller`. Confirm the cluster security group has the `kubernetes.io/cluster/roboshop-demo` tag and a rule from the NLB's backend group on 443 and 15021. |
| Gateway pods stuck `Running` but not Ready | Readiness gate waiting for target health. | `kubectl -n istio-ingress get pod -o yaml \| grep -A3 readinessGates`, then the row above. |
| `EXTERNAL-IP` stays `<pending>` | Controller failed to build the NLB. | `kubectl -n istio-ingress describe svc istio-ingressgateway`. `AccessDenied` means an IAM or Pod Identity problem; restart the controller after fixing the association. |
| No `istio-proxy` in a pod | Pod predates the label, or the namespace label is missing. | `kubectl get ns roboshop-ai --show-labels`, then `kubectl -n roboshop-ai rollout restart deploy/<name>`. |
| Pods not created: `serviceaccount "x" not found` | Step 6 out of order. | `argocd app sync argocd/roboshop-demo-mesh`. |
| Pods not created: `failed calling webhook sidecar-injector` | istiod is down; injection fails closed. | `kubectl -n istio-system get pods`. |
| Data store has a sidecar | Label synced before its Application. | Sync that Application, then restart it. |
| App starts before its sidecar is ready | `holdApplicationUntilProxyStarts` not applied. | Check `istio-sidecar-injector` in `istio-system`. |
