#!/bin/bash
set -e

echo ">>> 1. Cài đặt yq (v4.44.1)..."
sudo wget https://github.com/mikefarah/yq/releases/download/v4.44.1/yq_linux_amd64 -O /usr/bin/yq
sudo chmod +x /usr/bin/yq
yq --version

echo ">>> 2. Cài đặt Local Path Provisioner (StorageClass)..."
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.28/deploy/local-path-storage.yaml

echo ">>> 3. Thiết lập local-path làm StorageClass mặc định..."
kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

echo ">>> 4. Xóa các Pod bị Evicted để hệ thống dọn dẹp..."
kubectl delete pod -A --field-selector status.phase=Failed

echo ">>> 5. Triển khai lại Keycloak (để cập nhật config từ yq)..."
# Chạy lại script setup keycloak
./setup-keycloak.sh

echo "========================================================="
echo "XONG! Hãy đợi khoảng 1-2 phút để các PVC chuyển sang Bound"
echo "và các Pod infrastructure (Redis, Postgres) khởi động."
echo "Sau đó bạn có thể chạy ./deploy-yas-applications.sh"
echo "========================================================="
