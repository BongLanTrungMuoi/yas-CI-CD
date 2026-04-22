#!/bin/bash
set -x

# Add chart repos and update
helm repo add postgres-operator-charts https://opensource.zalando.com/postgres-operator/charts/postgres-operator
helm repo add strimzi https://strimzi.io/charts/
helm repo add akhq https://akhq.io/
helm repo add elastic https://helm.elastic.co
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo add jetstack https://charts.jetstack.io
helm repo update

#Read configuration value from cluster-config.yaml file
read -rd '' DOMAIN POSTGRESQL_REPLICAS POSTGRESQL_USERNAME POSTGRESQL_PASSWORD \
KAFKA_REPLICAS ZOOKEEPER_REPLICAS ELASTICSEARCH_REPLICAES \
GRAFANA_USERNAME GRAFANA_PASSWORD \
< <(yq -r '.domain, .postgresql.replicas, .postgresql.username,
 .postgresql.password, .kafka.replicas, .zookeeper.replicas,
 .elasticsearch.replicas, .grafana.username, .grafana.password' ./cluster-config.yaml)

# Define NS_PREFIX
NS_PREFIX=${NS_PREFIX:-yas-dev}

# Install the postgres-operator
helm upgrade --install "${NS_PREFIX}-postgres-operator" postgres-operator-charts/postgres-operator \
 --create-namespace --namespace "${NS_PREFIX}-postgres"

#Install postgresql
helm upgrade --install "${NS_PREFIX}-postgres" ./postgres/postgresql \
--create-namespace --namespace "${NS_PREFIX}-postgres" \
--set replicas="$POSTGRESQL_REPLICAS" \
--set username="$POSTGRESQL_USERNAME" \
--set password="$POSTGRESQL_PASSWORD"

#Install pgadmin
pg_admin_hostname="pgadmin.$DOMAIN" yq -i '.hostname=env(pg_admin_hostname)' ./postgres/pgadmin/values.yaml
helm upgrade --install "${NS_PREFIX}-pgadmin" ./postgres/pgadmin \
--create-namespace --namespace "${NS_PREFIX}-postgres"

#Install strimzi-kafka-operator
helm upgrade --install "${NS_PREFIX}-kafka-operator" strimzi/strimzi-kafka-operator \
--create-namespace --namespace "${NS_PREFIX}-kafka" \
--version 0.38.0

#Install kafka and postgresql connector
helm upgrade --install "${NS_PREFIX}-kafka-cluster" ./kafka/kafka-cluster \
--create-namespace --namespace "${NS_PREFIX}-kafka" \
--set kafka.replicas="$KAFKA_REPLICAS" \
--set zookeeper.replicas="$ZOOKEEPER_REPLICAS" \
--set postgresql.username="$POSTGRESQL_USERNAME" \
--set postgresql.password="$POSTGRESQL_PASSWORD"

#Install akhq
akhq_hostname="akhq.$DOMAIN" yq -i '.hostname=env(akhq_hostname)' ./kafka/akhq.values.yaml
helm upgrade --install "${NS_PREFIX}-akhq" akhq/akhq \
--create-namespace --namespace "${NS_PREFIX}-kafka" \
--values ./kafka/akhq.values.yaml

#Install elastic-operator
helm upgrade --install "${NS_PREFIX}-elastic-operator" elastic/eck-operator \
 --create-namespace --namespace "${NS_PREFIX}-elasticsearch"

# Install elasticsearch-cluster
helm upgrade --install "${NS_PREFIX}-elasticsearch-cluster" ./elasticsearch/elasticsearch-cluster \
--create-namespace --namespace "${NS_PREFIX}-elasticsearch" \
--set elasticsearch.replicas="$ELASTICSEARCH_REPLICAES" \
--set kibana.ingress.hostname="kibana.$DOMAIN"

#Install loki
helm upgrade --install "${NS_PREFIX}-loki" grafana/loki \
  --create-namespace --namespace "${NS_PREFIX}-observability" \
  --set fullnameOverride="${NS_PREFIX}-loki" \
  -f ./observability/loki.values.yaml

#Install tempo
helm upgrade --install "${NS_PREFIX}-tempo" grafana/tempo \
 --create-namespace --namespace "${NS_PREFIX}-observability" \
 --set fullnameOverride="${NS_PREFIX}-tempo" \
 -f ./observability/tempo.values.yaml

#Install cert manager
helm upgrade --install "${NS_PREFIX}-cert-manager" jetstack/cert-manager \
  --namespace "${NS_PREFIX}-cert-manager" \
  --create-namespace \
  --version v1.12.0 \
  --set installCRDs=true \
  --set prometheus.enabled=false \
  --set webhook.timeoutSeconds=4 \
  --set admissionWebhooks.certManager.create=true

#Install opentelemetry-operator
helm upgrade --install "${NS_PREFIX}-opentelemetry-operator" open-telemetry/opentelemetry-operator \
--create-namespace --namespace "${NS_PREFIX}-observability"

#Install opentelemetry-collector
helm upgrade --install "${NS_PREFIX}-opentelemetry-collector" ./observability/opentelemetry \
--create-namespace --namespace "${NS_PREFIX}-observability"

#Install promtail
helm upgrade --install "${NS_PREFIX}-promtail" grafana/promtail \
--create-namespace --namespace "${NS_PREFIX}-observability" \
--values ./observability/promtail.values.yaml

#Install prometheus + grafana
grafana_hostname="grafana.$DOMAIN" yq -i '.hostname=env(grafana_hostname)' ./observability/prometheus.values.yaml
postgresql_username="$POSTGRESQL_USERNAME" yq -i '.grafana."grafana.ini".database.user=env(postgresql_username)' ./observability/prometheus.values.yaml
postgresql_password="$POSTGRESQL_PASSWORD" yq -i '.grafana."grafana.ini".database.password=env(postgresql_password)' ./observability/prometheus.values.yaml
helm upgrade --install "${NS_PREFIX}-prometheus" prometheus-community/kube-prometheus-stack \
 --create-namespace --namespace "${NS_PREFIX}-observability" \
 --set fullnameOverride="${NS_PREFIX}-prometheus" \
 -f ./observability/prometheus.values.yaml

#Install grafana operator
helm upgrade --install "${NS_PREFIX}-grafana-operator" oci://ghcr.io/grafana-operator/helm-charts/grafana-operator \
--version v5.0.2 \
--create-namespace --namespace "${NS_PREFIX}-observability"

#Add datasource and dashboard to grafana
helm upgrade --install "${NS_PREFIX}-grafana" ./observability/grafana \
--create-namespace --namespace "${NS_PREFIX}-observability" \
--set hostname="grafana.$DOMAIN" \
--set grafana.username="$GRAFANA_USERNAME" \
--set grafana.password="$GRAFANA_PASSWORD" \
--set postgresql.username="$POSTGRESQL_USERNAME" \
--set postgresql.password="$POSTGRESQL_PASSWORD"

helm upgrade --install "${NS_PREFIX}-zookeeper" ./zookeeper \
 --namespace "${NS_PREFIX}-zookeeper" --create-namespace