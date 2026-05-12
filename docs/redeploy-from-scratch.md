# Hướng dẫn redeploy YAS + Service Mesh + Istio Gateway từ đầu

File handoff hoàn chỉnh từ session 12/05/2026. Khi bắt đầu session mới, đọc file này + `service-mesh-setup.md` là đủ context.

## Quick access (SSH, URLs, credentials)

### SSH vào Azure VM
```bash
ssh -i /home/lazyming/study/devops/yas-CI-CD/bltm-devops_key.pem azureuser@52.139.168.196
```

| Thông tin | Giá trị |
|---|---|
| Azure VM public IP | `52.139.168.196` |
| Azure VM tên | `bltm-devops` |
| SSH user | `azureuser` |
| SSH key path (local) | `/home/lazyming/study/devops/yas-CI-CD/bltm-devops_key.pem` |
| Repo path trên VM | `~/yas-CI-CD/` |
| Repo path local | `/home/lazyming/study/devops/yas-CI-CD/` |

### Azure NSG inbound ports đã mở
| Port | Rule name | Mục đích |
|---|---|---|
| 22 | (default SSH) | SSH |
| 20001 | `Allow-Kiali-20001` | Kiali dashboard |
| 31320 | `Allow-Istio-Gateway-31320` | Istio Gateway NodePort (có thể xóa, hiện dùng port 80) |
| 80 | `Allow-HTTP-80` | Istio Gateway via socat tunnel |

### Browser URLs (sau khi /etc/hosts trên máy local trỏ về `52.139.168.196`)

**Local /etc/hosts entries cần add:**
```
52.139.168.196  storefront-dev-1.yas.local.com
52.139.168.196  backoffice-dev-1.yas.local.com
52.139.168.196  identity-dev-1.yas.local.com
52.139.168.196  api-dev-1.yas.local.com
52.139.168.196  akhq-dev-1.yas.local.com
52.139.168.196  kibana-dev-1.yas.local.com
52.139.168.196  pgadmin-dev-1.yas.local.com
```

| URL | Phục vụ | Note |
|---|---|---|
| http://52.139.168.196:20001/kiali/ | Kiali Service Mesh dashboard | Tự gọi qua IP, không cần /etc/hosts |
| http://storefront-dev-1.yas.local.com/ | Storefront UI (NextJS) qua Istio Gateway | Login Keycloak required |
| http://storefront-dev-1.yas.local.com/oauth2/authorization/keycloak | Trigger OAuth login flow | Redirect đến Keycloak |
| http://identity-dev-1.yas.local.com/realms/Yas/.well-known/openid-configuration | Keycloak realm Yas (test 200) | API public |
| http://backoffice-dev-1.yas.local.com/ | Backoffice UI | Admin |

### Credentials

| Service | Username | Password | Realm | Note |
|---|---|---|---|---|
| Keycloak master admin | `admin` | `admin` | `master` | Bootstrap admin (cluster-config.yaml) |
| Keycloak Yas realm admin | `admin` | `admin` | `Yas` | Password đã reset qua API (sau import, password gốc hashed unknown) |
| PostgreSQL | `yasadminuser` | `admin` | - | cluster-config.yaml |
| Grafana | `admin` | `admin` | - | cluster-config.yaml grafana.* |

## Tổng quan trạng thái cuối (Service Mesh deliverable)

| Deliverable | Status | File |
|---|---|---|
| YAML manifest mTLS + AuthZ | ✅ | `k8s-cd/service-mesh/01-08*.yaml` (8 files) |
| Screenshot Kiali topology + giải thích flow | ✅ | `docs/images/kiali-topology-{full,mtls}.png` + README §10.4 |
| Test plan + logs (8/8 pass) | ✅ | `docs/service-mesh-evidence.md` |
| README hướng dẫn từng bước | ✅ | `docs/service-mesh-setup.md` (591 dòng, 11 bước + 10 bài học) |

## Pre-requisites

Trên VM (đã có sẵn):
- Docker, kubectl, helm, yq, istioctl 1.23.2
- Repo `~/yas-CI-CD/`
- SSH key đã copy

## Step-by-step

### Bước 1 — Tear down + clean minikube

```bash
sudo systemctl stop kiali-tunnel || true
minikube delete --all --purge
minikube start --driver=docker --cpus=4 --memory=24g --disk-size=20g \
  --kubernetes-version=v1.29.0 --addons=ingress

# ⚠️ BẮT BUỘC: cap CPU thật cho minikube (flag --cpus không cap container)
docker update --cpus=3 minikube
docker inspect minikube --format 'NanoCpus={{.HostConfig.NanoCpus}}'   # = 3000000000
```

### Bước 2 — Install Istio + addons + Kiali tunnel

```bash
istioctl install --set profile=demo -y
kubectl apply -f ~/istio-1.23.2/samples/addons/prometheus.yaml
kubectl apply -f ~/istio-1.23.2/samples/addons/jaeger.yaml
kubectl apply -f ~/istio-1.23.2/samples/addons/kiali.yaml
kubectl wait --for=condition=available --timeout=180s deployment/kiali -n istio-system

# Kiali NodePort + socat tunnel host:20001 → minikube NodePort
kubectl patch svc kiali -n istio-system -p '{"spec":{"type":"NodePort"}}'
KIALI_PORT=$(kubectl get svc kiali -n istio-system -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}')
MINIKUBE_IP=$(minikube ip)

sudo tee /etc/systemd/system/kiali-tunnel.service > /dev/null <<EOF
[Unit]
Description=Kiali NodePort tunnel
After=docker.service network-online.target
[Service]
ExecStart=/usr/bin/socat TCP-LISTEN:20001,fork,reuseaddr TCP:$MINIKUBE_IP:$KIALI_PORT
Restart=always
[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload && sudo systemctl restart kiali-tunnel
```

### Bước 3 — Tạo namespace yas-1 với sidecar injection

```bash
kubectl create namespace yas-1
kubectl label namespace yas-1 istio-injection=enabled
```

### Bước 4 — Run 3 deploy scripts (script gốc, KHÔNG hardening)

```bash
cd ~/yas-CI-CD/k8s-cd/deploy
export YAS_NAMESPACE=yas-1 ENV_TAG=dev-1

bash ./01-setup-operators.sh    # ~6 phút (12 helm release operators + observability)
bash ./02-setup-data-layer.sh   # ~30s (8 helm release data layer, install async)
bash ./03-deploy-apps.sh        # ~3 phút (20 helm release apps, install async)
```

> ⚠️ **KHÔNG hardening 3 script này** với `set -e` + `helm --wait --atomic`. Đã thử và phát sinh 2 bug (xem section "Bài học" cuối):
> - `read -rd '' ... < <(yq ...)` returns exit 1 khi reach EOF (expected) → `set -e` kill script
> - `helm install --wait --atomic --timeout 8m` với 15 Spring Boot service tuần tự trên VM 4 vCPU → dễ timeout → atomic rollback → fail

### Bước 5 — Scale 0 toàn bộ + scale up subset 3 service

```bash
kubectl scale deploy -n yas-1 --replicas=0 --all

# Patch probe failureThreshold=60 trước khi scale up (chart default = 12 không đủ cho VM share CPU)
for svc in product cart customer; do
  kubectl patch deploy/$svc -n yas-1 --type=json -p='[
    {"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/failureThreshold","value":60},
    {"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/failureThreshold","value":60}
  ]'
done

# Scale up từng cái cách 90s để CPU không bị starve cùng lúc
kubectl scale deploy product  -n yas-1 --replicas=1 ; sleep 90
kubectl scale deploy cart     -n yas-1 --replicas=1 ; sleep 90
kubectl scale deploy customer -n yas-1 --replicas=1 ; sleep 90
kubectl wait pod -n yas-1 -l 'app.kubernetes.io/name in (cart,product,customer)' \
  --for=condition=Ready --timeout=600s
```

### Bước 6 — Apply Service Mesh policies (file 01-06)

```bash
kubectl apply -f ~/yas-CI-CD/k8s-cd/service-mesh/01-peer-authentication.yaml
kubectl apply -f ~/yas-CI-CD/k8s-cd/service-mesh/02-authorization-policy.yaml
kubectl apply -f ~/yas-CI-CD/k8s-cd/service-mesh/03-retry-virtualservice.yaml
kubectl apply -f ~/yas-CI-CD/k8s-cd/service-mesh/04-curl-client.yaml
kubectl apply -f ~/yas-CI-CD/k8s-cd/service-mesh/05-httpbin-for-retry-demo.yaml
kubectl apply -f ~/yas-CI-CD/k8s-cd/service-mesh/06-destination-rule.yaml
```

Tới đây: **6/6 mesh test pass** (xem `docs/service-mesh-evidence.md`). Đã đáp ứng phần Nâng cao 2 (mTLS + AuthZ + retry).

---

## Bước 7 — (Nâng cao) Browser flow qua Istio Gateway

Bước 7-9 dưới đây mở rộng demo để test full web flow từ browser (đề bài cơ bản #3). Skip nếu chỉ cần đáp ứng Nâng cao 2.

### 7.1. Scale up keycloak-operator + reconcile realm

YAS cài Keycloak operator (scaled=0 sau script 03). Cần scale lên để KeycloakRealmImport reconcile:

```bash
kubectl scale deploy keycloak-operator -n yas-1 --replicas=1
kubectl wait pod -n yas-1 -l app.kubernetes.io/name=keycloak-operator --for=condition=Ready --timeout=120s

# Backup + delete + recreate realm để trigger reconcile (realm import job ban đầu fail vì Keycloak deployment chưa Ready)
kubectl get keycloakrealmimport yas-realm-kc -n yas-1 -o yaml > /tmp/realm-backup.yaml
kubectl delete keycloakrealmimport yas-realm-kc -n yas-1
sleep 5
kubectl apply -f /tmp/realm-backup.yaml

# Đợi job import xong (~2-3 phút)
kubectl wait job/yas-realm-kc -n yas-1 --for=condition=Complete --timeout=300s
```

### 7.2. Apply Istio Gateway thay nginx Ingress

```bash
kubectl apply -f ~/yas-CI-CD/k8s-cd/service-mesh/08-istio-gateway.yaml
```

File `08-istio-gateway.yaml` định nghĩa 1 `Gateway` + 7 `VirtualService` cho 7 host:
- storefront-dev-1, backoffice-dev-1 → BFFs
- api-dev-1 → swagger-ui
- identity-dev-1 → keycloak-service
- akhq-dev-1, kibana-dev-1, pgadmin-dev-1 → tools

### 7.3. Apply edge-permissive override (file 07)

```bash
kubectl apply -f ~/yas-CI-CD/k8s-cd/service-mesh/07-edge-permissive.yaml
```

File này:
- Override PeerAuthentication thành `PERMISSIVE` cho UI/BFF/swagger-ui/keycloak (workload selector)
- AuthZ rule `allow-ingress-to-*` allow source từ namespaces `istio-system` + `ingress-nginx` (cho cả Istio Gateway lẫn fallback nginx)
- AuthZ rule `allow-bff-to-*` allow storefront-bff/backoffice-bff gọi backend services

⚠️ **Quan trọng**: AuthZ rule MẶC ĐỊNH ban đầu allow `ingress-nginx` namespace. Khi dùng Istio Gateway thay nginx → traffic từ namespace `istio-system` → cần update:

```bash
for rule in allow-ingress-to-keycloak allow-ingress-to-storefront-ui allow-ingress-to-storefront-bff; do
  kubectl patch authorizationpolicy $rule -n yas-1 --type=json -p='[
    {"op":"replace","path":"/spec/rules/0/from/0/source/namespaces","value":["ingress-nginx","istio-system"]}
  ]'
done
```

### 7.4. Patch hostAliases cho BFF resolve external domain → Istio Gateway ClusterIP

YAS BFF cần resolve `identity-dev-1.yas.local.com` lúc startup (OAuth2 issuer URL). DNS pod không biết domain này → fail boot.

```bash
GATEWAY_IP=$(kubectl get svc istio-ingressgateway -n istio-system -o jsonpath='{.spec.clusterIP}')

for svc in storefront-bff backoffice-bff; do
  # Patch failureThreshold trước
  kubectl patch deploy/$svc -n yas-1 --type=json -p='[
    {"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/failureThreshold","value":60},
    {"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/failureThreshold","value":60}
  ]'
  # Add hostAliases
  kubectl patch deploy/$svc -n yas-1 --type=json -p="[
    {\"op\":\"add\",\"path\":\"/spec/template/spec/hostAliases\",\"value\":[
      {\"ip\":\"$GATEWAY_IP\",\"hostnames\":[
        \"identity-dev-1.yas.local.com\",
        \"storefront-dev-1.yas.local.com\",
        \"backoffice-dev-1.yas.local.com\",
        \"api-dev-1.yas.local.com\"
      ]}
    ]}
  ]"
done
```

⚠️ Lưu ý: hostAliases **PHẢI trỏ Istio Gateway ClusterIP**, không phải minikube IP. Vì:
- minikube IP:80 = nginx-ingress (no Istio sidecar) → mTLS reject 502
- Gateway ClusterIP:80 = Istio Gateway pod (có Istio cert) → mTLS work

### 7.5. Scale up storefront-bff

```bash
kubectl scale deploy storefront-bff -n yas-1 --replicas=1
kubectl wait pod -n yas-1 -l app.kubernetes.io/name=storefront-bff --for=condition=Ready --timeout=600s
```

BFF cold start ~50-60 giây trên VM share CPU. Sau Ready: pod 2/2 Running, Spring Boot log `Started StorefrontBffApplication in 53.841 seconds`.

### 7.6. Test from VM (trước khi tunnel)

```bash
MINIKUBE_IP=$(minikube ip)
NODEPORT=$(kubectl get svc istio-ingressgateway -n istio-system -o jsonpath='{.spec.ports[?(@.name=="http2")].nodePort}')
echo "Istio Gateway: http://$MINIKUBE_IP:$NODEPORT (NodePort)"

# Keycloak realm Yas should return 200
curl -sS -o /dev/null -w "HTTP %{http_code}\n" -H "Host: identity-dev-1.yas.local.com" \
  http://$MINIKUBE_IP:$NODEPORT/realms/Yas/.well-known/openid-configuration

# BFF root should return 403 (Spring Security default — expected khi chưa login)
curl -sS -o /dev/null -w "HTTP %{http_code}\n" -H "Host: storefront-dev-1.yas.local.com" \
  http://$MINIKUBE_IP:$NODEPORT/
```

### 7.7. (Optional) Setup socat tunnel host:80 → Gateway NodePort cho browser truy cập đẹp

Nếu muốn browser dùng URL `http://storefront-dev-1.yas.local.com/` (port 80) thay vì có port number, cần forward port. Vì nginx-ingress addon đang chiếm port 80, có 2 lựa chọn:

**Option A**: Disable nginx-ingress addon, setup socat host:80 → Gateway:
```bash
minikube addons disable ingress
GATEWAY_NODEPORT=$(kubectl get svc istio-ingressgateway -n istio-system -o jsonpath='{.spec.ports[?(@.name=="http2")].nodePort}')
sudo tee /etc/systemd/system/istio-gateway-tunnel.service > /dev/null <<EOF
[Unit]
Description=Istio Gateway tunnel host:80 → NodePort
After=docker.service network-online.target
[Service]
ExecStart=/usr/bin/socat TCP-LISTEN:80,fork,reuseaddr TCP:$(minikube ip):$GATEWAY_NODEPORT
Restart=always
[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload && sudo systemctl enable --now istio-gateway-tunnel
```

**Option B**: Giữ nginx ingress + dùng port khác cho Istio Gateway (vd 8080), browser url có port.

### 7.8. Test browser

Trên máy local, update `/etc/hosts`:
```
52.139.168.196 storefront-dev-1.yas.local.com
52.139.168.196 backoffice-dev-1.yas.local.com
52.139.168.196 identity-dev-1.yas.local.com
52.139.168.196 api-dev-1.yas.local.com
```

Mở Azure NSG inbound port 80 (Option A) hoặc port 31320 (Option B).

Browser → `http://storefront-dev-1.yas.local.com/` → flow login OAuth qua Keycloak.

---

## Mapping với đề bài

| Deliverable | File / Bước |
|---|---|
| K8s cluster | Bước 1 |
| CI Docker Hub | `.github/workflows/*-ci.yaml` (per service, đã có) |
| Jenkins developer_build | `Jenkinsfile` (đã có) |
| Jenkins destroy | `Jenkinsfile-destroy` (đã có) |
| dev + staging jobs | Skip nếu làm Nâng cao 1 (ArgoCD) |
| Nâng cao 1 ArgoCD | Out of scope session này (xem [Phuc-215/yas](https://github.com/Phuc-215/yas) reference) |
| Nâng cao 2 Service Mesh | Bước 6 (file 01-06) — `docs/service-mesh-setup.md` |
| Observability (Grafana) | Bước 4 (01-script) — `grafana.yas.local.com` |

## Bài học chính từ session (TLDR)

1. **Pattern install-then-scale**: deploy hết Helm release async (KHÔNG `--wait`), scale 0 ngay sau, scale up subset cần. Đây là **đúng** cho VM nhỏ; hardening `--wait --atomic` cho `03-deploy-apps.sh` phản tác dụng.

2. **Probe slow-start**: chart YAS default `failureThreshold=12` không đủ. Quick fix: patch lên 60 trước scale up. Long-term: thêm `startupProbe` vào chart (đã có chart improved trong `k8s/charts/backend/` nhưng `k8s-cd/charts/backend/` deploy thực — chú ý duplicate folder).

3. **Folder duplicate**: `k8s/charts/` ≠ `k8s-cd/charts/`. Jenkins + 03-script dùng `k8s-cd/charts/`. Edit chart phải edit `k8s-cd/charts/`.

4. **DNS resolution OAuth2 trong K8s pod**: BFF cần resolve external hostname Keycloak. Fix bằng `hostAliases` (per-pod) trỏ về **Istio Gateway ClusterIP** (KHÔNG phải minikube IP/nginx). Pattern best practice production: dùng nip.io domain hoặc Keycloak `hostname-backchannel-dynamic=true`.

5. **mTLS STRICT + external Ingress**: nginx-ingress KHÔNG có Istio sidecar → reject ở TLS. Fix: migrate sang Istio Gateway (Gateway pod là Envoy có Istio cert). Hoặc workaround `PeerAuthentication PERMISSIVE` cho workload edge (kèm AuthZ restrict source).

6. **Keycloak realm import job**: ban đầu fail vì Keycloak deployment chưa Ready. Fix: scale up keycloak-operator + delete/recreate KeycloakRealmImport để trigger reconcile.

7. **AuthZ source namespace**: rule `allow-ingress-to-*` ban đầu chỉ allow `ingress-nginx`. Khi migrate Istio Gateway → traffic từ namespace `istio-system` → cần update rule để include cả 2.

Chi tiết hơn về Bài học cho phần mesh: xem `docs/service-mesh-setup.md` mục "Bài học khi triển khai" (10 items).

## File reference trong repo

| File | Mục đích |
|---|---|
| `k8s-cd/service-mesh/01-peer-authentication.yaml` | mTLS STRICT namespace |
| `k8s-cd/service-mesh/02-authorization-policy.yaml` | Default-deny + 5 allow rule |
| `k8s-cd/service-mesh/03-retry-virtualservice.yaml` | Retry policy cho cart/product |
| `k8s-cd/service-mesh/04-curl-client.yaml` | Pod tiện ích test in-mesh |
| `k8s-cd/service-mesh/05-httpbin-for-retry-demo.yaml` | httpbin + retry VS demo |
| `k8s-cd/service-mesh/06-destination-rule.yaml` | Circuit Breaker httpbin |
| `k8s-cd/service-mesh/07-edge-permissive.yaml` | PeerAuthentication PERMISSIVE + AuthZ cho edge workloads (UI/BFF/Keycloak/swagger) |
| `k8s-cd/service-mesh/08-istio-gateway.yaml` | Istio Gateway + 7 VirtualService thay nginx Ingress |
| `docs/service-mesh-setup.md` | README chính 11 bước Service Mesh |
| `docs/service-mesh-evidence.md` | Raw evidence 8 test |
| `docs/redeploy-from-scratch.md` | File này — full e2e redeploy pipeline |
| `docs/images/kiali-topology-*.png` | Screenshots Kiali |
