# Deploy YAS K8s (Hybrid Architecture)

## 0. Khởi động Minikube

Khởi tạo cụm và bật addon Ingress (bỏ qua bước cài Ingress Controller thủ công):

```bash
minikube start --driver=docker --disk-size='80000mb' --memory='18g' --cpus='7' --kubernetes-version=v1.29.0
minikube addons enable ingress
```

## 1. Triển khai Hệ thống (Kiến trúc Hybrid)

Di chuyển vào thư mục `deploy` và chạy tuần tự các script theo đúng 3 giai đoạn:

```bash
cd k8s-cd/deploy/
export YAS_NAMESPACE="yas13"
./01-setup-operators.sh
./02-setup-data-layer.sh
./03-deploy-apps.sh
```

## 2. Cấu hình Local DNS (Mapping Domain)

```bash
kubectl get nodes -o wide

sudo nano /etc/hosts
```

*Thêm nội dung sau vào file `/etc/hosts` (Thay IP bằng IP của Minikube nếu khác `192.168.49.2`):*

```text
192.168.49.2 pgoperator.yas.local.com
192.168.49.2 pgadmin.yas.local.com
192.168.49.2 akhq.yas.local.com
192.168.49.2 kibana.yas.local.com
192.168.49.2 identity.yas.local.com
192.168.49.2 backoffice.yas.local.com
192.168.49.2 storefront.yas.local.com
192.168.49.2 grafana.yas.local.com
192.168.49.2 api.yas.local.com
```

## 3. Teardown & Cleanup (Dọn dẹp cụm)

Để gỡ bỏ toàn bộ hệ thống một cách sạch sẽ:

```bash
export YAS_NAMESPACE="yas13"
helm list -n "$YAS_NAMESPACE" -q | xargs -r helm uninstall -n "$YAS_NAMESPACE"
kubectl delete ns "$YAS_NAMESPACE" --ignore-not-found=true
```
