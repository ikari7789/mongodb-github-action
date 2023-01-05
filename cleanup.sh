#!/bin/sh

CID_FILE=$RUNNER_TEMP/mongodb-$GITHUB_RUN_ID.cid

docker container kill $(cat $CID_FILE)
docker container rm --force $(cat $CID_FILE)
rm -f $CID_FILE
