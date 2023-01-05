#!/bin/sh

docker container kill $(cat /tmp/mongodb.cid)
docker container rm --force $(cat /tmp/mongodb.cid)
rm -f /tmp/mongodb.cid
