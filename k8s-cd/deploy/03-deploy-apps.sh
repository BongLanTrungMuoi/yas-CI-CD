#!/bin/bash
set -x

helm repo add stakater https://stakater.github.io/stakater-charts
helm repo update

read -rd '' DOMAIN \
< <(yq -r '.domain' ./cluster-config.yaml)

NAMESPACE="${YAS_NAMESPACE:-yas}"

# Create namespace yas if not exists
kubectl create namespace "$NAMESPACE" || true

echo ">>> Deploying YAS Configuration (including Reloader)..."
helm dependency build ../charts/yas-configuration
helm upgrade --install yas-configuration ../charts/yas-configuration \
--namespace "$NAMESPACE"

sleep 10

echo ">>> Deploying Backoffice..."
helm dependency build ../charts/backoffice-bff
helm upgrade --install backoffice-bff ../charts/backoffice-bff \
--namespace "$NAMESPACE" \
--set backend.ingress.host="backoffice.$DOMAIN"

helm dependency build ../charts/backoffice-ui
helm upgrade --install backoffice-ui ../charts/backoffice-ui \
--namespace "$NAMESPACE"

sleep 10

echo ">>> Deploying Storefront..."
helm dependency build ../charts/storefront-bff
helm upgrade --install storefront-bff ../charts/storefront-bff \
--namespace "$NAMESPACE" \
--set backend.ingress.host="storefront.$DOMAIN"

helm dependency build ../charts/storefront-ui
helm upgrade --install storefront-ui ../charts/storefront-ui \
--namespace "$NAMESPACE"

sleep 10

echo ">>> Deploying Swagger UI..."
helm upgrade --install swagger-ui ../charts/swagger-ui \
--namespace "$NAMESPACE" \
--set ingress.host="api.$DOMAIN"

sleep 10

echo ">>> Deploying Core Microservices..."
for chart in {"cart","customer","inventory","location","media","order","payment","product","promotion","rating","search","tax","recommendation","webhook","sampledata"} ; do
    helm dependency build ../charts/"$chart"
    helm upgrade --install "$chart" ../charts/"$chart" \
    --namespace "$NAMESPACE" \
    --set backend.ingress.host="api.$DOMAIN"
    sleep 10
done

echo ">>> Xong Giai đoạn 2.2: Tất cả Microservices và UI đã được cài vào namespace '$NAMESPACE'."
