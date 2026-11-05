# Values for mk4, used by .github/workflows/minikube-terraform-apply.yml and by hand
# (terraform apply -var-file=vars/mk4.tfvars).
kube_context = "mk4"

# true starts Kong beside Traefik (docs/kong/06-cutover-runbook.md, step 3). Needs Secret
# kong/kong-postgres first: bash deploy/minikube/kong/create-secrets.sh.
kong_enabled = false
