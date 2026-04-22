FROM quay.io/strimzi/kafka:0.38.0-kafka-3.6.0

USER root:root

RUN mkdir -p /opt/kafka/plugins/debezium-postgres && \
    curl -L https://repo1.maven.org/maven2/io/debezium/debezium-connector-postgres/2.5.0.Final/debezium-connector-postgres-2.5.0.Final-plugin.tar.gz | tar -xzf - -C /opt/kafka/plugins/debezium-postgres --strip-components=1

RUN chown -R 1001:1001 /opt/kafka/plugins/debezium-postgres

USER 1001