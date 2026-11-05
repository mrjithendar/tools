#!/usr/bin/env bash
# Connects host ports to the selected local Minikube ingress endpoints.
# TCP forwarding leaves TLS termination to the in-cluster gateway: Kong (INGRESS_TARGET=kong) or, for rollback,
# Traefik (INGRESS_TARGET=traefik). The target must be named: rerunning must never switch traffic by accident. This changes host networking;
# it does not create DNS records or prove that upstream firewalls allow traffic.

# Validate the supported host before operational side effects.
if [ -z "${BASH_VERSION:-}" ]; then exec bash "$0" "$@"; fi
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/lib/require-centos.sh"
roboshop_require_centos "${1:-}" linux || exit 1
# Run on the Linux Docker/Minikube host, never on the remote Mac client.
# HAProxy forwards TCP with a PROXY protocol v2 header (client IP); the gateway handles TLS.
# Kong: HTTP 31080, HTTPS 31443, and PostgreSQL-over-TLS 31543 for SNI db.jithendar.com (HAProxy reads the SNI from
# the TLS ClientHello without decrypting; Kong serves HTTP and stream traffic on separate ports, Traefik on one).
set -euo pipefail
fail() { echo "ERROR: $*" >&2; exit 1; }
if [[ "${1:-}" == --help ]]; then
  echo 'Usage (on the host): INGRESS_TARGET=kong bash deploy/minikube/expose-ingress.sh'
  echo '       rollback:      INGRESS_TARGET=traefik bash deploy/minikube/expose-ingress.sh'
  echo 'Overrides: PROFILE=mk4. Uses the selected local Minikube Docker node.'
  exit 0
fi
[[ $# == 0 ]] || fail 'No positional arguments expected.'
INGRESS_TARGET="${INGRESS_TARGET:-}"
[[ "$INGRESS_TARGET" == kong || "$INGRESS_TARGET" == traefik ]] || fail 'Set INGRESS_TARGET=kong or INGRESS_TARGET=traefik.'
[[ "$(uname -s)" == Linux ]] || fail 'Run this script on the Vultr Linux host, not your Mac.'
export PATH="/usr/local/bin:$HOME/.local/bin:$PATH"
for command in docker kubectl; do command -v "$command" >/dev/null || fail "$command is required."; done
PROFILE="${PROFILE:-mk4}"
[[ "$PROFILE" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]] || fail 'Invalid PROFILE.'
state_dir="${MINIKUBE_HOME:-$HOME/.minikube}/roboshop-installer"
if [[ -f "$state_dir/$PROFILE.profile" ]]; then PROFILE="$(cat "$state_dir/$PROFILE.profile")"; fi
[[ "$PROFILE" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]] || fail 'Invalid selected profile.'
# Require a local Docker daemon: bind-mounted files and published ports belong here.
endpoint="${DOCKER_HOST:-$(docker context inspect --format '{{.Endpoints.docker.Host}}')}"
[[ "$endpoint" == unix://* ]] || fail 'Use the local Docker daemon on Vultr (unix socket).'
[[ "$(docker inspect --format '{{.State.Running}}' "$PROFILE")" == true ]] || fail "Local Minikube node $PROFILE is not running."
network="$(docker inspect --format '{{range $name, $details := .NetworkSettings.Networks}}{{println $name}}{{end}}' "$PROFILE")"
[[ "$network" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]] || fail 'Expected exactly one Docker network on the Minikube node.'
if [[ "$INGRESS_TARGET" == traefik ]]; then
  kubectl --context="$PROFILE" -n traefik rollout status deployment/traefik --timeout=120s
  # HAProxy sends the PROXY protocol (real client IPs for the IP allowlists and the apps' logs). Traefik must
  # already accept it (traefik/values.yaml, proxyProtocol.trustedIPs), or every connection would fail.
  kubectl --context="$PROFILE" -n traefik get deployment traefik -o jsonpath='{.spec.template.spec.containers[0].args}' \
    | grep -q 'websecure.proxyProtocol.trustedIPs' || fail 'Traefik does not accept the PROXY protocol yet: run deploy-traefik.sh first.'
  http_port=30080; https_port=30443; postgres_port=''
else
  kubectl --context="$PROFILE" -n kong rollout status deployment/kong --timeout=120s
  # Kong's public listeners require the PROXY protocol (kong/kong-config.yaml); refuse to switch otherwise.
  kubectl --context="$PROFILE" -n kong get configmap kong-config -o jsonpath='{.data.KONG_PROXY_LISTEN}' \
    | grep -q '8443 http2 ssl proxy_protocol' || fail 'Kong does not accept the PROXY protocol on 8443.'
  # An empty database would answer 404 for every site: require the seeded routes (docs/kong/06-cutover-runbook.md).
  kubectl --context="$PROFILE" -n kong exec deploy/kong -c kong -- \
    kong health >/dev/null || fail 'Kong is not healthy.'
  # Ask the Admin API on the pod's loopback through the cert-sync sidecar (it has Python; the Kong image has no curl).
  routes="$(kubectl --context="$PROFILE" -n kong exec deploy/kong -c cert-sync -- python3 -I -c \
    'import urllib.request; print(urllib.request.urlopen("http://127.0.0.1:8001/routes/jithendar-com", timeout=5).read().decode())' \
    2>/dev/null | grep -o '"seed:v1"' || true)"
  [[ -n "$routes" ]] || fail 'Kong has no seeded jithendar-com route yet: import kong-config/seed/kong.yaml first.'
  http_port=31080; https_port=31443; postgres_port=31543
fi
name="roboshop-ingress-edge-$(id -u)"
label='roboshop.minikube.ingress-owner'
config_dir="$state_dir/ingress-edge"
mkdir -p "$config_dir"
config="$config_dir/haproxy.cfg"
cat > "$config.tmp" <<CONFIG
global
  log stdout format raw local0
  maxconn 2048
defaults
  log global
  mode tcp
  timeout connect 10s
  timeout client 1h
  timeout server 1h
resolvers docker
  nameserver dns 127.0.0.11:53
  resolve_retries 3
  timeout resolve 1s
  timeout retry 1s
  hold valid 10s
frontend http
  bind :8080
  default_backend minikube_http
backend minikube_http
  server node $PROFILE:$http_port send-proxy-v2 check resolvers docker init-addr libc,none
frontend https
  bind :8443
  # Wait for the TLS ClientHello to read its SNI (used only when Kong is the target).
  tcp-request inspect-delay 5s
  tcp-request content accept if { req.ssl_hello_type 1 }
$( [[ -n "$postgres_port" ]] && echo '  use_backend minikube_postgres if { req.ssl_sni -i db.jithendar.com }' || true )
  default_backend minikube_https
backend minikube_https
  server node $PROFILE:$https_port send-proxy-v2 check resolvers docker init-addr libc,none
$( [[ -n "$postgres_port" ]] && printf 'backend minikube_postgres\n  server node %s:%s send-proxy-v2 check resolvers docker init-addr libc,none\n' "$PROFILE" "$postgres_port" || true )
CONFIG
# Pin the supported HAProxy 3.2 maintenance line. No TLS keys live in this container.
image=haproxy:3.2-alpine
docker run --rm --network "$network" -v "$config_dir:/usr/local/etc/haproxy:ro,z" \
  "$image" haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg.tmp
if docker container inspect "$name" >/dev/null 2>&1; then
  owner="$(docker inspect --format "{{index .Config.Labels \"$label\"}}" "$name")"
  [[ "$owner" == "$(id -u)" ]] || fail "Container $name belongs to another setup; leaving it untouched."
  existing_network="$(docker inspect --format '{{range $name, $details := .NetworkSettings.Networks}}{{println $name}}{{end}}' "$name")"
  [[ "$existing_network" == "$network" ]] || fail "The proxy belongs to another Docker network. Remove only $name when ready to replace it, then rerun."
  mv "$config.tmp" "$config"
  docker restart "$name" >/dev/null
else
  mv "$config.tmp" "$config"
  docker run -d --name "$name" --restart unless-stopped --network "$network" \
    --label "$label=$(id -u)" --security-opt no-new-privileges:true \
    -p 80:8080 -p 443:8443 -v "$config_dir:/usr/local/etc/haproxy:ro,z" "$image" >/dev/null || \
    fail "Could not publish ports 80/443. Check existing listeners; do not stop unrelated services. Inspect/remove failed container $name before retrying."
fi
[[ "$(docker inspect --format '{{.State.Running}}' "$name")" == true ]] || fail "Proxy failed; inspect docker logs $name."
echo "Host ports 80/443 now forward to $INGRESS_TARGET on $PROFILE via $name."
echo 'Allow TCP 80/443 in the Vultr firewall and point jithendar.com DNS to this server.'
echo 'Kong entities are managed in Kong Manager (docs/kong/03-admin-access.md); rollback: docs/kong/07-rollback-runbook.md.'
