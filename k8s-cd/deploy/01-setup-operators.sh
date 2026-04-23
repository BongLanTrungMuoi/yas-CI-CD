#!/bin/bash
set -x

# Add chart repos and update
helm repo add postgres-operator-charts https://opensource.zalando.com/postgres-operator/charts/postgres-operator
helm repo add strimzi https://strimzi.io/charts/
helm repo add elastic https://helm.elastic.co
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo add jetstack https://charts.jetstack.io
helm repo update

# Read configuration value from cluster-config.yaml file
read -rd '' DOMAIN GRAFANA_USERNAME GRAFANA_PASSWORD POSTGRESQL_USERNAME POSTGRESQL_PASSWORD \
< <(yq -r '.domain, .grafana.username, .grafana.password, .postgresql.username, .postgresql.password' ./cluster-config.yaml)

NAMESPACE="${YAS_NAMESPACE:-yas}"

# Install cert manager
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.12.0 \
  --set installCRDs=true \
  --set prometheus.enabled=false \
  --set webhook.timeoutSeconds=4 \
  --set admissionWebhooks.certManager.create=true

# Install the postgres-operator
helm upgrade --install postgres-operator postgres-operator-charts/postgres-operator \
 --create-namespace --namespace postgres

# Install strimzi-kafka-operator
helm upgrade --install kafka-operator strimzi/strimzi-kafka-operator \
--create-namespace --namespace kafka \
--version 0.38.0 \
-f ./kafka/kafka-operator.values.yaml

# Install elastic-operator
helm upgrade --install elastic-operator elastic/eck-operator \
 --create-namespace --namespace elasticsearch

# Install opentelemetry-operator
helm upgrade --install opentelemetry-operator open-telemetry/opentelemetry-operator \
--create-namespace --namespace observability

# Wait for OpenTelemetry Operator to be ready
kubectl wait --for=condition=available --timeout=120s deployment/opentelemetry-operator -n observability
sleep 10

# Install opentelemetry-collector
helm upgrade --install opentelemetry-collector ./observability/opentelemetry \
--create-namespace --namespace observability

# Install loki
helm upgrade --install loki grafana/loki \
 --create-namespace --namespace observability \
 -f ./observability/loki.values.yaml \
 --set loki.useTestSchema=true

# Install tempo
helm upgrade --install tempo grafana/tempo \
--create-namespace --namespace observability \
-f ./observability/tempo.values.yaml

# Install promtail
helm upgrade --install promtail grafana/promtail \
--create-namespace --namespace observability \
--values ./observability/promtail.values.yaml

# Install prometheus + grafana
grafana_hostname="grafana.$DOMAIN" yq -i '.hostname=env(grafana_hostname)' ./observability/prometheus.values.yaml
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
 --create-namespace --namespace observability \
-f ./observability/prometheus.values.yaml

# Install grafana operator
helm upgrade --install grafana-operator oci://ghcr.io/grafana-operator/helm-charts/grafana-operator \
--version v5.0.2 \
--create-namespace --namespace observability

# Add datasource and dashboard to grafana
helm upgrade --install grafana ./observability/grafana \
--create-namespace --namespace observability \
--set hotname="grafana.$DOMAIN" \
--set grafana.username="$GRAFANA_USERNAME" \
--set grafana.password="$GRAFANA_PASSWORD"

echo ">>> Xong Giai đoạn 1: Các Operator và Observability đã được cài đặt vào các namespace độc lập."
