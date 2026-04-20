#!/bin/bash
set -x

#Read configuration value from cluster-config.yaml file
read -rd '' DOMAIN POSTGRESQL_USERNAME POSTGRESQL_PASSWORD \
BOOTSTRAP_ADMIN_USERNAME BOOTSTRAP_ADMIN_PASSWORD \
KEYCLOAK_BACKOFFICE_REDIRECT_URL KEYCLOAK_STOREFRONT_REDIRECT_URL \
< <(yq -r '.domain,
  .postgresql.username, .postgresql.password,
  .keycloak.bootstrapAdmin.username, .keycloak.bootstrapAdmin.password,
  .keycloak.backofficeRedirectUrl, .keycloak.storefrontRedirectUrl' ./cluster-config.yaml)

# Define NS_PREFIX
NS_PREFIX=${NS_PREFIX:-yas-dev}
KEYCLOAK_NS="${NS_PREFIX}-keycloak"

# Create keycloak namespace
kubectl create namespace "$KEYCLOAK_NS" --dry-run=client -o yaml | kubectl apply -f -

# Install Keycloak operator CRDs and operator into the build namespace
kubectl apply -f https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/26.0.2/kubernetes/keycloaks.k8s.keycloak.org-v1.yml
kubectl apply -f https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/26.0.2/kubernetes/keycloakrealmimports.k8s.keycloak.org-v1.yml
kubectl apply -f https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/26.0.2/kubernetes/kubernetes.yml -n "$KEYCLOAK_NS"

# Install keycloak
helm upgrade --install "${NS_PREFIX}-keycloak" ./keycloak/keycloak \
--namespace "$KEYCLOAK_NS" \
--set hostname="identity.$DOMAIN" \
--set postgresql.username="$POSTGRESQL_USERNAME" \
--set postgresql.password="$POSTGRESQL_PASSWORD" \
--set bootstrapAdmin.username="$BOOTSTRAP_ADMIN_USERNAME" \
--set bootstrapAdmin.password="$BOOTSTRAP_ADMIN_PASSWORD" \
--set backofficeRedirectUrl="$KEYCLOAK_BACKOFFICE_REDIRECT_URL" \
--set storefrontRedirectUrl="$KEYCLOAK_STOREFRONT_REDIRECT_URL"
