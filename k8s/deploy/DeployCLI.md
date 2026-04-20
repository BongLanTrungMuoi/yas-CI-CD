# Deploy yas k8s

## 0. Start minikube

```bash
minikube start --driver=docker --disk-size='80000mb' --memory='18g' --cpus='7' --kubernetes-version=v1.29.0
minikube addons enable ingress
```

## 1. Install Ingress NGINX Controller (K8S Cluster)

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --set controller.service.type=NodePort \
  --set controller.service.nodePorts.http=30080 \
  --set controller.service.nodePorts.https=30443
```

## 2. Deploy YAS System and Infrastructure

```bash
cd k8s/deploy/
./setup-cluster.sh
./setup-redis.sh
./setup-keycloak.sh
./deploy-yas-configuration.sh
./deploy-yas-applications.sh
```

## 3. Configure Local DNS (Mapping Domain)

```bash
# Kiểm tra IP của Node
kubectl get nodes -o wide

# Thêm cấu hình vào file hosts
sudo nano /etc/hosts
```

*Thêm nội dung sau vào file `/etc/hosts`:*

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

## 4. Teardown & Cleanup

```bash
# 1. Xóa các ứng dụng bằng Helm một cách an toàn (tránh lỗi nếu namespace trống)
NAMESPACES="yas postgres elasticsearch kafka keycloak observability zookeeper redis ingress-nginx cert-manager"
for ns in $NAMESPACES; do
  helm list -n $ns -q | xargs -r helm uninstall -n $ns
done

# 2. Xóa các Custom Resource Definitions (CRDs)
kubectl delete crd $(kubectl get crd -o name | grep -E "zalan.do|strimzi|elastic|keycloak|cert-manager|opentelemetry")

# 3. Xóa toàn bộ dữ liệu (Persistent Volume Claims) TRƯỚC KHI xóa namespace
kubectl delete pvc --all -A

# 4. Xóa các Namespaces (Bước này sẽ quét sạch các ConfigMap, Secret, Service còn sót lại)
kubectl delete ns $NAMESPACES --ignore-not-found=true

# 5. (Tùy chọn) Xóa bỏ các Persistent Volumes (PV) bị mồ côi nếu StorageClass không tự dọn
kubectl delete pv --all
```
