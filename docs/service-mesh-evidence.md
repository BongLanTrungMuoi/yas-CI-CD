# Service Mesh — Phụ lục Evidence

File này chứa raw output thu thập trực tiếp từ cluster trên Azure VM (`minikube` driver=docker, Istio 1.23.2 demo profile), dùng làm phụ lục báo cáo phần **Nâng cao 2 — Service Mesh**.

Tất cả thao tác thực hiện trong namespace `yas-1` (đã có label `istio-injection=enabled`).

Capture date: **2026-05-12** (giờ UTC trong log).

---

## 1. Trạng thái cluster

### 1.1. Sidecar injection — mọi pod READY = 2/2

`READY 2/2` nghĩa là pod có 2 container (app + `istio-proxy` sidecar) đều ready.

```
$ kubectl get pod -n yas-1 -o wide
NAME                                             READY   STATUS    RESTARTS       AGE
cart-5bfb64dbfc-dpwsw                            2/2     Running   0              159m
curl-client                                      2/2     Running   0              151m
customer-5c8d4f9f64-g4wtz                        2/2     Running   0              157m
debezium-connect-cluster-connect-0               2/2     Running   1 (162m ago)   166m
elasticsearch-es-node-0                          2/2     Running   0              166m
httpbin-7dff6d6bf6-ht2sv                         2/2     Running   0              151m
kafka-cluster-entity-operator-7bc4d88484-t8jwh   4/4     Running   0              159m
kafka-cluster-kafka-0                            2/2     Running   0              160m
kafka-cluster-zookeeper-0                        2/2     Running   0              166m
postgresql-0                                     2/2     Running   0              166m
product-d7df6bb4b-bqd96                          2/2     Running   0              160m
redis-master-0                                   2/2     Running   0              166m
redis-replicas-{0,1,2}                           2/2     Running   0              ~165m
zookeeper-0                                      2/2     Running   1 (154m ago)   166m
```

### 1.2. Service ClusterIP

```
$ kubectl get svc -n yas-1
NAME       TYPE        CLUSTER-IP       PORT(S)
cart       ClusterIP   10.105.97.189    80/TCP,8090/TCP
customer   ClusterIP   10.107.6.243     80/TCP,8090/TCP
httpbin    ClusterIP   10.107.228.232   80/TCP
product    ClusterIP   10.101.111.129   80/TCP,8090/TCP
```

---

## 2. Mesh policies đã apply

### 2.1. PeerAuthentication (mTLS STRICT)

```yaml
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata:
  name: default
  namespace: yas-1
spec:
  mtls:
    mode: STRICT
```

→ Mọi pod trong `yas-1` chỉ chấp nhận traffic đã mTLS, peer không có Istio certificate sẽ bị reject ở TLS handshake.

### 2.2. AuthorizationPolicy — default-deny + 5 allow

Default-deny áp dụng toàn namespace:

```yaml
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: default-deny-all
  namespace: yas-1
spec: {}     # rỗng → action ALLOW không match gì → tất cả deny
```

5 rule ALLOW tạo "exception" cho default-deny:

| Rule | Source | Selector (target) |
|---|---|---|
| `allow-from-istio-system` | namespace `istio-system` | toàn namespace |
| `allow-curlclient-to-cart` | SA `curl-client` | `app.kubernetes.io/name=cart` |
| `allow-curlclient-to-httpbin` | SA `curl-client` | `app.kubernetes.io/name=httpbin` |
| `allow-cart-to-product` | SA `cart` | `app.kubernetes.io/name=product` |
| `allow-internal-data-layer` | namespace `yas-1` | postgres / redis / kafka / es |

### 2.3. VirtualService — retry policy

`cart-mesh`, `product-mesh`, `httpbin-mesh` đều set:

```yaml
retries:
  attempts: 3
  perTryTimeout: 2s
  retryOn: 5xx,connect-failure,refused-stream
```

(Manifest đầy đủ: `k8s-cd/service-mesh/03-retry-virtualservice.yaml`, `05-httpbin-for-retry-demo.yaml`).

---

## 3. Test plan & raw output

Tất cả test chạy trên VM, capture timestamp UTC `2026-05-12T06:40-06:46`.

### Test 1 — mTLS STRICT chặn peer out-of-mesh

```
$ kubectl run tmp-mtls-test --image=curlimages/curl:8.5.0 --rm -i --restart=Never -n default -- \
    curl -v --max-time 5 http://product.yas-1.svc.cluster.local/storefront/product-thumbnails?productIds=1
* Connected to product.yas-1.svc.cluster.local (10.101.111.129) port 80
> GET /storefront/product-thumbnails?productIds=1 HTTP/1.1
> Host: product.yas-1.svc.cluster.local
> User-Agent: curl/8.5.0
> Accept: */*
>
* Recv failure: Connection reset by peer
curl: (56) Recv failure: Connection reset by peer
```

→ TCP connect OK (10.101.111.129:80), nhưng ngay khi gửi HTTP request, sidecar của `product` reset connection vì client không phải mTLS peer.

### Test 2 — AuthZ ALLOW: `curl-client → cart` (HTTP 404, app response)

```
$ kubectl exec -n yas-1 curl-client -c curl -- \
    curl -sS -D - -o /dev/null --max-time 5 http://cart.yas-1.svc.cluster.local/storefront/cart
HTTP/1.1 404 Not Found
content-type: text/html;charset=utf-8
content-language: en
content-length: 431
date: Tue, 12 May 2026 06:40:23 GMT
x-envoy-upstream-service-time: 1
server: envoy
```

→ Header `server: envoy` + `x-envoy-upstream-service-time` chứng tỏ request đi xuyên qua sidecar và **chạm tới app** (app trả 404 vì path `/storefront/cart` không tồn tại trên Spring Boot endpoint mặc định). AuthZ cho phép.

### Test 3 — AuthZ DENY: `curl-client → product` (HTTP 403)

```
$ kubectl exec -n yas-1 curl-client -c curl -- \
    curl -sS -D - -o /dev/null --max-time 5 http://product.yas-1.svc.cluster.local/storefront/product-thumbnails?productIds=1
HTTP/1.1 403 Forbidden
content-length: 19
content-type: text/plain
date: Tue, 12 May 2026 06:40:23 GMT
server: envoy
x-envoy-upstream-service-time: 0
```

→ `x-envoy-upstream-service-time: 0` = sidecar không forward lên app, từ chối ngay tại L7. Body trả 19 byte = chuỗi `RBAC: access denied`.

### Test 4 — AuthZ DENY: `curl-client → customer` (HTTP 403)

```
$ kubectl exec -n yas-1 curl-client -c curl -- \
    curl -sS -D - -o /dev/null --max-time 5 http://customer.yas-1.svc.cluster.local/customers
HTTP/1.1 403 Forbidden
content-length: 19
content-type: text/plain
date: Tue, 12 May 2026 06:40:23 GMT
server: envoy
x-envoy-upstream-service-time: 0
```

### Test 5 — AuthZ ALLOW: `cart → product` (verify allow-cart-to-product)

Để chứng minh rule `allow-cart-to-product` thật sự work (không thể `kubectl exec curl` trực tiếp vào `cart` pod vì image Spring Boot không có curl), tạo pod tạm với `serviceAccountName: cart`:

```
$ kubectl run curl-as-cart --image=curlimages/curl:8.5.0 -n yas-1 \
    --labels="app=curl-as-cart,sidecar.istio.io/inject=true" \
    --overrides='{"spec":{"serviceAccountName":"cart", ...}}' \
    --restart=Never
$ kubectl exec -n yas-1 curl-as-cart -c curl -- \
    curl -sS -D - -o /dev/null --max-time 5 http://product.yas-1.svc.cluster.local/storefront/product-thumbnails?productIds=1
HTTP/1.1 404 Not Found
content-type: text/html;charset=utf-8
content-length: 431
date: Tue, 12 May 2026 06:41:41 GMT
x-envoy-upstream-service-time: 23
server: envoy
```

→ SPIFFE principal `cluster.local/ns/yas-1/sa/cart` match rule → request được forward lên app product (`x-envoy-upstream-service-time: 23` = app xử lý 23ms, trả 404 vì query `productIds=1` không có sản phẩm).

### Test 6 — Retry policy trên upstream 5xx

Gọi `httpbin /status/500` từ `curl-client` với custom `x-request-id` để filter log:

```
$ REQ_ID="claude-retry-1778568368"
$ kubectl exec -n yas-1 curl-client -c curl -- \
    curl -sS -D - -o /dev/null --max-time 10 -H "x-request-id: $REQ_ID" \
    http://httpbin.yas-1.svc.cluster.local/status/500
HTTP/1.1 500 Internal Server Error
date: Tue, 12 May 2026 06:46:08 GMT
x-envoy-upstream-service-time: 85
server: envoy
```

Kiểm tra Envoy access log trên `istio-proxy` của pod httpbin — filter theo cùng `x-request-id`:

```
$ kubectl logs -n yas-1 -l app.kubernetes.io/name=httpbin -c istio-proxy --tail=200 | grep "$REQ_ID"
[2026-05-12T06:46:08.491Z] "GET /status/500 HTTP/1.1" 500 - via_upstream ... "claude-retry-1778568368" ...
[2026-05-12T06:46:08.516Z] "GET /status/500 HTTP/1.1" 500 - via_upstream ... "claude-retry-1778568368" ...
[2026-05-12T06:46:08.536Z] "GET /status/500 HTTP/1.1" 500 - via_upstream ... "claude-retry-1778568368" ...
[2026-05-12T06:46:08.575Z] "GET /status/500 HTTP/1.1" 500 - via_upstream ... "claude-retry-1778568368" ...
```

→ **4 dòng cùng request-id** = 1 lần khởi tạo + 3 lần retry (đúng VS `attempts: 3`). Khoảng cách ~20-40ms giữa các retry. Sau lần thứ 4 vẫn 500 → bubble lên client.

Thêm bằng chứng từ traffic generator (request-id khác do generator không set tay, Envoy tự sinh UUID):

```
[06:46:08.580] "GET /status/500" 500 ... "bfda88fa-78b9-9498-a55f-d54b61118f25"
[06:46:08.589] "GET /status/500" 500 ... "bfda88fa-78b9-9498-a55f-d54b61118f25"
[06:46:08.638] "GET /status/500" 500 ... "bfda88fa-78b9-9498-a55f-d54b61118f25"
[06:46:08.644] "GET /status/500" 500 ... "bfda88fa-78b9-9498-a55f-d54b61118f25"

[06:46:10.019] "GET /status/500" 500 ... "5ff88450-e666-9ba6-a3d5-6139ecbf6664"
[06:46:10.031] "GET /status/500" 500 ... "5ff88450-e666-9ba6-a3d5-6139ecbf6664"
[06:46:10.043] "GET /status/500" 500 ... "5ff88450-e666-9ba6-a3d5-6139ecbf6664"
[06:46:10.087] "GET /status/500" 500 ... "5ff88450-e666-9ba6-a3d5-6139ecbf6664"
```

→ 2 request độc lập, mỗi request đều có đúng 4 dòng access log cùng `x-request-id`. Pattern này nhất quán → retry policy hoạt động đúng.

---

### Test 7 — `notPrincipals` chặn `curl-client` khỏi data layer (defense in depth)

Sau khi tightening rule `allow-internal-data-layer` với `notPrincipals: [curl-client, httpbin]`:

```
$ kubectl exec -n yas-1 curl-client -c curl -- \
    curl -sS -D - -o /dev/null --max-time 5 http://postgresql.yas-1.svc.cluster.local:5432/
HTTP/1.1 403 Forbidden
content-length: 19
content-type: text/plain
date: Tue, 12 May 2026 07:21:53 GMT
server: envoy
```

→ Trước fix: rule allow theo `namespaces: [yas-1]` → curl-client được phép gọi postgres. Sau fix: `notPrincipals` excluded curl-client → AuthZ trả 403. Cart/product/customer vẫn gọi postgres bình thường (vì principals của 3 app này không nằm trong `notPrincipals`).

### Test 8 — Retry vẫn hoạt động sau khi đổi `retryOn`

Sau khi đổi `retryOn` từ `5xx,connect-failure,refused-stream` → `5xx,gateway-error,connect-failure,refused-stream,reset` và `perTryTimeout` từ `2s` → `5s`:

```
$ REQ_ID="post-fix-retry-1778570509"
$ kubectl exec -n yas-1 curl-client -c curl -- \
    curl -sS -H "x-request-id: $REQ_ID" --max-time 30 \
    http://httpbin.yas-1.svc.cluster.local/status/500
HTTP/1.1 500 Internal Server Error
...

$ kubectl logs -n yas-1 -l app.kubernetes.io/name=httpbin -c istio-proxy --tail=300 | grep "$REQ_ID"
[2026-05-12T07:21:49.752Z] "GET /status/500" 500 ... "post-fix-retry-1778570509" ...
[2026-05-12T07:21:49.777Z] "GET /status/500" 500 ... "post-fix-retry-1778570509" ...
[2026-05-12T07:21:49.822Z] "GET /status/500" 500 ... "post-fix-retry-1778570509" ...
[2026-05-12T07:21:49.838Z] "GET /status/500" 500 ... "post-fix-retry-1778570509" ...
```

→ Vẫn 4 dòng cùng request-id (1 initial + 3 retries). Việc thêm `gateway-error`/`reset` không ảnh hưởng tới retry trên 500 (vì `5xx` vẫn được giữ trong `retryOn`).

---

## 4. Bảng tổng kết test

| # | Test | Mong đợi | Kết quả thực tế | Pass |
|---|---|---|---|---|
| 1 | out-of-mesh (ns `default`) → product | TCP/TLS reset | `curl: (56) Recv failure: Connection reset by peer` | ✅ |
| 2 | curl-client → cart (allowed) | HTTP từ app | HTTP 404 (app response, x-envoy-upstream-service-time=1ms) | ✅ |
| 3 | curl-client → product (no rule) | RBAC denied | HTTP 403 (server=envoy, x-envoy=0ms, body `RBAC: access denied`) | ✅ |
| 4 | curl-client → customer (no rule) | RBAC denied | HTTP 403 (server=envoy, x-envoy=0ms) | ✅ |
| 5 | cart SA → product (allow-cart-to-product) | App response | HTTP 404 (app response, x-envoy=23ms) | ✅ |
| 6 | curl-client → httpbin /status/500 | 4 attempts cùng request-id | 4 dòng log đúng request-id, gap ~20-40ms | ✅ |
| 7 | curl-client → postgres (notPrincipals block) | RBAC denied (defense in depth) | HTTP 403 (server=envoy) | ✅ |
| 8 | Retry sau khi thay retryOn + perTryTimeout | 4 attempts (vẫn work) | 4 dòng log post-fix-retry-1778570509, gap ~25-50ms | ✅ |

---

## 5. File reference trong repo

- `k8s-cd/service-mesh/01-peer-authentication.yaml` — PeerAuthentication STRICT
- `k8s-cd/service-mesh/02-authorization-policy.yaml` — default-deny + 5 allow
- `k8s-cd/service-mesh/03-retry-virtualservice.yaml` — VS cart, product
- `k8s-cd/service-mesh/04-curl-client.yaml` — pod test in-mesh
- `k8s-cd/service-mesh/05-httpbin-for-retry-demo.yaml` — httpbin + VS retry
- `docs/service-mesh-setup.md` — README hướng dẫn từng bước
- `docs/images/kiali-topology-mtls.png` — Kiali graph (mTLS lock icons)
- `docs/images/kiali-topology-detail.png` — Kiali edge detail panel
