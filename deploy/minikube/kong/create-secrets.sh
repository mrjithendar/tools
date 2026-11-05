#!/usr/bin/env bash
# Creates Secret kong/kong-postgres (keys superuser-password, kong-password) with random values, once.
# Same mechanism as the rest of mk4: Secrets are created by a person with a script, never stored in Git
# (AppProjects blacklist Secrets). The values are generated here, sent straight to the API server, and never
# printed or written to disk.
#
# It refuses to replace an existing Secret: PostgreSQL stores the role passwords on first start, so a new
# Secret would lock Kong out. To rotate, follow docs/kong/05-backup-restore.md (ALTER ROLE, then update the Secret).
set -euo pipefail
CONTEXT="${KUBE_CONTEXT:-mk4}"
NAMESPACE=kong
[[ "${1:-}" == --help ]] && { echo "Usage: KUBE_CONTEXT=mk4 bash deploy/minikube/kong/create-secrets.sh"; exit 0; }
command -v kubectl >/dev/null || { echo "kubectl is required" >&2; exit 1; }
command -v openssl >/dev/null || { echo "openssl is required" >&2; exit 1; }
k() { kubectl --context="$CONTEXT" "$@"; }
k get namespace "$NAMESPACE" >/dev/null 2>&1 || k create namespace "$NAMESPACE"
if k -n "$NAMESPACE" get secret kong-postgres >/dev/null 2>&1; then
  echo "Secret $NAMESPACE/kong-postgres already exists; leaving it unchanged."
  exit 0
fi
gen() { openssl rand -base64 48 | tr -d '/+=\n' | cut -c1-40; }
# Values reach kubectl through a heredoc on stdin, not the command line, so they never show in `ps`.
k -n "$NAMESPACE" apply -f - <<EOF >/dev/null
apiVersion: v1
kind: Secret
metadata:
  name: kong-postgres
  namespace: $NAMESPACE
  labels: {app.kubernetes.io/part-of: kong-gateway}
type: Opaque
stringData:
  superuser-password: "$(gen)"
  kong-password: "$(gen)"
EOF
echo "Created Secret $NAMESPACE/kong-postgres (values not shown)."
