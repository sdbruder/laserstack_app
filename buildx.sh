#!/bin/bash
set -euo pipefail
# IFS=$'\n\t'

# load .env
if [ -f .env ]; then
  export $(echo $(cat .env | sed 's/#.*//g' | xargs) | envsubst)
fi

base_dir="$(dirname "$(readlink -f "$BASH_SOURCE")")"

# versions the build must not touch, from .buildx-skip: one directory name per line
skip_patterns=""
if [ -f "$base_dir/.buildx-skip" ]; then
  skip_patterns="$(awk '/^[0-9]+\.[0-9]+$/{printf "%s%s", sep, $0; sep="|"}' "$base_dir/.buildx-skip")"
fi

# version directories, newest first, for example 8.5, 8.4, 7.4
versions="$(cd $base_dir && ls -d */ | cut -f1 -d'/' | grep -E '^[0-9]+\.[0-9]+$' | sort -rV)"
if [ -n "$skip_patterns" ]; then
  echo "skipped versions: $skip_patterns" | tr '|' ' '
  versions="$(printf '%s\n' "$versions" | grep -vE "^($skip_patterns)$" || true)"
fi
if [ -z "$versions" ]; then
  echo "buildx.sh: every version directory is skipped, nothing to build" >&2
  exit 2
fi

# the latest tag goes to the newest version directory that builds, unless APP_LATEST says otherwise
APP_LATEST="${APP_LATEST:-$(echo "$versions" | head -n1)}"

# optional build cache: BUILDX_CACHE=gha uses the GitHub Actions cache
CACHE_ARGS=""
case "${BUILDX_CACHE:-}" in
  gha) CACHE_ARGS="gha" ;;
  "") ;;
  *) echo "buildx.sh: unknown BUILDX_CACHE value '${BUILDX_CACHE}'" >&2; exit 2 ;;
esac

docker login --username "$HUB_USER" --password "$HUB_PASSWORD"
docker buildx create --name laserbuilder --use --bootstrap
for version in $versions; do
  if [ "$APP_LATEST" == "$version" ]; then
    EXTRA="--tag laserstack/app:latest"
  else
    EXTRA=""
  fi
  cd $base_dir/$version
  echo "$version ----------------------------"

  # the markers must match the start of a line: comments and ARG lines in the
  # Dockerfile mention the same names
  ALPINE=$(grep -m1 '^FROM ' Dockerfile | awk '{ print $2;}')
  PHP=$(grep -m1 '^#PHP ' Dockerfile | awk '{ print $2;}')
  # a series that lives outside main and community names its repository in an
  # ARG PHP_REPO line, so the resolution below installs the same package. awk
  # prints nothing and succeeds when a Dockerfile has no such line; grep exits 1
  # and set -e ends the script before the second version, so do not use grep here.
  PHP_REPO="$(awk -F\" '/^ARG PHP_REPO=/{print $2; exit}' Dockerfile)"
  repo_arg=""
  [ -n "$PHP_REPO" ] && repo_arg="--repository=$PHP_REPO"
  PHPVERSION=$(docker run --rm $ALPINE /bin/ash -c "apk add $repo_arg $PHP; $PHP --version" | grep ^PHP | awk '{print $2}')
  EXTRA="--tag laserstack/app:$PHPVERSION $EXTRA"

  if [ "$CACHE_ARGS" == "gha" ]; then
    cache="--cache-from type=gha,scope=$version --cache-to type=gha,mode=min,scope=$version"
  else
    cache=""
  fi

  # shellcheck disable=SC2086
  build() {
    docker \
      buildx build \
      --push \
      --platform linux/amd64,linux/arm64 \
      --tag laserstack/app:$version $EXTRA \
      $cache \
      .
  }

  if ! build; then
    if [ -n "$cache" ]; then
      # a broken cache must not block a release
      echo "build $version with cache failed, retry without cache" >&2
      cache=""
      build
    else
      exit 1
    fi
  fi
done
docker buildx rm laserbuilder
