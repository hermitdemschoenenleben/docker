#!/bin/bash

set -e

cd projects/bm


function init_data(){
  # create a directory to store Pelias data files
  mkdir ./data
  sed -i '/DATA_DIR/d' .env
  echo 'DATA_DIR=./data' >> .env

  # configure docker to write files as your local user
  sed -i '/DOCKER_USER/d' .env
  echo "DOCKER_USER=$(id -u)" >> .env
}

function create_pod() {
  podman pod create \
    --name pelias \
    -p 4000:4000 \
    -p 9200:9200 \
    --add-host elasticsearch:127.0.0.1 \
    --add-host pip:127.0.0.1;
}

function make_elastic_dir() {
  mkdir -p $DATA_DIR/elasticsearch
  # attemp to set proper permissions if running as root
  chown $DOCKER_USER $DATA_DIR/elasticsearch 2>/dev/null || true
  chmod -R 777 $DATA_DIR/elasticsearch
}

function elastic_start(){
  podman run \
      -d \
      --rm \
      --name pelias_elasticsearch \
      --pod pelias \
      -v "${DATA_DIR}/elasticsearch:/usr/share/elasticsearch/data:z" \
      --cap-add IPC_LOCK \
      pelias/elasticsearch:7.5.1
}

function elastic_status(){
  curl \
    --output /dev/null \
    --silent \
    --write-out "%{http_code}" \
    "http://${ELASTIC_HOST:-localhost:9200}/_cluster/health?wait_for_status=yellow&timeout=1s" \
      || true;
}
function elastic_wait(){
  echo 'waiting for elasticsearch service to come up';
  retry_count=30

  i=1
  while [[ "$i" -le "$retry_count" ]]; do
    if [[ $(elastic_status) -eq 200 ]]; then
      echo "Elasticsearch up!"
      return
    elif [[ $(elastic_status) -eq 408 ]]; then
      # 408 indicates the server is up but not yet yellow status
      printf ":"
    else
      printf "."
    fi
    sleep 1
    i=$(($i + 1))
  done

  echo -e "\n"
  echo "Elasticsearch did not come up, check configuration"
  error
}

function create_index(){
  podman run \
      --rm \
      --name pelias_schema \
      --pod pelias \
      -v "./pelias.json:/code/pelias.json:z" \
      pelias/schema:master \
      ./bin/create_index
}

function download_wof(){
  podman run \
      --rm \
      -v "./pelias.json:/code/pelias.json:z" \
      -v "${DATA_DIR}:/data:z" \
      -v "./blacklist/:/data/blacklist:z" \
      --name pelias_whosonfirst \
      --pod pelias \
      "pelias/whosonfirst:master" \
      ./bin/download
}
# prepare all the data to be used by imports
function prepare_all(){
  echo "preparing all doesnt seem to be necessary if only using wof"
}
function import_wof(){
  podman run \
      --rm \
      -v "./pelias.json:/code/pelias.json:z" \
      -v "${DATA_DIR}:/data:z" \
      -v "./blacklist/:/data/blacklist:z" \
      --name pelias_whosonfirst \
      --pod pelias \
      "pelias/whosonfirst:master" \
      ./bin/start;
}
function run_api(){
  podman run \
      -d \
      --rm \
      -v "./pelias.json:/code/pelias.json:z" \
      --name pelias_api \
      --pod pelias \
      -p 4000:4000 \
      --env "PORT=4000" \
      "pelias/api:master";
}
function run_pip(){
  podman run \
      -d \
      --rm \
      -v "./pelias.json:/code/pelias.json:z" \
      -v "${DATA_DIR}:/data:z" \
      --name pelias_pip-service \
      --pod pelias \
      -p 4000:4000 \
      --env "PORT=4200" \
      "pelias/pip-service:master";
}

if [[ $* == *--init* ]]
then
  init_data
fi

source .env

if [[ $* == *--init* ]]
then
  chmod -R 777 $DATA_DIR
  create_pod
  make_elastic_dir
fi

elastic_start
elastic_wait

if [[ $* == *--init* ]]
then
  create_index
  download_wof
  prepare_all
  import_wof
fi

run_pip
run_api