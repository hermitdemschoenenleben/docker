#!/bin/bash
set -e

# make pelias binary available
export PATH=$PATH:$(pwd)

# cd into the project directory
cd projects/bm

# create a directory to store Pelias data files
mkdir ./data
sed -i '/DATA_DIR/d' .env
echo 'DATA_DIR=./data' >> .env

# configure docker to write files as your local user
sed -i '/DOCKER_USER/d' .env
echo "DOCKER_USER=$(id -u)" >> .env

# run build
pelias compose pull
pelias elastic start
pelias elastic wait
pelias elastic create
pelias download wof
pelias prepare all
pelias import wof
pelias compose up

# optionally run tests
#pelias test run
