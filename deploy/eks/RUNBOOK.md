# RoboShop on EKS: deployment runbook

Takes `https://jithendar.com/roboshop` from mk4 to EKS. Background and design: [README.md](README.md).

**This has never been run on EKS.** Each step says what to expect; stop and use [Troubleshooting](#troubleshooting) if the
output differs. Public traffic does not move until step 10. An NLB is billed from step 4.

Never sync with prune. Argo CD owns `deploy/eks/manifests/` on this cluster, so change Git and sync; a direct `kubectl apply` drops
Argo CD's tracking until the next sync ([DEPLOY.md](DEPLOY.md#direct-kubectl-apply)).

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
git -C ../roboshop-ai log -1 --format=%h
```

Expected: two `Ready` nodes, every pod `Running` and ready, and `391b441` or a later commit that keeps
`argocd-eks` compatible.

Do not continue until the application is healthy without the mesh, or a mesh problem and an application problem will look
the same. Note that EKS has its **own databases**: mk4's accounts, carts and orders do not move with this runbook, so users sign
in again and see an empty history after step 10. Razorpay, SES and Turnstile values in `roboshop-secrets` must also be set on EKS.

## 2. Let's Encrypt token

Create a Cloudflare API token with **Zone → DNS → Edit** and **Zone → Zone → Read** on `jithendar.com`. It stays out of Git and Terraform state.

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
```

Then register the Applications. This changes nothing on either cluster, because none of them sync automatically:

```bash
kubectl --context $MK4 apply -f ../miniKube/deploy/minikube/applications/project-mk-platform.yaml
kubectl --context $MK4 apply -f deploy/eks/applications/
for f in ../roboshop-ai/argocd-eks/*.yaml; do
  [ "${f##*/}" = kustomization.yaml ] || kubectl --context $MK4 apply -f "$f"
done
```

Expected: `configured` or `created`. After this, the 15 changed Applications show `OutOfSync`
until step 6, which is expected.

## 4. Install the controllers and the NLB

Billing for the NLB starts here. In `infrastructure/vars/terraform.tfvars` set `eks_ingress_enabled = true`, which creates the
controller's IAM role and Pod Identity. Confirm your current address is still in `deploy/eks/helm-values/istio-ingressgateway.yaml`
(`curl -s https://checkip.amazonaws.com`), then commit and push. **Create infrastructure** runs on the self-hosted runner.

```bash
gh run watch -R mrjithendar/tools $(gh run list -R mrjithendar/tools --workflow 'Create infrastructure' --limit 1 --json databaseId -q '.[0].databaseId')
```

Then sync the controllers from the hub, in this order. The issuers need the token from step 2 to become Ready:

```bash
kubectl --context $MK4 apply -f deploy/eks/applications/
for a in metrics-server prometheus-agent alloy letsencrypt-issuers aws-load-balancer-controller istio-base istiod istio-ingressgateway; do
  argocd app diff argocd/roboshop-demo-$a
  argocd app sync argocd/roboshop-demo-$a
done
```

**Taking over the Helm releases Terraform installed.** Push first: `infrastructure/eks-argocd-handover.tf` makes Terraform forget
them without uninstalling, and `terraform plan` must show `will no longer be managed` and `0 to destroy`. Run the same loop. The
diffs should be Argo CD tracking metadata only, except `aws-load-balancer-controller`, whose webhook certificate moves to
cert-manager: expect `Issuer` and `Certificate` resources and new webhook `caBundle` injection. Check that before going on:

```bash
kubectl --context $EKS -n kube-system wait certificate/aws-load-balancer-serving-cert --for=condition=Ready --timeout=3m
kubectl --context $EKS get mutatingwebhookconfiguration aws-load-balancer-webhook -o jsonpath='{.webhooks[0].clientConfig.caBundle}' | wc -c
kubectl --context $EKS -n istio-ingress rollout restart deployment/istio-ingressgateway
kubectl --context $EKS -n istio-ingress rollout status deployment/istio-ingressgateway
```

Expected: `condition met`, a non-zero count, and a rollout that finishes, which proves the webhook still admits gateway pods.
Then delete Helm's records so `helm list` stops showing releases nobody owns. **Never run `helm uninstall`: it deletes the
workloads, and with the gateway Service the NLB.**

```bash
for r in kube-system/aws-load-balancer-controller kube-system/metrics-server istio-system/istio-base istio-system/istiod \
  istio-ingress/istio-ingressgateway monitoring/prometheus-agent cert-manager/letsencrypt-issuers; do
  kubectl --context $EKS -n ${r%/*} delete secret -l owner=helm,name=${r#*/}
done
```

Finally delete `infrastructure/eks-argocd-handover.tf`, the `provider "helm"` block and `helm` in `required_providers` in
`_provider.tf`, `data.aws_eks_cluster_auth` in `_data.tf`, and `mock_provider "helm"` in `tests/eks.tftest.hcl`, in one commit.

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

Expected: `internet-facing active network`; two listeners, `443 TCP` and `80 TCP`; two `healthy` targets per listener; the
frontend group allows 443 and 80 from exactly the listed addresses. No `15021`, no `0.0.0.0/0` until [step 10](#10-public-cutover).

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

Order matters. Identities first, then the namespace gets its label, then data stores and applications restart into it. The
mesh starts permissive with policies in dry run, so nothing can be blocked yet. Store restarts briefly interrupt the shop; their
data is on volumes.

```bash
argocd app sync argocd/roboshop-demo-mesh
kubectl --context $EKS -n roboshop-ai get serviceaccounts
argocd app sync argocd/roboshop-demo-roboshop-config
kubectl --context $EKS get namespace roboshop-ai -L istio-injection
for app in redis rabbitmq postgres mongodb kafka-bridge; do
  argocd app sync argocd/roboshop-demo-$app && argocd app wait argocd/roboshop-demo-$app --health --timeout 300
done
for app in user-service catalogue-service cart-service payment-service shipping-service currency-service moks mcp-server ai-gateway web; do
  argocd app sync argocd/roboshop-demo-$app && argocd app wait argocd/roboshop-demo-$app --health --timeout 300
done
```

Expected: 15 ServiceAccounts from the mesh Application, plus `mongodb` and `default`; `ISTIO-INJECTION` is `enabled`; every sync succeeds.

The sidecar is a native sidecar, so it is listed under init containers:

```bash
kubectl --context $EKS -n roboshop-ai get pods -o custom-columns='POD:.metadata.name,READY:.status.containerStatuses[*].ready,SA:.spec.serviceAccountName,PROXY:.spec.initContainers[*].name'
istioctl --context $EKS proxy-status
```

Expected: every workload shows `istio-proxy` and its own ServiceAccount, including `mongodb`, `redis`, `rabbitmq`, `shipping-db` and
`kafka`. `proxy-status` lists one sidecar per pod plus 2 gateways, all `SYNCED`. A store failing to come up: see Troubleshooting.

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

**Stage 1: STRICT.** In `roboshop-ai/argocd-eks/apps/mesh/default-peerauthentication.yaml` set `mode: STRICT`, commit, push.

```bash
argocd app sync argocd/roboshop-demo-mesh
kubectl --context $EKS -n roboshop-ai get peerauthentication default
```

Expected: `STRICT`. Repeat the step 7 curls. Sidecars then accept mesh traffic only, on the data stores too.

**Stage 2: review the dry run.** Turn on logging, use the shop as in step 7 including a full checkout and a Moks question, then
read what would have been denied. Dry run is an Alpha Istio feature, so treat the result as a strong hint, and keep the fast
rollback below ready.

```bash
for d in deploy/web deploy/ai-gateway deploy/user-service deploy/catalogue-service deploy/cart-service deploy/payment-service deploy/shipping-service deploy/currency-service deploy/moks deploy/redis deploy/shipping-db sts/mongodb sts/rabbitmq; do
  istioctl --context $EKS -n roboshop-ai proxy-config log $d --level rbac:debug >/dev/null
done
# ... use the shop ...
for d in deploy/web deploy/ai-gateway deploy/user-service deploy/catalogue-service deploy/cart-service deploy/payment-service deploy/shipping-service deploy/currency-service deploy/moks deploy/redis deploy/shipping-db sts/mongodb sts/rabbitmq; do
  echo "== $d: $(kubectl --context $EKS -n roboshop-ai logs $d -c istio-proxy --since=30m | grep -c 'shadow denied')"
done
```

Expected: every count `0`. For a non-zero count, read the lines, and add the caller to that workload's policy and to `MATRIX` in
`tests/test_eks_ingress.py` if the call is legitimate. Do not continue until it is zero.

**Stage 3: enforce.** In `roboshop-ai/argocd-eks/apps/mesh/kustomization.yaml` delete the whole `patches:` block and its comment, commit, push.

```bash
argocd app sync argocd/roboshop-demo-mesh
kubectl --context $EKS -n roboshop-ai get authorizationpolicy -o custom-columns='NAME:.metadata.name,DRYRUN:.metadata.annotations.istio\.io/dry-run'
for d in deploy/web deploy/ai-gateway deploy/user-service deploy/catalogue-service deploy/cart-service deploy/payment-service deploy/shipping-service deploy/currency-service deploy/moks deploy/redis deploy/shipping-db sts/mongodb sts/rabbitmq; do
  istioctl --context $EKS -n roboshop-ai proxy-config log $d --level rbac:warning >/dev/null
done
```

Expected: 15 policies with `<none>` in `DRYRUN`. Repeat the step 7 curls and browser flow.

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

Browsers then reach the NLB directly. **Do not start until steps 8 and 9 pass.** The DNS change moves every path on the
hostname, and the `roboshop` VirtualService answers `404` for everything except `/roboshop`. These run on mk4 behind its Traefik
and stop being reachable at `jithendar.com` unless they have moved first:

| What | Where it is now | What depends on it |
|---|---|---|
| Next.js website | `jithendar.com/`, `www.jithendar.com` | The apex record; `www` also needs adding to the Gateway and Certificate |
| Argo CD | `/argocd` | It is the hub that deploys `roboshop-demo`; the `argocd` CLI logs in through this path |
| Prometheus, Grafana | `/prometheus`, `/grafana` | `remoteWrite` in `deploy/eks/helm-values/prometheus-agent.yaml` |
| Loki | `/loki/api/v1/` | `loki.write` in `deploy/eks/manifests/alloy/alloy-config-configmap.yaml`, and the Loki connector in Moks |
| Moks portal | `/moks` paths | Its own Argo application and schema |

Open the NLB. In `deploy/eks/helm-values/istio-ingressgateway.yaml` set:

```yaml
loadBalancerSourceRanges:
- 0.0.0.0/0
```

Commit and push, sync `roboshop-demo-istio-ingressgateway`, then check it from an address outside the old list:

```bash
curl -s -o /dev/null -w '%{http_code}\n' --resolve jithendar.com:443:$NLB_IP https://jithendar.com/roboshop/
curl -s -o /dev/null -w '%{http_code} %{redirect_url}\n' --resolve jithendar.com:80:$NLB_IP http://jithendar.com/roboshop/
```

Expected: `200`, then `301 https://jithendar.com/roboshop/`.

In Cloudflare, change the `jithendar.com` record to a **DNS only** CNAME for `$NLB_HOST`; Cloudflare flattens it at the apex.
This is the moment public traffic moves. If proxied, Cloudflare would terminate the connection.

## 11. Public smoke test

```bash
B=https://jithendar.com
curl -s -o /dev/null -w '%{http_code} %{redirect_url}\n' "$B/roboshop?utm=x"
curl -sI "$B/roboshop/" | grep -iE '^(HTTP|server)'
curl -s -o /dev/null -w '%{http_code} %{redirect_url}\n' "http://jithendar.com/roboshop/"
kubectl --context $EKS -n roboshop-ai logs deploy/web -c web --since=2m | tail -3
```

Expected: `308 https://jithendar.com/roboshop/?utm=x`; `HTTP/2 200` with `server: istio-envoy`; `301` to HTTPS; requests in the EKS
web log. Then repeat the browser flow from step 7 without the `/etc/hosts` line.

## Kiali

Read-only mesh dashboard, served by the gateway at `/kiali`. It needs steps 2 and 5 for the certificate, and shows traffic only
for workloads with sidecars, from step 6. `jithendar.com` must point at the NLB (step 10) to open it by name; until then use the
port-forward below, or the `/etc/hosts` line from step 7.

The signing key is created by hand, so it stays out of Git and does not change between renders. Sync after it exists:

```bash
kubectl --context $EKS -n istio-system create secret generic kiali-signing-key --from-literal=key="$(openssl rand -hex 16)"
kubectl --context $MK4 apply -f deploy/eks/applications/project-eks-platform.yaml
kubectl --context $MK4 apply -f deploy/eks/applications/roboshop-demo-kiali.yaml -f deploy/eks/applications/roboshop-demo-kiali-prometheus.yaml
argocd app sync argocd/roboshop-demo-kiali-prometheus
argocd app sync argocd/roboshop-demo-kiali
argocd app sync argocd/roboshop-demo-ingress
kubectl --context $EKS -n istio-system rollout status deployment/kiali
kubectl --context $EKS -n istio-system port-forward svc/kiali 20001:20001
```

Open `http://localhost:20001/kiali`, and sign in with a token that lasts one working day:

```bash
kubectl --context $EKS -n istio-system create token kiali --duration=8h
```

Anyone with that token can read the mesh, including at `/kiali` once the NLB is public. Do not share it.

## Retiring mk4

Once the site has been stable long enough to trust: remove `46.224.38.14/32` from `eks_public_access_cidrs`, and only then
delete mk4.

## Rollback

**Public traffic.** Restore the `jithendar.com` A record to `46.224.38.14`. That brings back what mk4 still serves. It does not
bring back the shop: the `roboshop-ai` namespace on mk4 has been deleted.

**Mesh policy.** See the fast rollback in step 8.

**Remove the sidecars.** Reverse the patch and restart:

```bash
# In roboshop-ai, remove the serviceAccountName patches from argocd-eks/*.yaml and the label patch from roboshop-config.yaml; commit and push.
kubectl --context $EKS label namespace roboshop-ai istio-injection-
for f in ../roboshop-ai/argocd-eks/*.yaml; do
  [ "${f##*/}" = kustomization.yaml ] || kubectl --context $MK4 apply -f "$f"
done
argocd app sync --project eks
kubectl --context $EKS -n roboshop-ai rollout restart deployment
```

**Remove everything.** Sidecars first, as above, and DNS must already be off the NLB. Removing the CRDs before these
Applications would leave them failing.

```bash
kubectl --context $MK4 -n argocd delete application roboshop-demo-ingress roboshop-demo-mesh
kubectl --context $EKS -n istio-ingress delete virtualservice,gateway,certificate --all
kubectl --context $EKS -n roboshop-ai delete authorizationpolicy,peerauthentication --all
```

Delete the gateway Service first, while the controller is still running, so it can delete the NLB and its security groups. Then
remove the Applications and what they installed; they carry `Delete=false`, so deleting an Application leaves its resources:

```bash
kubectl --context $EKS -n istio-ingress delete service istio-ingressgateway
kubectl --context $MK4 -n argocd delete application roboshop-demo-istio-ingressgateway roboshop-demo-istiod roboshop-demo-istio-base roboshop-demo-aws-load-balancer-controller
kubectl --context $EKS delete namespace istio-ingress istio-system
kubectl --context $EKS -n kube-system delete deployment aws-load-balancer-controller
```

Set `eks_ingress_enabled = false`, then commit and push. Check nothing is left:

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
| `404` with an empty body and no `x-envoy-upstream-service-time` header | The gateway has no route: wrong Host, or a path outside `/roboshop/`. | `istioctl -n istio-ingress proxy-config routes deploy/istio-ingressgateway`. Check the request's `Host` is `jithendar.com`. |
| `404` with `x-envoy-upstream-service-time` | The request reached web with the wrong path, usually prefix not stripped or stripped twice. | The web log shows the path it got. It must have no `/roboshop`. The only rewrite is in the VirtualService. |
| Page loads with no styling or broken links | Assets requested without the prefix, or `FRONTEND_BASE_PATH` changed. | View source: `src` must start `/roboshop/`. A page opened at `/roboshop` without the slash should have been redirected. |
| `503` with `UF` or `URX`, TLS error in logs | Sidecar mismatch: a pod without a sidecar under STRICT, or passthrough to a meshed service. | `istioctl -n roboshop-ai x describe pod <pod>`. Restart pods created before the namespace label. |
| `503`, `no healthy upstream` | web has no ready pods. | `kubectl -n roboshop-ai get pods`, then `kubectl -n roboshop-ai describe pod`. |
| `502` or `504` on `/api/*`, and `web` not Ready | web cannot reach ai-gateway. The Service must have `appProtocol: tcp`. | `kubectl -n roboshop-ai get svc ai-gateway -o jsonpath='{.spec.ports[0].appProtocol}'`. Without it, `Host: jithendar.com` falls into passthrough and fails under STRICT. |
| A store's clients fail with connection resets, timeouts or auth errors after STRICT | A client without a sidecar, a caller missing from the store's policy, or a store that only listens on one address. | `istioctl -n roboshop-ai x describe pod <store pod>`; the store's `istio-proxy` log with `rbac:debug`. Use the fast rollback in step 8 first. |
| `403 RBAC: access denied`, or resets on ai-gateway | A policy is missing a legitimate caller. | `istioctl -n roboshop-ai proxy-config log deploy/<dest> --level rbac:debug` and read the log. Fix in Git, or use the fast rollback. |
| Browser certificate error | The gateway serves no or the wrong certificate, or a staging one. | Step 5 `openssl` command. A staging issuer never passes. |
| Timeout connecting to the NLB | The address is not in `deploy/eks/helm-values/istio-ingressgateway.yaml`, or DNS is wrong. | `dig`, and the security group from step 4. |
| TLS handshake resets at the gateway | No `Gateway` synced, or the Secret is absent, so Envoy has no 443 filter chain. | `istioctl -n istio-ingress proxy-config listeners deploy/istio-ingressgateway --port 443`, `kubectl -n istio-ingress get secret`. |
| Certificate stuck `False` | Issuer not ready or a DNS-01 failure. | `kubectl -n istio-ingress get certificaterequest,order,challenge`, `kubectl describe challenge`. `InvalidSolver` means the Cloudflare Secret is missing. A `403` from Cloudflare means the token lacks DNS edit or zone read on this zone. |
| Issuer `Ready=False`, `secrets not found` | Step 2 not done. | `kubectl -n cert-manager get secret cloudflare-api-token`. |
| Targets `unhealthy` or `initial` | Backend rule missing, or the gateway is not ready on 15021. | `kubectl -n kube-system logs deployment/aws-load-balancer-controller`. Confirm the cluster security group has the `kubernetes.io/cluster/roboshop-demo` tag and a rule from the NLB's backend group on 443 and 15021. |
| Gateway pods stuck `Running` but not Ready | Readiness gate waiting for target health. | `kubectl -n istio-ingress get pod -o yaml \| grep -A3 readinessGates`, then the row above. |
| `EXTERNAL-IP` stays `<pending>` | Controller failed to build the NLB. | `kubectl -n istio-ingress describe svc istio-ingressgateway`. `AccessDenied` means an IAM or Pod Identity problem; restart the controller after fixing the association. |
| No `istio-proxy` in a pod | Pod predates the label, or the namespace label is missing. | `kubectl get ns roboshop-ai --show-labels`, then `kubectl -n roboshop-ai rollout restart deploy/<name>`. |
| Pods not created: `serviceaccount "x" not found` | Step 6 out of order. | `argocd app sync argocd/roboshop-demo-mesh`. |
| Pods not created: `failed calling webhook sidecar-injector` | istiod is down; injection fails closed. | `kubectl -n istio-system get pods`. |
| Data store has a sidecar | Label synced before its Application. | Sync that Application, then restart it. |
| App starts before its sidecar is ready | `holdApplicationUntilProxyStarts` not applied. | Check `istio-sidecar-injector` in `istio-system`. |
