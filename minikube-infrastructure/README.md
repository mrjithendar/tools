# minikube-infrastructure: cluster add-ons on mk4 (Terraform Helm releases)

Terraform root for the Minikube cluster `mk4`, beside `infrastructure/` (AWS). One Helm release per file. These are
not Argo CD Applications.

| File | Release | Chart | Namespace | Values |
|---|---|---|---|---|
| `metrics-server.tf` | `metrics-server` | kubernetes-sigs `metrics-server` 3.14.0 | `kube-system` | `deploy/minikube/metrics-server/values.yaml` |
| `cert-manager.tf` | `cert-manager` | `oci://quay.io/jetstack/charts/cert-manager` v1.20.4, CRDs included | `cert-manager` | `deploy/minikube/cert-manager/values.yaml` |
| `argocd.tf` | `argocd` | argo-helm `argo-cd` 10.10.5 | `argocd` | `deploy/minikube/argocd/values.yaml` |
| `kong.tf` | `kong`, only when `kong_enabled` | local chart `deploy/minikube/kong` (Kong 3.9.4 + its PostgreSQL) | `kong` | none: plain manifests in `templates/` |

| Other files | What |
|---|---|
| `versions.tf`, `variables.tf` | provider, S3 backend, `kubeconfig_path` (`~/.kube/config`), `kube_context` (`mk4`), `helm_timeout` (600 s), `kong_enabled` (`false`) |
| `vars/mk4.tfvars` | the values CI applies; `kong_enabled` is switched here for the Kong cutover |
| `tests/` | `terraform test` with a mock provider |
| `ci/github-terraform-serviceaccount.yaml` | CI's identity on mk4, applied once by `scripts/setup-minikube-terraform-ci.sh` |

Not here: the ClusterIssuers (jithendar.com `minikube/45-jithendar-letsencrypt.yaml`), Traefik
(`scripts/argocd/bootstrap.py`), Argo CD's Traefik Ingress (`deploy/minikube/argocd/kustomization.yaml`) and every
Argo CD Application (`deploy/minikube/applications`).

State is in S3 (`s3://jithendardharmapuri/terraform/minikube-mk4.tfstate`, same bucket as `infrastructure/`, own key).
By hand, from the repository root, with AWS credentials and a kubeconfig that has the `mk4` context:

```bash
terraform -chdir=minikube-infrastructure init
terraform -chdir=minikube-infrastructure plan -var-file=vars/mk4.tfvars
terraform -chdir=minikube-infrastructure apply -var-file=vars/mk4.tfvars
```

Checks without a cluster: `terraform init -backend=false && terraform validate && terraform test -var-file=vars/mk4.tfvars`.
`python3 -m pytest tests/test_kong_seed.py` (repository root) renders the Kong chart with `helm template`.

## CI

| Workflow | When | Runner | Does |
|---|---|---|---|
| `.github/workflows/minikube-terraform-check.yml` | pull requests touching this folder, the three values files or `deploy/minikube/kong` | GitHub-hosted, no secrets | fmt, validate, `terraform test`, `helm lint`/`template` of the Kong chart |
| `.github/workflows/minikube-terraform-apply.yml` | push to `master` (same paths), or run by hand | GitHub-hosted, environment `mk4` | fmt, validate, test, plan, apply, all with `vars/mk4.tfvars` |

The apply job runs only when repository variable `MINIKUBE_TERRAFORM_APPLY` is `true`. Its access:

- **mk4:** ServiceAccount `kube-system/github-minikube-terraform`, bound to `cluster-admin` (CRDs, ClusterRoles and
  webhooks need it). Its token is a secret of the environment `mk4`, which only `master` can deploy to, so pull
  request jobs never see it. API endpoint `MK4_API_SERVER` (`https://jithendar.com:32771`, the one jithendar.com's CI
  uses). Revoke: `kubectl --context mk4 -n kube-system delete secret github-minikube-terraform-token`.
- **State:** AWS role `github-tools-minikube-terraform` through GitHub OIDC, only for `repo:mrjithendar/tools:environment:mk4`,
  only the state object and its `.tflock` (`infrastructure/github-minikube-terraform.tf`). No AWS key is stored.

Turning it on (once):

1. Merge to `master`; the AWS workflow `create-infrastructure.yml` creates the role.
2. `scripts/setup-minikube-terraform-ci.sh` (applies the ServiceAccount, creates the environment, stores the token and
   the variables `MK4_API_SERVER`, `MK4_CA_DATA`, `MK4_TERRAFORM_ROLE_ARN`).
3. The move below, steps 1–6 (by hand, once).
4. `gh variable set MINIKUBE_TERRAFORM_APPLY --repo mrjithendar/tools --body true`. From then on, pushes that change
   this folder or the values apply them; run the workflow by hand to check for drift.

## Kong needs its Secret first

`bash deploy/minikube/kong/create-secrets.sh` creates the namespace `kong` and Secret `kong-postgres` once. Without
it the Kong and PostgreSQL pods cannot start and the `kong` release times out (15 minutes) and is marked failed.
The release starts Kong beside Traefik; traffic only moves when HAProxy is switched
(`docs/kong/06-cutover-runbook.md`). So `kong_enabled` stays `false` in `vars/mk4.tfvars` until that window, and
CI cannot start Kong early.

The release never deletes the database: the PVC `kong-postgres-data` and StorageClass `standard-retain` carry
`helm.sh/resource-policy: keep`, so `terraform destroy` leaves them, and the class's `Retain` keeps the volume even
if the PVC is deleted by hand.

## Moving the live mk4 add-ons to Terraform (once)

State on 2026-11-05, read from mk4:

- `metrics-server`: Argo CD Application `metrics-server`, no Helm release. No finalizer on the Application.
- `cert-manager`: applied by an earlier Argo CD Application that no longer exists, no Helm release.
- Argo CD: Helm release `argocd` revision 1, status `pending-install` since 2026-10-27. Helm refuses to upgrade a
  pending release, and Terraform cannot install over it.
- Kong: not deployed.

Every release in Terraform sets `take_ownership`: Helm adopts the running objects and patches only the fields the
chart renders. Fields that exist only on the live objects stay, so `argocd-secret` keeps `admin.password` and
`server.secretkey`, which the chart does not render. Nothing is deleted or recreated.

`K="kubectl --context mk4"`. Keep backups outside `My Drive/Work`, which syncs to Google Drive.

| # | Action | Check | Pass |
|---|---|---|---|
| 1 | Back up: `mkdir -p ~/Backups/mk4-terraform && chmod 700 ~/Backups/mk4-terraform && $K -n argocd get secret sh.helm.release.v1.argocd.v1 argocd-secret -o yaml > ~/Backups/mk4-terraform/argocd-secrets.yaml && $K -n argocd get application metrics-server -o yaml > ~/Backups/mk4-terraform/metrics-server-app.yaml` | `ls -l ~/Backups/mk4-terraform` | both files non-empty |
| 2 | Remove the Application, keep its workloads: `$K -n argocd delete application metrics-server` | `$K -n kube-system get deploy metrics-server`; `$K top nodes` | Deployment still `1/1`; node metrics print |
| 3 | Remove Helm's stuck `pending-install` record for Argo CD (only the record; Argo CD keeps running): `$K -n argocd delete secret sh.helm.release.v1.argocd.v1` | `helm --kube-context mk4 -n argocd list -a`; `$K -n argocd get pods` | no `argocd` release; pods still Running |
| 4 | `terraform -chdir=minikube-infrastructure init`, then `terraform -chdir=minikube-infrastructure apply -var-file=vars/mk4.tfvars` (Kong stays off) | `helm --kube-context mk4 list -A` | `metrics-server`, `cert-manager`, `argocd` all `deployed` |
| 5 | Verify the add-ons | `$K top pods -A \| head -3`; `$K get certificate -A`; `$K -n argocd get applications`; sign in at https://jithendar.com/argocd/ | metrics print; certificates `True`; applications listed; the old admin password still works |
| 6 | Shrink the AppProject (Argo CD's `deploy.py` never updates an existing project): `$K apply -f deploy/minikube/applications/project-mk-platform.yaml` | `$K -n argocd get appproject mk-platform -o jsonpath='{.spec.destinations[*].namespace}'` | no `kube-system`, no `cert-manager` |
| 7 | Kong, in the cutover window: `bash deploy/minikube/kong/create-secrets.sh`, set `kong_enabled = true` in `vars/mk4.tfvars` and push (CI applies) or apply by hand | `docs/kong/06-cutover-runbook.md` step 3 | as written there |

If step 4 fails with `invalid ownership metadata` or `cannot re-use a name`, run step 3 (or 2) first. If it fails
part-way, run it again; Helm adopts what it has not yet adopted. To undo step 3, re-apply the backup:
`$K apply -f ~/Backups/mk4-terraform/argocd-secrets.yaml` (this also restores the `argocd-secret` as backed up).

Afterwards the objects still carry Argo CD's `argocd.argoproj.io/tracking-id` annotation from the old Applications.
No Application claims them, so Argo CD ignores it.
