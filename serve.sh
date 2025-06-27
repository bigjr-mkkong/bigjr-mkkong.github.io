#!/bin/bash

set -e

SITE_DIR="$(pwd)"
BUILD_DIR="$SITE_DIR/_site"
NGINX_CONTAINER_NAME="jekyll_site_nginx"
PORT=8080

docker run --rm \
  -v "$SITE_DIR:/srv/jekyll" \
  jekyll/jekyll \
  jekyll build

if docker ps -q -f name=$NGINX_CONTAINER_NAME | grep -q .; then
  docker stop $NGINX_CONTAINER_NAME
fi

EXISTING=$(docker ps --filter "publish=8080" --format "{{.ID}}")
if [ -n "$EXISTING" ]; then
  docker stop "$EXISTING"
fi


docker run --rm -d \
  --name $NGINX_CONTAINER_NAME \
  -v "$BUILD_DIR:/usr/share/nginx/html:ro" \
  -p $PORT:80 \
  nginx

echo "finished"
