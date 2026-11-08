# Deployment files

| Directory | Cluster | kubectl context | Deployed with | Guide |
|---|---|---|---|---|
| [`eks/`](eks/) | `roboshop-demo` (AWS EKS) | `roboshop-demo`, and `mk4` for the Argo CD hub | Argo CD reading plain YAML; Helm charts for add-ons | [eks/DEPLOY.md](eks/DEPLOY.md) |

The Minikube cluster `mk4` (install scripts, Traefik, Argo CD, the Terraform add-ons and its Argo CD catalog) moved to its
own repository, [mrjithendar/miniKube](https://github.com/mrjithendar/miniKube), on 2026-11-08. Clone it beside this one.
RoboShop workloads are in neither: they live in `roboshop-ai/argocd-eks`. See [What is outside this directory](#what-is-outside-this-directory).

## Rules

- Never run `kubectl apply` on `deploy/`, `deploy/eks/` or `deploy/eks/manifests/`. Name the leaf directory, and pass `--context` every time.
- `deploy/eks/` never reads a file from the miniKube repository, or the reverse. Copy a setting if both need it.
- `deploy/eks/` has no Kustomize and no templating of its own manifests. Every file in `deploy/eks/manifests/` is one complete object with its namespace, so what you read is what is applied. Add-on charts stay Helm charts, with values in `deploy/eks/helm-values/`.
- `deploy/eks/applications/` goes to the `mk4` hub, not to EKS. Everything in `deploy/eks/manifests/` goes to EKS.
- Secrets are never in Git. Templates are in `deploy/eks/examples/`, which nothing applies. A `*.yaml.example` file is skipped by `kubectl apply -f` and by Argo CD. Filled-in `*-secret.yaml` files under `deploy/` are gitignored.
- AWS settings (NLB annotations, subnets, VPC ID, `alb` IngressClass, Pod Identity) stay in `deploy/eks/` and `infrastructure/`. Local settings (Traefik, hostPath volumes, `nodeSelector` pins) stay in the miniKube repository.

`tests/test_deploy_layout.py` enforces these.

## Publishing a path change

Argo CD reads the **pushed** `master`, and no Application syncs automatically. Live Applications keep their old paths until their specs are re-applied, so a path change takes these steps. Do not sync anything between the push and the re-apply, and never sync with prune.

```bash
# 1. Push the change, then point the live Applications at the new paths.
kubectl --context mk4 diff -f deploy/eks/applications/
kubectl --context mk4 apply -f deploy/eks/applications/

# 2. Check the EKS apps show no change, then sync them.
for a in letsencrypt-issuers ingress bootstrap; do
  argocd app diff argocd/roboshop-demo-$a; argocd app sync argocd/roboshop-demo-$a
done
kubectl --context mk4 -n argocd get applications.argoproj.io
```

Until step 1, every Application that reads `tools` shows a `ComparisonError` for a path that does not exist. Running workloads are not affected.

## What is outside this directory

| Path | Contents |
|---|---|
| `infrastructure/` | Terraform for AWS, including the EKS cluster, its add-ons and IAM, and the OIDC role the miniKube repository's CI uses for its state. Applies on push to `master`, including comment-only changes. |
| `../miniKube` | The `mk4` Minikube cluster: `deploy/minikube/`, `minikube-infrastructure/`, `scripts/argocd/` and the root wrappers (`deploy-argocd.sh`, `bootstrap-cluster.sh`, …). |
| `roboshop-ai/argocd-eks` | RoboShop's Applications, namespace, shared config and mesh policy. **Still Kustomize:** its 15 Applications carry inline `kustomize.patches`, and `apps/mesh`, `apps/roboshop` and `apps/kustomization.yaml` are Kustomize directories. |
| `jithendar.com`, `moks` | Their own Applications and manifests. |

## Tests

```bash
python3 -m pytest -q tests
```

They need the roboshop-ai checkout beside this repository; the two tests that compare EKS with mk4 (`test_loki.py`, one in
`test_eks_platform.py`) also read `../miniKube` (or `MINIKUBE_DIR`) and skip without it.
