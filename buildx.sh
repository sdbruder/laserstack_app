#!/bin/bash
set -euo pipefail
# IFS=$'\n\t'

# load .env
if [ -f .env ]; then
    export $(echo $(cat .env | sed 's/#.*//g'| xargs) | envsubst)
fi

base_dir="$(dirname "$(readlink -f "$BASH_SOURCE")")"

docker login --username "$HUB_USER" --password "$HUB_PASSWORD"
docker buildx create --name laserbuilder --use --bootstrap

for version in $(ls -r -d */ | cut -f1 -d'/' | xargs) ; do
    if [ "$APP_LATEST" == "$version" ]; then
        EXTRA="--tag laserstack/app:latest"
    else
        EXTRA=""
    fi
    cd $base_dir/$version
    echo "$version ----------------------------"
    docker buildx build 			\
    	--push					\
	--platform linux/amd64,linux/arm64 	\
	--tag laserstack/app:$version $EXTRA 	\
	.
done
docker buildx rm laserbuilder
