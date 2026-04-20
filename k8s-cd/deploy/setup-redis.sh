#!/bin/bash
set -x

#Read configuration value from cluster-config.yaml file
read -rd '' REDIS_PASSWORD \
< <(yq -r '.redis.password' ./cluster-config.yaml)

# Define NS_PREFIX
NS_PREFIX=${NS_PREFIX:-yas-dev}

helm upgrade --install "${NS_PREFIX}-redis" \
  --set auth.password="$REDIS_PASSWORD" \
  oci://registry-1.docker.io/bitnamicharts/redis -n "${NS_PREFIX}-redis" --create-namespace
