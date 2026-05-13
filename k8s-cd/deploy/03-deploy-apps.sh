#!/bin/bash
set -x

helm repo add stakater https://stakater.github.io/stakater-charts
helm repo update

read -rd '' DOMAIN \
< <(yq -r '.domain' ./cluster-config.yaml)

NAMESPACE="${YAS_NAMESPACE:-yas}"

# Construct dynamic domains
if [ -n "$ENV_TAG" ]; then
  IDENTITY_HOST="identity-$ENV_TAG.$DOMAIN"
  BACKOFFICE_HOST="backoffice-$ENV_TAG.$DOMAIN"
  STOREFRONT_HOST="storefront-$ENV_TAG.$DOMAIN"
  API_HOST="api-$ENV_TAG.$DOMAIN"
else
  IDENTITY_HOST="identity.$DOMAIN"
  BACKOFFICE_HOST="backoffice.$DOMAIN"
  STOREFRONT_HOST="storefront.$DOMAIN"
  API_HOST="api.$DOMAIN"
fi

# Create namespace yas if not exists
kubectl create namespace "$NAMESPACE" || true

echo ">>> Deploying YAS Configuration (including Reloader)..."
helm dependency build ../charts/yas-configuration
helm upgrade --install yas-configuration ../charts/yas-configuration \
--namespace "$NAMESPACE" \
--set global.domain="$DOMAIN" \
--set global.envTag="$ENV_TAG"

sleep 50

echo ">>> Deploying Backoffice..."
helm dependency build ../charts/backoffice-bff
helm upgrade --install backoffice-bff ../charts/backoffice-bff \
--namespace "$NAMESPACE" \
--set backend.ingress.host="$BACKOFFICE_HOST" \
--set global.domain="$DOMAIN" \
--set global.envTag="$ENV_TAG"

helm dependency build ../charts/backoffice-ui
helm upgrade --install backoffice-ui ../charts/backoffice-ui \
--namespace "$NAMESPACE" \
--set ingress.host="$BACKOFFICE_HOST" \
--set ui.extraEnvs[0].name=API_BASE_PATH \
--set ui.extraEnvs[0].value="http://$BACKOFFICE_HOST/api"

sleep 50

echo ">>> Deploying Storefront..."
helm dependency build ../charts/storefront-bff
helm upgrade --install storefront-bff ../charts/storefront-bff \
--namespace "$NAMESPACE" \
--set backend.ingress.host="$STOREFRONT_HOST" \
--set global.domain="$DOMAIN" \
--set global.envTag="$ENV_TAG"

helm dependency build ../charts/storefront-ui
helm upgrade --install storefront-ui ../charts/storefront-ui \
--namespace "$NAMESPACE" \
--set ingress.host="$STOREFRONT_HOST" \
--set ui.extraEnvs[0].name=API_BASE_PATH \
--set ui.extraEnvs[0].value="http://$STOREFRONT_HOST/api"

sleep 50

echo ">>> Deploying Swagger UI..."
helm upgrade --install swagger-ui ../charts/swagger-ui \
--namespace "$NAMESPACE" \
--set ingress.host="$API_HOST"

sleep 50

echo ">>> Deploying Core Microservices..."
for chart in {"cart","customer","inventory","location","media","order","payment","product","promotion","rating","search","tax","recommendation","webhook","sampledata"} ; do
    helm dependency build ../charts/"$chart"
    helm upgrade --install "$chart" ../charts/"$chart" \
    --namespace "$NAMESPACE" \
    --set backend.ingress.host="$API_HOST" \
    --set global.domain="$DOMAIN" \
    --set global.envTag="$ENV_TAG"
    sleep 50
done

echo ">>> Xong Giai đoạn 2.2: Tất cả Microservices và UI đã được cài vào namespace '$NAMESPACE' với domain prefix '$ENV_TAG'."
