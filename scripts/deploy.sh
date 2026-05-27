#!/bin/bash
set -e

: "${IMAGE:?IMAGE environment variable is required}"
: "${DB_PASSWORD:?DB_PASSWORD environment variable is required}"

DB_NAME="${DB_NAME:-taskdb}"
DB_USER="${DB_USER:-taskuser}"
DB_PORT="${DB_PORT:-3306}"
APP_PORT="${APP_PORT:-3000}"

info()  { echo -e "\e[32m[INFO]\e[0m  $*"; }
error() { echo -e "\e[31m[ERROR]\e[0m $*"; exit 1; }

info "pulling image: $IMAGE..."
docker pull "$IMAGE"

info "tagging image as stable..."
docker tag "$IMAGE" ghcr.io/tamanegich/devops-labs:stable

info "running database migration..."
docker run --rm \
    --network host \
    "$IMAGE" \
    node migrate.js \
    --db-host localhost \
    --db-port "$DB_PORT" \
    --db-user "$DB_USER" \
    --db-password "$DB_PASSWORD" \
    --db-name "$DB_NAME"

info "restarting mywebapp service..."
sudo systemctl restart mywebapp

info "waiting for service to come up..."
sleep 5

sudo systemctl is-active mywebapp || error "mywebapp service failed to start"

info "><>    =======================    <><"
info "        deployment complete         "
info "><>    =======================    <><"