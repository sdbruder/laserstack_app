#!/bin/bash
set -euo pipefail
# IFS=$'\n\t'

# load .env
if [ -f .env ]; then
    export $(echo $(cat .env | sed 's/#.*//g'| xargs) | envsubst)
fi

base_dir="$(dirname "$(readlink -f "$BASH_SOURCE")")"

# versions the build must not touch, from .buildx-skip: one directory name per line
skip_patterns=""
if [ -f "$base_dir/.buildx-skip" ]; then
    skip_patterns="$(awk '/^[0-9]+\.[0-9]+$/{printf "%s%s", sep, $0; sep="|"}' "$base_dir/.buildx-skip")"
fi

docker login --username "$HUB_USER" --password "$HUB_PASSWORD"
for version in $(ls -r -d */ | cut -f1 -d'/' | xargs) ; do
    if [ -n "$skip_patterns" ] && echo "$version" | grep -qE "^($skip_patterns)$"; then
        echo "skip $version (.buildx-skip)"
        continue
    fi
    if [ "$APP_LATEST" == "$version" ]; then
        EXTRA="--tag laserstack/app:latest"
    else
        EXTRA=""
    fi
    cd $base_dir/$version
    echo "$version ----------------------------"
    docker build --tag laserstack/app:$version $EXTRA .
done

docker push --all-tags laserstack/app

