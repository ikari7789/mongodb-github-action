#!/bin/sh

# Map input values from the GitHub Actions workflow to shell variables
MONGODB_VERSION=$1
MONGODB_REPLICA_SET=$2
MONGODB_PORT=$3
MONGODB_DB=$4
MONGODB_USERNAME=$5
MONGODB_PASSWORD=$6

ensure_required_values_provided() {
  if [ -z "$MONGODB_VERSION" ]; then
    echo ""
    echo "Missing MongoDB version in the [mongodb-version] input. Received value: $MONGODB_VERSION"
    echo ""

    exit 2
  fi
}

select_mongodb_client() {
  echo "::group::Selecting correct MongoDB client"
  if [ "`echo $MONGODB_VERSION | cut -c 1`" = "4" ]; then
    MONGO_CLIENT="mongo"
  else
    MONGO_CLIENT="mongosh --quiet"
  fi
  echo "  - Using [$MONGO_CLIENT]"
  echo ""
  echo "::endgroup::"
}

cleanup_leftover_container() {
  if [ -e $CID_FILE ]; then
    docker container kill $(cat $CID_FILE) > /dev/null 2>&1 || true
    docker container rm -f $(cat $CID_FILE) > /dev/null 2>&1 || true
    rm $CID_FILE > /dev/null 2>&1 || true
  fi
}

prepare_cid_file() {
  CID_FILE=$GITHUB_WORKSPACE/mongodb.$(md5sum <<EOF
$RANDOM
EOF
)
  cleanup_leftover_container
  echo "CID_FILE=${CID_FILE}" >> $GITHUB_ENV
}

start_container() {
  DOCKER_SWITCHES="--publish $MONGODB_PORT"
  MONGO_SWITCHES="--port $MONGODB_PORT"

  START_MESSAGE='Starting single-node instance, no replica set'

  if [ ! -z "$MONGODB_REPLICA_SET" ]; then
    START_MESSAGE='Starting MongoDB as single-node replica set'
    MONGO_SWITCHES="$MONGO_SWITCHES --replSet $MONGODB_REPLICA_SET"
  else
    DOCKER_SWITCHES="$DOCKER_SWITCHES -e MONGO_INITDB_DATABASE=$MONGODB_DB -e MONGO_INITDB_ROOT_USERNAME=$MONGODB_USERNAME -e MONGO_INITDB_ROOT_PASSWORD=$MONGODB_PASSWORD"
  fi

  echo "::group::$START_MESSAGE"
  echo "  - credentials [$MONGODB_USERNAME:$MONGODB_PASSWORD]"
  echo "  - database [$MONGODB_DB]"
  echo "  - port [$MONGODB_PORT]"
  echo "  - replica set [$MONGODB_REPLICA_SET]"
  echo "  - version [$MONGODB_VERSION]"
  echo "  - cidfile [$CID_FILE]"
  echo ""

  prepare_cid_file

  docker run --cidfile $CID_FILE $DOCKER_SWITCHES --detach mongo:$MONGODB_VERSION $MONGO_SWITCHES

  if [ $? -ne 0 ]; then
    echo "Error starting MongoDB Docker container"
    exit 2
  fi

  set_outputs

  exit_if_no_replica_set
  wait_for_connections
  initiate_replica_set
  check_replica_set_status

  echo "::endgroup::"
}

set_outputs() {
  echo "::group::Instance information"

  CONTAINER_ID=$(cat $CID_FILE)
  CONTAINER_NAME=$(docker inspect --format="{{.Name}}" $(cat $CID_FILE) | cut -c2-)
  CONTAINER_IP_ADDRESS=$(docker inspect --format '{{ .NetworkSettings.IPAddress }}' $(cat $CID_FILE))
  CONTAINER_PORT=$(docker inspect --format='{{ (index (index .NetworkSettings.Ports "'$MONGODB_PORT'/tcp") 0).HostPort }}' $(cat $CID_FILE))

  echo "::set-output name=mongodb-container-id::$CONTAINER_ID"
  echo "mongodb-container-id=$CONTAINER_ID" >> $GITHUB_OUTPUT
  echo " - container id [$CONTAINER_ID]"

  echo "::set-output name=mongodb-container-name::$CONTAINER_NAME"
  echo "mongodb-container-name=$CONTAINER_NAME" >> $GITHUB_OUTPUT
  echo " - container name [$CONTAINER_NAME]"

  echo "::set-output name=mongodb-container-ip-address::$CONTAINER_IP_ADDRESS"
  echo "mongodb-container-ip-address=$CONTAINER_IP_ADDRESS" >> $GITHUB_OUTPUT
  echo " - container ip address [$CONTAINER_IP_ADDRESS]"

  echo "::set-output name=mongodb-container-port::$CONTAINER_PORT"
  echo "mongodb-container-port=$CONTAINER_PORT" >> $GITHUB_OUTPUT
  echo " - container port [$CONTAINER_PORT]"

  echo ""

  echo "::endgroup::"
}

exit_if_no_replica_set() {
  # Nothing else necessary if we aren't building a replica set
  if [ -z "$MONGODB_REPLICA_SET" ]; then
    exit 0
  fi
}

wait_for_connections() {
  echo "::group::Waiting for MongoDB to accept connections"

  sleep 1
  TIMER=0
  
  until docker exec --tty $(cat $CID_FILE) $MONGODB_CONTAINER $MONGO_CLIENT --port $MONGODB_PORT --eval "db.serverStatus()" # &> /dev/null
  do
    sleep 1
    echo "."
    TIMER=$((TIMER + 1))
  
    if [[ $TIMER -eq 20 ]]; then
      echo "MongoDB did not initialize within 20 seconds. Exiting."
      exit 2
    fi
  done

  echo ""

  echo "::endgroup::"
}

initiate_replica_set() {
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

  echo ""

  echo "::endgroup::"
}

check_replica_set_status() {
  echo "::group::Checking replica set status [$MONGODB_REPLICA_SET]"

  docker exec --tty $(cat $CID_FILE) $MONGO_CLIENT --port $MONGODB_PORT --eval "
    rs.status()
  "

  echo ""

  echo "::endgroup::"
}

ensure_required_values_provided
select_mongodb_client
start_container
