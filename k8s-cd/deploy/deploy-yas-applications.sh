#!/bin/bash
set -x

# Auto restart when change configmap or secret
helm repo add stakater https://stakater.github.io/stakater-charts
helm repo update

read -rd '' DOMAIN \
< <(yq -r '.domain' ./cluster-config.yaml)

# Define NS_PREFIX
NS_PREFIX=${NS_PREFIX:-yas-dev}
APP_NS="${NS_PREFIX}-yas"

helm dependency build ../charts/backoffice-bff
helm upgrade --install "${NS_PREFIX}-backoffice-bff" ../charts/backoffice-bff \
--namespace "$APP_NS" --create-namespace \
--set backend.ingress.host="backoffice.$DOMAIN"

helm dependency build ../charts/backoffice-ui
helm upgrade --install "${NS_PREFIX}-backoffice-ui" ../charts/backoffice-ui \
--namespace "$APP_NS" --create-namespace

sleep 20

helm dependency build ../charts/storefront-bff
helm upgrade --install "${NS_PREFIX}-storefront-bff" ../charts/storefront-bff \
--namespace "$APP_NS" --create-namespace \
--set backend.ingress.host="storefront.$DOMAIN"

helm dependency build ../charts/storefront-ui
helm upgrade --install "${NS_PREFIX}-storefront-ui" ../charts/storefront-ui \
--namespace "$APP_NS" --create-namespace

sleep 20

helm upgrade --install "${NS_PREFIX}-swagger-ui" ../charts/swagger-ui \
--namespace "$APP_NS" --create-namespace \
--set ingress.host="api.$DOMAIN"

sleep 20

for chart in {"cart","customer","inventory","location","media","order","payment","product","promotion","rating","search","tax","recommendation","webhook","sampledata"} ; do
    helm dependency build ../charts/"$chart"
    helm upgrade --install "${NS_PREFIX}-$chart" ../charts/"$chart" \
    --namespace "$APP_NS" --create-namespace \
    --set backend.ingress.host="api.$DOMAIN"
    sleep 20
done
