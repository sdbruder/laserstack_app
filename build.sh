#!/bin/bash

# load .env
if [ -f .env ]; then
    export $(echo $(cat .env | sed 's/#.*//g'| xargs) | envsubst)
fi

base_dir="$(dirname "$(readlink -f "$BASH_SOURCE")")"

for version in $(ls -r -d */ | cut -f1 -d'/' | xargs) ; do
    cd $base_dir/$version
    echo "$version ----------------------------"
    docker build -t laserstack/app:$version .
    docker push     laserstack/app:$version
done
