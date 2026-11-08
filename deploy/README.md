# Deployment files

Each environment has its own directory and can be deployed without the other.

| Directory | Cluster | kubectl context | Deployed with | Guide |
|---|---|---|---|---|
| [`eks/`](eks/) | `roboshop-demo` (AWS EKS) | `roboshop-demo`, and `mk4` for the Argo CD hub | Argo CD reading plain YAML; Helm charts for add-ons | [eks/DEPLOY.md](eks/DEPLOY.md) |
| [`minikube/`](minikube/) | `mk4` (self-hosted Minikube) | `mk4` | Repository scripts, Helm, Kustomize, Argo CD | [minikube/README.md](minikube/README.md) |

RoboShop workloads are in neither: they live in `roboshop-ai/argocd-eks`. See [What is outside this directory](#what-is-outside-this-directory).

## Rules

- Never run `kubectl apply` on `deploy/`, `deploy/eks/` or `deploy/minikube/`. Name the leaf directory, and pass `--context` every time.
- `deploy/eks/` never reads a file from `deploy/minikube/`, or the reverse. Copy a setting if both need it.
- `deploy/eks/` has no Kustomize and no templating of its own manifests. Every file in `deploy/eks/manifests/` is one complete object with its namespace, so what you read is what is applied. Add-on charts stay Helm charts, with values in `deploy/eks/helm-values/`.
- `deploy/eks/applications/` goes to the `mk4` hub, not to EKS. Everything in `deploy/eks/manifests/` goes to EKS.
- Secrets are never in Git. Templates are in `deploy/*/examples/`, which nothing applies. A `*.yaml.example` file is skipped by `kubectl apply -f` and by Argo CD. Filled-in `*-secret.yaml` files under `deploy/` are gitignored.
- AWS settings (NLB annotations, subnets, VPC ID, `alb` IngressClass, Pod Identity) stay in `deploy/eks/` and `infrastructure/`. Local settings (Traefik, hostPath volumes, `nodeSelector` pins) stay in `deploy/minikube/`.

`tests/test_deploy_layout.py` enforces these.

## Publishing a path change

Argo CD reads the **pushed** `master`, and no Application syncs automatically. Live Applications keep their old paths until their specs are re-applied, so a path change takes these steps. Do not sync anything between the push and the re-apply, and never sync with prune.

```bash
# 1. Push the change, then point the live Applications at the new paths.
kubectl --context mk4 diff -f deploy/eks/applications/
kubectl --context mk4 apply -f deploy/eks/applications/
./deploy-argocd.sh status --context mk4                         # warns about Minikube apps with stale specs

# 2. The Minikube add-ons are Terraform releases, not Applications (minikube-infrastructure/README.md).
terraform -chdir=minikube-infrastructure apply -var-file=vars/mk4.tfvars

# 3. Check the EKS apps show no change, then sync them.
for a in letsencrypt-issuers ingress bootstrap; do
  argocd app diff argocd/roboshop-demo-$a; argocd app sync argocd/roboshop-demo-$a
done
kubectl --context mk4 -n argocd get applications.argoproj.io
```

Until step 1, every Application that reads `tools` shows a `ComparisonError` for a path that does not exist. Running workloads are not affected.

## What is outside this directory

| Path | Contents |
|---|---|
| `infrastructure/` | Terraform for AWS, including the EKS cluster, its add-ons and IAM. Applies on push to `master`, including comment-only changes. |
| `roboshop-ai/argocd-eks` | RoboShop's Applications, namespace, shared config and mesh policy. **Still Kustomize:** its 15 Applications carry inline `kustomize.patches`, and `apps/mesh`, `apps/roboshop` and `apps/kustomization.yaml` are Kustomize directories. |
| `jithendar.com`, `moks` | Their own Applications and manifests. |

## Tests

```bash
python3 scripts/argocd/validate.py
python3 -m pytest -q tests deploy/minikube/test-*.py
```

Both need the roboshop-ai and jithendar.com checkouts beside this repository.
