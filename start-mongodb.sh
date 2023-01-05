#!/bin/sh

kill_mongodb_container() {
  docker container kill $(cat /tmp/mongodb.cid)
  docker container rm --force $(cat /tmp/mongodb.cid)
  rm -f /tmp/mongodb.cid
}

trap kill_mongodb_container SIGINT SIGQUIT SIGTERM INT TERM QUIT

# Map input values from the GitHub Actions workflow to shell variables
MONGODB_VERSION=$1
MONGODB_REPLICA_SET=$2
MONGODB_PORT=$3
MONGODB_DB=$4
MONGODB_USERNAME=$5
MONGODB_PASSWORD=$6
CID_FILE=/tmp/mongodb.cid

if [ -z "$MONGODB_VERSION" ]; then
  echo ""
  echo "Missing MongoDB version in the [mongodb-version] input. Received value: $MONGODB_VERSION"
  echo ""

  exit 2
fi


DOCKER_SWITCHES="--publish ${MONGODB_PORT}:${MONGODB_PORT}"
if [ -z "$MONGODB_REPLICA_SET" ]; then
  DOCKER_SWITCHES="--publish ${MONGODB_PORT}:27017"
fi

echo "::group::Selecting correct MongoDB client"
if [ "`echo $MONGODB_VERSION | cut -c 1`" = "4" ]; then
  MONGO_CLIENT="mongo"
else
  MONGO_CLIENT="mongosh --quiet"
fi
echo "  - Using [$MONGO_CLIENT]"
echo ""
echo "::endgroup::"


if [ -z "$MONGODB_REPLICA_SET" ]; then
  echo "::group::Starting single-node instance, no replica set"
  echo "  - port [$MONGODB_PORT]"
  echo "  - version [$MONGODB_VERSION]"
  echo "  - database [$MONGODB_DB]"
  echo "  - credentials [$MONGODB_USERNAME:$MONGODB_PASSWORD]"
  echo ""

  docker run --cidfile $CID_FILE $DOCKER_SWITCHES -e MONGO_INITDB_DATABASE=$MONGODB_DB -e MONGO_INITDB_ROOT_USERNAME=$MONGODB_USERNAME -e MONGO_INITDB_ROOT_PASSWORD=$MONGODB_PASSWORD --detach mongo:$MONGODB_VERSION

  if [ $? -ne 0 ]; then
      echo "Error starting MongoDB Docker container"
      exit 2
  fi
  echo "::endgroup::"


  echo "::group::Instance information"

  CONTAINER_ID=$(cat $CID_FILE)
  CONTAINER_NAME=$(docker inspect --format="{{.Name}}" $(cat $CID_FILE) | cut -c2-)
  CONTAINER_PORT=$(docker inspect --format='{{ (index (index .NetworkSettings.Ports "27017/tcp") 0).HostPort }}' $(cat $CID_FILE))

  echo "::set-output name=mongodb-container-id::$CONTAINER_ID"
  echo "mongodb-container-id=$CONTAINER_ID" >> $GITHUB_OUTPUT
  echo " - container id [$CONTAINER_ID]"

  echo "::set-output name=mongodb-container-name::$CONTAINER_NAME"
  echo "mongodb-container-name=$CONTAINER_NAME" >> $GITHUB_OUTPUT
  echo " - container name [$CONTAINER_NAME]"

  echo "::set-output name=mongodb-container-port::$CONTAINER_PORT"
  echo "mongodb-container-port=$CONTAINER_PORT" >> $GITHUB_OUTPUT
  echo " - container port [$CONTAINER_PORT]"

  echo "::endgroup::"


  exit 0
fi


echo "::group::Starting MongoDB as single-node replica set"
echo "  - port [$MONGODB_PORT]"
echo "  - version [$MONGODB_VERSION]"
echo "  - replica set [$MONGODB_REPLICA_SET]"
echo ""

docker run --cidfile $CID_FILE $DOCKER_SWITCHES --detach mongo:$MONGODB_VERSION --replSet $MONGODB_REPLICA_SET --port $MONGODB_PORT

if [ $? -ne 0 ]; then
    echo "Error starting MongoDB Docker container"
    exit 2
fi
echo "::endgroup::"


echo "::group::Instance information"

CONTAINER_ID=$(cat $CID_FILE)
CONTAINER_NAME=$(docker inspect --format="{{.Name}}" $(cat $CID_FILE) | cut -c2-)
CONTAINER_PORT=$(docker inspect --format='{{ (index (index .NetworkSettings.Ports "27017/tcp") 0).HostPort }}' $(cat $CID_FILE))

echo "::set-output name=mongodb-container-id::$CONTAINER_ID"
echo "mongodb-container-id=$CONTAINER_ID" >> $GITHUB_OUTPUT
echo " - container id [$CONTAINER_ID]"

echo "::set-output name=mongodb-container-name::$CONTAINER_NAME"
echo "mongodb-container-name=$CONTAINER_NAME" >> $GITHUB_OUTPUT
echo " - container name [$CONTAINER_NAME]"

echo "::set-output name=mongodb-container-port::$CONTAINER_PORT"
echo "mongodb-container-port=$CONTAINER_PORT" >> $GITHUB_OUTPUT
echo " - container port [$CONTAINER_PORT]"

echo "::endgroup::"


echo "::group::Waiting for MongoDB to accept connections"
sleep 1
TIMER=0

until docker exec --tty $(cat /tmp/mongodb.cid) $MONGODB_CONTAINER $MONGO_CLIENT --port $MONGODB_PORT --eval "db.serverStatus()" # &> /dev/null
do
  sleep 1
  echo "."
  TIMER=$((TIMER + 1))

  if [[ $TIMER -eq 20 ]]; then
    echo "MongoDB did not initialize within 20 seconds. Exiting."
    exit 2
  fi
done
echo "::endgroup::"


echo "::group::Initiating replica set [$MONGODB_REPLICA_SET]"

docker exec --tty $(cat $CID_FILE) $MONGO_CLIENT --port $MONGODB_PORT --eval "
  rs.initiate({
    \"_id\": \"$MONGODB_REPLICA_SET\",
    \"members\": [ {
       \"_id\": 0,
      \"host\": \"localhost:$MONGODB_PORT\"
    } ]
  })
"

echo "Success! Initiated replica set [$MONGODB_REPLICA_SET]"
echo "::endgroup::"


echo "::group::Checking replica set status [$MONGODB_REPLICA_SET]"
docker exec --tty $(cat $CID_FILE) $MONGO_CLIENT --port $MONGODB_PORT --eval "
  rs.status()
"
echo "::endgroup::"
