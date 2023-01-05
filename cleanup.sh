#!/bin/sh

docker container kill $(cat $CID_FILE)
docker container rm --force $(cat $CID_FILE)
rm -f $CID_FILE
