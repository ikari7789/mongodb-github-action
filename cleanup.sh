#!/bin/sh

# Map input values from the GitHub Actions workflow to shell variables
MONGODB_VERSION=$1
MONGODB_REPLICA_SET=$2
MONGODB_PORT=$3
MONGODB_DB=$4
MONGODB_USERNAME=$5
MONGODB_PASSWORD=$6
HOST_CONTAINER_HOSTNAME=$7

CID_FILE=$GITHUB_WORKSPACE/mongodb.$HOST_CONTAINER_HOSTNAME

docker container kill $(cat $CID_FILE)
docker container rm --force $(cat $CID_FILE)
rm -f $CID_FILE
