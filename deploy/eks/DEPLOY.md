# Deploy to EKS

How `roboshop-demo` is deployed from this repository. Every path is from the repository root. Design: [README.md](README.md). First rollout of the mesh and the public cutover: [RUNBOOK.md](RUNBOOK.md).

| Directory | Contents | Goes to | How |
|---|---|---|---|
| `deploy/eks/applications/` | AppProject and Applications | `mk4`, the Argo CD hub | `kubectl apply -f` |
| `deploy/eks/manifests/cert-manager/` | ClusterIssuers | `roboshop-demo` | Argo CD plain directory |
| `deploy/eks/manifests/ingress/` | Certificate, Gateway, VirtualServices | `roboshop-demo` | Argo CD plain directory |
| `deploy/eks/manifests/bootstrap/` | Connectivity ConfigMap | `roboshop-demo` | Argo CD plain directory |
| `deploy/eks/helm-values/` | Values for add-on charts. Not Kubernetes objects. | Read by Argo CD | Never applied |
| `deploy/eks/examples/` | Secret templates | Nowhere | Never applied |

Add-ons stay Helm charts, pinned in their Applications. Do not run `kubectl apply -f deploy/eks/` or use `-R`: it would send Applications to the wrong cluster and fail on the Helm values.

## Prerequisites

- Terraform has created the cluster, the cert-manager add-on and the load balancer controller's IAM role (`eks_ingress_enabled = true` in `infrastructure/vars/terraform.tfvars`). See [infrastructure/README.md](../../infrastructure/README.md).
- `aws`, `kubectl`, `argocd` 3.x, and `istioctl` 1.30.7 to match the mesh.
- The cluster is registered with the hub, once: `argocd cluster add roboshop-demo --name roboshop-demo --yes`.
- Your changes are pushed. Argo CD reads `master` on GitHub, not this checkout.

```bash
EKS=roboshop-demo
MK4=mk4
export AWS_REGION=us-east-1
aws eks update-kubeconfig --name roboshop-demo --region us-east-1 --alias roboshop-demo
argocd login jithendar.com --grpc-web --grpc-web-root-path /argocd --username admin
kubectl --context $EKS get nodes
```

Expected: every node `Ready`.

## Required configuration

**Secrets.** None is in Git and each is created by hand once. The templates in [`examples/`](examples/) show the shape; the commands below leave no file behind. These commands fail with `AlreadyExists` when the Secret is already there, which is safe: leave it alone.

| Secret | Namespace | Key | Used by |
|---|---|---|---|
| `cloudflare-api-token` | `cert-manager` | `api-token` | ClusterIssuers (DNS-01) |
| `prometheus-remote-write-auth` | `monitoring` | `password` | Prometheus agent. The same password must be on mk4. |
| `loki-push-auth` | `monitoring` | `password` | Alloy. The same password must be on mk4. |
| `kiali-signing-key` | `istio-system` | `key` | Kiali login tokens |
| `roboshop-secrets` | `roboshop-ai` | See `roboshop-ai` | RoboShop workloads. Not owned by this repository. |

**Values in Git that come from your AWS account.** Take them from Terraform; never guess them.

| File | Setting | Source |
|---|---|---|
| `helm-values/aws-load-balancer-controller.yaml` | `vpcId` | `terraform -chdir=infrastructure output vpc_id` |
| `helm-values/istio-ingressgateway.yaml` | `aws-load-balancer-subnets` | `terraform -chdir=infrastructure output public_subnets` |
| `helm-values/istio-ingressgateway.yaml` | `loadBalancerSourceRanges` | The addresses allowed to reach the NLB. An empty list opens it to the Internet. |
| `manifests/ingress/*.yaml` | Hostnames | Must also be DNS records for the NLB, DNS only |

## Deploy

The commands create or update everything, in dependency order. On a cluster that is already running, every step is safe to repeat. Review each `argocd app diff`, and never add `--prune`.

### 1. Register the Applications on the hub

```bash
kubectl --context $MK4 apply -f deploy/eks/applications/project-eks-platform.yaml
kubectl --context $MK4 apply -f deploy/eks/applications/
```

### 2. Install the add-ons

Istio's CRDs come first, and the gateway last because its Service creates the NLB, which is billed.

```bash
read -rs CF_TOKEN
kubectl --context $EKS -n cert-manager create secret generic cloudflare-api-token --from-literal=api-token="$CF_TOKEN"
unset CF_TOKEN

PASS=$(openssl rand -hex 32)
kubectl --context $MK4 -n monitoring create secret generic prometheus-remote-write-auth \
  --type=kubernetes.io/basic-auth --from-literal=username=eks --from-literal=password="$PASS"
kubectl --context $EKS create namespace monitoring
kubectl --context $EKS -n monitoring create secret generic prometheus-remote-write-auth --from-literal=password="$PASS"
unset PASS

PASS=$(openssl rand -hex 32)
kubectl --context $MK4 -n monitoring create secret generic loki-push-auth \
  --type=kubernetes.io/basic-auth --from-literal=username=eks --from-literal=password="$PASS"
kubectl --context $EKS -n monitoring create secret generic loki-push-auth --from-literal=password="$PASS"
unset PASS

for a in metrics-server prometheus-agent alloy aws-load-balancer-controller istio-base istiod istio-ingressgateway; do
  argocd app diff argocd/roboshop-demo-$a
  argocd app sync argocd/roboshop-demo-$a
  argocd app wait argocd/roboshop-demo-$a --health --timeout 300
done
```

### 3. Wait for the CRDs

The plain manifests are custom resources, so these must exist first:

```bash
kubectl --context $EKS wait --for=condition=Established --timeout=2m \
  crd/clusterissuers.cert-manager.io crd/certificates.cert-manager.io \
  crd/gateways.networking.istio.io crd/virtualservices.networking.istio.io
```

Expected: four `condition met` lines.

### 4. Sync the plain manifests

Order matters: the Certificate needs its issuer, and the Gateway needs the Secret that the Certificate writes.

```bash
for a in bootstrap letsencrypt-issuers; do
  argocd app diff argocd/roboshop-demo-$a
  argocd app sync argocd/roboshop-demo-$a
done
kubectl --context $EKS wait clusterissuer letsencrypt-prod letsencrypt-staging --for=condition=Ready --timeout=3m

argocd app diff argocd/roboshop-demo-ingress
argocd app sync argocd/roboshop-demo-ingress
kubectl --context $EKS -n istio-ingress wait certificate/jithendar-com --for=condition=Ready --timeout=10m
```

### 5. Install Kiali

```bash
kubectl --context $EKS -n istio-system create secret generic kiali-signing-key --from-literal=key="$(openssl rand -hex 16)"
argocd app sync argocd/roboshop-demo-kiali-prometheus
argocd app sync argocd/roboshop-demo-kiali
kubectl --context $EKS -n istio-system rollout status deployment/kiali --timeout=5m
```

### 6. Deploy RoboShop

These Applications are in the roboshop-ai repository. Its `argocd-eks/kustomization.yaml` only lists files, so this does the same thing without Kustomize:

```bash
for f in ../roboshop-ai/argocd-eks/*.yaml; do
  [ "${f##*/}" = kustomization.yaml ] || kubectl --context $MK4 apply -f "$f"
done
```

Then sync them in the order given in [RUNBOOK.md step 6](RUNBOOK.md#6-enroll-the-workloads).

## Verify

```bash
kubectl --context $MK4 -n argocd get applications.argoproj.io | grep roboshop-demo
kubectl --context $EKS get clusterissuer
kubectl --context $EKS -n istio-ingress get certificate,gateway,virtualservice,svc,pods
kubectl --context $EKS -n istio-system get pods
kubectl --context $EKS -n roboshop-ai get configmap roboshop-demo-bootstrap
curl -sS -o /dev/null -w '%{http_code}\n' https://eks.jithendar.com/roboshop/
```

Expected: every Application `Synced` and `Healthy`; both issuers and the Certificate `True`; the Service has an `EXTERNAL-IP` ending in `elb.amazonaws.com`; every pod ready; and `200`, from an address the NLB allows.

## Direct `kubectl apply`

Every file in `manifests/` works with plain `kubectl apply -f`, with no Argo CD. Use this when the hub is unavailable or for a cluster it does not manage.

```bash
kubectl --context $EKS diff -f deploy/eks/manifests/cert-manager/
kubectl --context $EKS apply -f deploy/eks/manifests/cert-manager/
kubectl --context $EKS diff -f deploy/eks/manifests/bootstrap/
kubectl --context $EKS apply -f deploy/eks/manifests/bootstrap/
kubectl --context $EKS diff -f deploy/eks/manifests/ingress/
kubectl --context $EKS apply -f deploy/eks/manifests/ingress/
```

The add-ons from step 2 must already be installed: the namespaces `cert-manager`, `istio-ingress` and `roboshop-ai` are not in these files, and neither are the CRDs.

**On a cluster Argo CD manages, this has a cost.** Argo CD records ownership in the `argocd.argoproj.io/tracking-id` annotation, and `kubectl apply` removes it, because the files do not carry it. `kubectl diff` shows that as the only change. The Application then reports the resources as out of sync until the next `argocd app sync`, which restores the annotation. Nothing else changes, and the workloads keep running. Use Argo CD unless you have a reason not to.

## Roll back

Argo CD deploys Git, so a rollback is a revert. Never sync with prune, and never run `helm uninstall`: with the gateway, that deletes the NLB.

**A manifest or values change:**

```bash
git revert <commit>
git push
kubectl --context $MK4 apply -f deploy/eks/applications/
argocd app diff argocd/roboshop-demo-<app>
argocd app sync argocd/roboshop-demo-<app>
```

**Urgently, with the hub down:** check out the last good commit and use [Direct `kubectl apply`](#direct-kubectl-apply) from that checkout.

**Mesh policy and removing components:** [RUNBOOK.md](RUNBOOK.md#rollback).
