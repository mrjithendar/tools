#!/usr/bin/env bash
# Build Harbor's own images for linux/arm64 from the official source and push them to ECR.
#
# goharbor publishes amd64 images only, and every mk4 node is arm64. This builds the images values.yaml uses from
# the pinned Harbor tag with Harbor's own Makefile, on a native arm64 Docker host (GitHub's ubuntu-24.04-arm runner,
# .github/workflows/build-harbor-images.yml, or an Apple Silicon Mac). It refuses to run on the mk4 host: image
# builds there froze the cluster twice (runner/README.md).
#
# Usage: bash deploy/minikube/harbor/build-images.sh [--with-trivy] [--no-push]
# Env:   AWS_REGION (us-east-1), ECR_PREFIX (harbor). AWS credentials need ecr:GetAuthorizationToken and push
#        rights on <ECR_PREFIX>/*, plus ecr:CreateRepository the first time.
set -euo pipefail

HARBOR_VERSION=v2.15.4
HARBOR_COMMIT=0a6bf30d54e779962ad5b862fc67e3e9f6b010d8   # git rev-parse v2.15.4^{commit}
TRIVY_VERSION=v0.75.0                                     # TRIVYVERSION in that tag's Makefile
AWS_REGION="${AWS_REGION:-us-east-1}"
ECR_PREFIX="${ECR_PREFIX:-harbor}"
WITH_TRIVY=false
PUSH=true

fail() { echo "ERROR: $*" >&2; exit 1; }
for arg in "$@"; do
  case "$arg" in
    --with-trivy) WITH_TRIVY=true ;;
    --no-push) PUSH=false ;;
    -h|--help) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) fail "unknown argument: $arg" ;;
  esac
done

for command in docker git make; do
  command -v "$command" >/dev/null || fail "$command is required"
done
docker compose version >/dev/null 2>&1 || fail 'the Docker Compose plugin is required (make/checkenv.sh checks for it)'
[ "$(docker version --format '{{.Server.Arch}}')" = arm64 ] || fail 'the Docker server must be arm64 (native, not emulated)'
if docker ps --format '{{.Names}}' | grep -qx mk4; then
  fail 'this is the mk4 host: build elsewhere (see runner/README.md)'
fi
if $PUSH; then
  command -v aws >/dev/null || fail 'aws CLI is required to push (or pass --no-push)'
fi

# What values.yaml deploys. db, valkey, nginx and the exporter are not used (README.md); the exporter cannot
# build for arm64 at this tag (make/photon/exporter/Dockerfile sets GOARCH=amd64).
TARGETS="_build_portal _build_core _build_jobservice _build_registry _build_registryctl"
IMAGES="harbor-portal harbor-core harbor-jobservice registry-photon harbor-registryctl"
if $WITH_TRIVY; then
  TARGETS="$TARGETS _build_trivy_adapter"
  IMAGES="$IMAGES trivy-adapter-photon"
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$HARBOR_VERSION" https://github.com/goharbor/harbor.git "$WORK/harbor"
cd "$WORK/harbor"
[ "$(git rev-parse HEAD)" = "$HARBOR_COMMIT" ] || fail "$HARBOR_VERSION does not point at $HARBOR_COMMIT any more"

# Harbor's base images start FROM goharbor/photon:5.0-legacy, which Docker Hub has for amd64 only. Build it
# here the way Harbor's release workflow does (.github/workflows/build-package.yml); with
# PULL_BASE_FROM_DOCKERHUB=false no later step pulls the amd64 copy over it.
docker build --quiet -f make/photon/common/Dockerfile -t goharbor/photon:5.0-legacy .

make compile build \
  VERSIONTAG="$HARBOR_VERSION" BASEIMAGETAG="$HARBOR_VERSION" PKGVERSIONTAG="$HARBOR_VERSION" \
  BUILD_BASE=true PULL_BASE_FROM_DOCKERHUB=false PUSHBASEIMAGE=false \
  BUILDREG=true BUILD_INSTALLER=false EXPORTERFLAG=false \
  TRIVYFLAG="$WITH_TRIVY" BUILDTRIVYADP=true \
  TRIVY_DOWNLOAD_URL="https://github.com/aquasecurity/trivy/releases/download/$TRIVY_VERSION/trivy_${TRIVY_VERSION#v}_Linux-ARM64.tar.gz" \
  GOBUILDTAGS="include_oss include_gcs" \
  BUILDTARGET="$TARGETS"

for image in $IMAGES; do
  arch="$(docker image inspect --format '{{.Architecture}}' "goharbor/$image:$HARBOR_VERSION")"
  [ "$arch" = arm64 ] || fail "goharbor/$image:$HARBOR_VERSION is $arch, not arm64"
  echo "built goharbor/$image:$HARBOR_VERSION ($arch)"
done
$PUSH || { echo 'Not pushed (--no-push).'; exit 0; }

ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
REGISTRY="$ACCOUNT.dkr.ecr.$AWS_REGION.amazonaws.com"
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$REGISTRY" >/dev/null
for image in $IMAGES; do
  repository="$ECR_PREFIX/$image"
  if ! aws ecr describe-repositories --region "$AWS_REGION" --repository-names "$repository" >/dev/null 2>&1; then
    aws ecr create-repository --region "$AWS_REGION" --repository-name "$repository" \
      --image-tag-mutability MUTABLE --encryption-configuration encryptionType=AES256 >/dev/null
    echo "created ECR repository $repository"
  fi
  docker tag "goharbor/$image:$HARBOR_VERSION" "$REGISTRY/$repository:$HARBOR_VERSION"
  docker push --quiet "$REGISTRY/$repository:$HARBOR_VERSION"
done
docker logout "$REGISTRY" >/dev/null
echo "Pushed to $REGISTRY/$ECR_PREFIX/*:$HARBOR_VERSION. values.yaml expects that registry and tag."
