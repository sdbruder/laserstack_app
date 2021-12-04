#!/bin/bash

# load .env
if [ -f .env ]; then
    export $(echo $(cat .env | sed 's/#.*//g'| xargs) | envsubst)
fi

echo $HUB_PASSWORD | docker login -u $HUB_USER --password-stdin

docker build --no-cache -t laserstack/app:$APP_VERSION .
docker push                laserstack/app:$APP_VERSION

if [ $APP_LATEST -eq 1 ] ; then
    docker build -t laserstack/app:latest .
    docker push     laserstack/app:latest
fi
