#!/bin/bash
set -euo pipefail

# Builds the production overlay of prod/Dockerfile. Run it from anywhere; the
# build context is the repository root, so examples/ and prod/ are included.
#
#   ./prod/build.sh --update                     resolve the base digest, write prod/digests.lock
#   APP_DOMAIN=app.example.com ./prod/build.sh   build from the pinned digest
#   APP_DOMAIN=app.example.com ./prod/build.sh --push --scan --sign
#
# Flags:
#   --update  resolve the digest of the base tag, write the lock, then stop
#   --check   resolve the digest, compare it with the lock, then stop
#             (exit 1 when the base moved: use it in CI)
#   --push    build linux/amd64 and linux/arm64, and push
#   --scan    scan the image, needs trivy or grype, fails on HIGH and CRITICAL
#   --sign    sign the pushed image, needs cosign and --push
#   --help
#
# Environment:
#   PHP_SERIES=8.5            base PHP series, must match the lock
#   APP_DOMAIN                server_name of the app, required
#   IMAGE=laserstack/app-prod  image repository
#   TAG=8.5                   image tag
#   TRUST_FORWARDED_PROTO=0   1 when a balancer terminates TLS
#   TRUSTED_PROXY=10.0.0.0/8  the balancer range, with TRUST_FORWARDED_PROTO=1
#   PHP_MAX_CHILDREN=16       php-fpm pm.max_children, at least 8
#   HEALTH_PATH=/             path the health check requests

base_dir="$(cd "$(dirname "$0")" && pwd)"
repo_dir="$(dirname "$base_dir")"
lock="$base_dir/digests.lock"

php_series="${PHP_SERIES:-8.5}"
base_tag="laserstack/app:${php_series}"
image="${IMAGE:-laserstack/app-prod}"
tag="${TAG:-$php_series}"

# the .env of the repository root, the same file buildx.sh reads
if [ -f "$repo_dir/.env" ]; then
  export $(echo $(cat "$repo_dir/.env" | sed 's/#.*//g' | xargs) | envsubst)
fi

die() { echo "build.sh: $*" >&2; exit 2; }

action=build
push=0
scan=0
sign=0
for arg in "$@"; do
  case "$arg" in
    --update) action=update ;;
    --check)  action=check ;;
    --push)   push=1 ;;
    --scan)   scan=1 ;;
    --sign)   sign=1 ;;
    --help)   sed -n '3,30p' "$0"; exit 0 ;;
    *)        die "unknown argument '$arg', try --help" ;;
  esac
done

# the digest that the moving base tag points at, right now
resolve() {
  local digest
  digest="$(docker buildx imagetools inspect "$base_tag" --format '{{.Manifest.Digest}}')" \
    || die "cannot resolve $base_tag, check the network and the docker login"
  case "$digest" in
    sha256:*) printf '%s' "$digest" ;;
    *) die "unexpected digest '$digest' for $base_tag" ;;
  esac
}

write_lock() {
  local digest="$1" tmp="$lock.tmp"
  {
    echo "# base image of the production overlay, written by prod/build.sh --update"
    echo "# commit this file: it is what makes a rebuild reproducible"
    echo "php_series=$php_series"
    echo "base_image=$base_tag"
    echo "base_digest=$digest"
    echo "resolved_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } > "$tmp"
  mv "$tmp" "$lock"
  echo "build.sh: $base_tag pinned to $digest"
}

lock_series=""
lock_image=""
lock_digest=""

read_lock() {
  [ -f "$lock" ] || die "no prod/digests.lock, run ./prod/build.sh --update first"
  lock_series="$(awk -F= '$1=="php_series"{print $2}' "$lock")"
  lock_image="$(awk -F= '$1=="base_image"{print $2}' "$lock")"
  lock_digest="$(awk -F= '$1=="base_digest"{print $2}' "$lock")"
  [ "$lock_series" = "$php_series" ] \
    || die "the lock pins PHP $lock_series, not $php_series, run --update"
  [ -n "$lock_image" ] \
    || die "the lock has no base_image, run --update"
  case "$lock_digest" in
    sha256:*) ;;
    *) die "the lock has no base_digest, run --update" ;;
  esac
}

case "$action" in
  update)
    write_lock "$(resolve)"
    exit 0
    ;;
  check)
    read_lock
    now="$(resolve)"
    if [ "$now" = "$lock_digest" ]; then
      echo "build.sh: $lock_image is still $lock_digest"
    else
      echo "build.sh: $lock_image moved: lock $lock_digest, registry $now" >&2
      exit 1
    fi
    exit 0
    ;;
esac

read_lock

[ -n "${APP_DOMAIN:-}" ] \
  || die "set APP_DOMAIN, for example APP_DOMAIN=app.example.com ./prod/build.sh"
case "${TRUST_FORWARDED_PROTO:-0}" in
  0|1) ;;
  *) die "TRUST_FORWARDED_PROTO must be 0 or 1" ;;
esac
[ "${PHP_MAX_CHILDREN:-16}" -ge 8 ] || die "PHP_MAX_CHILDREN must be at least 8"

# fail before the build when a requested tool is missing
if [ "$scan" = 1 ]; then
  command -v trivy >/dev/null || command -v grype >/dev/null \
    || die "--scan needs trivy or grype in PATH"
fi
if [ "$sign" = 1 ]; then
  [ "$push" = 1 ] || die "--sign needs --push"
  command -v cosign >/dev/null || die "--sign needs cosign in PATH"
fi

# the tag for the reader, the digest for docker: this is the pin
pinned_ref="$lock_image@$lock_digest"

build_args=(
  --file "$base_dir/Dockerfile"
  --tag "$image:$tag"
  --build-arg "BASE_IMAGE=$pinned_ref"
  --build-arg "BASE_DIGEST=$lock_digest"
  --build-arg "PHP_SERIES=$php_series"
  --build-arg "APP_DOMAIN=$APP_DOMAIN"
  --build-arg "TRUST_FORWARDED_PROTO=${TRUST_FORWARDED_PROTO:-0}"
  --build-arg "TRUSTED_PROXY=${TRUSTED_PROXY:-10.0.0.0/8}"
  --build-arg "PHP_MAX_CHILDREN=${PHP_MAX_CHILDREN:-16}"
  --build-arg "HEALTH_PATH=${HEALTH_PATH:-/}"
)

if [ "$push" = 1 ]; then
  docker buildx create --name laserprod --use --bootstrap >/dev/null
  trap 'docker buildx rm laserprod >/dev/null 2>&1 || true' EXIT
  build_args+=(--platform linux/amd64,linux/arm64 --push)
else
  build_args+=(--load)
fi

docker buildx build "${build_args[@]}" "$repo_dir"
echo "build.sh: built $image:$tag from $pinned_ref"

ref="$image:$tag"
digest=""
if [ "$push" = 1 ]; then
  digest="$(docker buildx imagetools inspect "$ref" --format '{{.Manifest.Digest}}')"
  echo "build.sh: pushed $ref as $digest"
fi

if [ "$scan" = 1 ]; then
  if command -v trivy >/dev/null; then
    trivy image --severity HIGH,CRITICAL --exit-code 1 "$ref"
  else
    grype "$ref" --fail-on high
  fi
fi

if [ "$sign" = 1 ]; then
  [ -n "$digest" ] || die "--sign needs the pushed digest"
  cosign sign --yes "$image@$digest"
  echo "build.sh: signed $image@$digest"
fi
