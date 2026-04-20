#!/bin/bash
set -x

# Auto restart when change configmap or secret
helm repo add stakater https://stakater.github.io/stakater-charts
helm repo update

# Define NS_PREFIX
NS_PREFIX=${NS_PREFIX:-yas-dev}

helm dependency build ../charts/yas-configuration
helm upgrade --install "${NS_PREFIX}-yas-configuration" ../charts/yas-configuration \
--namespace "${NS_PREFIX}-yas" --create-namespace

