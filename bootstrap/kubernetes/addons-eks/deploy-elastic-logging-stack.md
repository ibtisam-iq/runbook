Deploy Elastic logging stack (ECK, Elasticsearch, Filebeat, Kibana) on EKS
==========================================================================

Official sources
----------------

| Resource                    | URL                                                                                           |
|-----------------------------|-----------------------------------------------------------------------------------------------|
| ECK operator Helm chart     | https://artifacthub.io/packages/helm/elastic/eck-operator                                    |
| ECK Elasticsearch chart     | https://artifacthub.io/packages/helm/elastic/eck-elasticsearch                               |
| ECK Beats chart             | https://artifacthub.io/packages/helm/elastic/eck-beats                                       |
| ECK Kibana chart            | https://artifacthub.io/packages/helm/elastic/eck-kibana                                      |
| ECK documentation           | https://www.elastic.co/docs/deploy-manage/deploy/cloud-on-k8s                               |
| Beats on ECK examples       | https://www.elastic.co/docs/deploy-manage/deploy/cloud-on-k8s/configuration-examples-beats  |
| AWS EBS CSI driver (runbook)| https://runbook.ibtisam-iq.com/bootstrap/kubernetes/addons-eks/install-ebs-csi-driver/      |

This runbook deploys a **centralized logging stack** on EKS using:

- **ECK operator** — manages Elasticsearch, Kibana, and Beats via CRDs.  
- **Elasticsearch** — stores and indexes logs on EBS-backed volumes.  
- **Filebeat (eck-beats)** — DaemonSet log shipper, reads container logs and sends to Elasticsearch.  
- **Kibana** — UI for log search and dashboards.  
- **Gateway API + AWS Load Balancer Controller** — exposes Kibana at an HTTPS hostname via ALB.

Data flow:

`Kubernetes pods → container log files on nodes (/var/log/containers) → Filebeat DaemonSet → Elasticsearch (ECK) → Kibana UI → exposed via Gateway + ALB`

Requirements
------------

!!! info
    This runbook assumes:

    - An EKS cluster exists and `kubectl` is configured.  
    - AWS Load Balancer Controller is installed and configured with Gateway API.  
    - Route 53 and ACM are configured for the domain used to expose Kibana.  
    - `helm` and `aws` CLIs are installed.

Check for the presence of the EBS CSI driver addon:

```bash
aws eks list-addons --cluster-name silver-stack-eks --region us-east-1
```

If `aws-ebs-csi-driver` is **not** present, follow this runbook first:

!!! info "Runbook"
    https://runbook.ibtisam-iq.com/bootstrap/kubernetes/addons-eks/install-ebs-csi-driver/

Environment variables
---------------------

```bash
export CLUSTER_NAME=silver-stack-eks
export REGION=us-east-1

# DNS hostname for Kibana
export KIBANA_HOST=kibana.ibtisam.qzz.io

# Optional: name of the Gateway that fronts the ALB
export APP_GATEWAY_NAME=app-alb-gateway
```

Step 1 — Install ECK operator
-----------------------------

!!! note
    ECK components are deployed into the `logging` namespace.  
    If the namespace does not exist, create it with:

    ```bash
    kubectl get namespace logging >/dev/null 2>&1 || kubectl create namespace logging
    ```

Add the Elastic Helm repository:

```bash
helm repo add elastic https://helm.elastic.co
helm repo update
```

Install the **ECK operator** into the `logging` namespace:

```bash
helm install eck-operator elastic/eck-operator \
  --version 3.4.0 \
  -n logging
```

Verify that the operator statefulset is running:

```bash
kubectl get sts,pods,svc,sa -n logging
```

Step 2 — Deploy Elasticsearch via eck-elasticsearch
---------------------------------------------------

!!! info
    A default StorageClass (`gp3`) is required for Elasticsearch PersistentVolumeClaims.  
    To verify the default StorageClass, run:

    ```bash
    kubectl get sc
    ```
    If StorageClass is not `gp3` or not exists, run the following command to create a new StorageClass `gp3` and mark it as default.

    ```bash
    cat <<EOF | kubectl apply -f -
    apiVersion: storage.k8s.io/v1
    kind: StorageClass
    metadata:
      name: gp3
      annotations:
        storageclass.kubernetes.io/is-default-class: "true"
    provisioner: ebs.csi.aws.com
    parameters:
      type: gp3
      fsType: ext4
    reclaimPolicy: Delete
    volumeBindingMode: WaitForFirstConsumer
    allowVolumeExpansion: true
    EOF

    kubectl patch storageclass gp2 -p \
      '{"metadata": {"annotations": {"storageclass.kubernetes.io/is-default-class": "false"}}}'

    kubectl get storageclass
    ```

Install the **eck-elasticsearch** chart into the `logging` namespace:

```bash
helm install eck-elasticsearch elastic/eck-elasticsearch \
  --version 0.19.0 \
  -n logging
```

Check sts, pods and Elasticsearch custom resource:

```bash
kubectl get sts,pods,svc,es -n logging
```

Verify that a PersistentVolume and PersistentVolumeClaim have been provisioned using the cluster default StorageClass:

```bash
kubectl get pv
kubectl get pvc -n logging
```

Step 3 — Deploy Filebeat via eck-beats
--------------------------------------

Filebeat runs as a DaemonSet and ships container logs to Elasticsearch.

### 3.1 Create values file for eck-beats

```bash
mkdir -p helm-values/logging

cat <<'EOF' > helm-values/logging/eck-beats-values.yaml
type: filebeat

# Reference to the Elasticsearch cluster managed by ECK.
elasticsearchRef:
  name: eck-elasticsearch
  namespace: logging

# DaemonSet-level configuration: run Filebeat on every node and mount container log paths.
daemonSet:
  podTemplate:
    spec:
      serviceAccount: elastic-beat-filebeat
      automountServiceAccountToken: true
      terminationGracePeriodSeconds: 30
      dnsPolicy: ClusterFirstWithHostNet
      hostNetwork: true
      containers:
        - name: filebeat
          securityContext:
            runAsUser: 0
          env:
          - name: NODE_NAME
            valueFrom:
              fieldRef:
                fieldPath: spec.nodeName
          volumeMounts:
          - mountPath: /var/log/containers
            name: varlogcontainers
          - mountPath: /var/log/pods
            name: varlogpods
          - mountPath: /var/lib/docker/containers
            name: varlibdockercontainers  
      volumes:
        - name: varlogcontainers
          hostPath:
            path: /var/log/containers
            type: Directory
        - name: varlogpods
          hostPath:
            path: /var/log/pods
            type: Directory
        - name: varlibdockercontainers
          hostPath:
            path: /var/lib/docker/containers
            type: Directory

# Filebeat configuration: Kubernetes autodiscover and log parsing.
config:
  filebeat:
    autodiscover:
      providers:
      - node: ${NODE_NAME}
        type: kubernetes
        hints:
          enabled: true
          default_config:
            type: filestream
            id: kubernetes-container-logs-${data.kubernetes.pod.name}-${data.kubernetes.container.id}
            paths:
              - /var/log/containers/*${data.kubernetes.container.id}.log
            parsers:
              - container: {}
            prospector:
              scanner:
                fingerprint.enabled: true
                symlinks: true
            file_identity.fingerprint: {}
  processors:
    - add_cloud_metadata: {}
    - add_host_metadata: {}

# RBAC: service account, ClusterRole and ClusterRoleBinding for autodiscover.
serviceAccount:
  name: elastic-beat-filebeat
  namespace: logging

clusterRoleBinding:
  name: elastic-beat-autodiscover-binding
  subjects:
  - kind: ServiceAccount
    name: elastic-beat-filebeat
    namespace: logging
  roleRef:
    kind: ClusterRole
    name: elastic-beat-autodiscover
    apiGroup: rbac.authorization.k8s.io

clusterRole:
  name: elastic-beat-autodiscover
  rules:
  - apiGroups: [""]
    resources:
    - events
    - pods
    - namespaces
    - nodes
    verbs:
    - get
    - watch
    - list
  - apiGroups: ["apps"]
    resources:
    - replicasets
    verbs:
    - get
    - list
    - watch
  - apiGroups: ["batch"]
    resources:
    - jobs
    verbs:
    - get
    - list
    - watch
EOF
```

### 3.2 Install eck-beats

```bash
helm upgrade -i eck-beats elastic/eck-beats \
  --version 0.19.0 \
  -f helm-values/logging/eck-beats-values.yaml \
  -n logging
```

Verify Beats health and Filebeat daemonset and pods:

```bash
kubectl get sa,ds,pods,beats -n logging
```

Step 4 — Deploy Kibana via eck-kibana
--------------------------------------

### 4.1 Create values file for eck-kibana

```bash
mkdir -p helm-values/logging

cat <<'EOF' > helm-values/logging/eck-kibana-values.yaml
# Reference to the Elasticsearch cluster managed by ECK.
elasticsearchRef:
  name: eck-elasticsearch
  namespace: logging
EOF
```

### 4.2 Install eck-kibana

```bash
helm install eck-kibana elastic/eck-kibana \
  --version 0.19.0 \
  -f helm-values/logging/eck-kibana-values.yaml \
  -n logging
```

Verify:

```bash
kubectl get deploy,pods,svc,kibana -n logging
```

Step 5 — Expose Kibana via Gateway API and ALB
----------------------------------------------

An HTTPRoute and TargetGroupConfiguration are required to expose Kibana through a Gateway fronted by the AWS Load Balancer Controller.

### 5.1 Determine the Gateway name

```bash
kubectl get gateways.gateway.networking.k8s.io -A
```

Set `APP_GATEWAY_NAME` to the appropriate Gateway name. The examples below assume `app-alb-gateway`:

```bash
export APP_GATEWAY_NAME=app-alb-gateway
export KIBANA_HOST=kibana.ibtisam.qzz.io
```

### 5.2 HTTPRoute for Kibana

```bash
mkdir -p helm-values/logging

cat <<'EOF' > helm-values/logging/httproute-kibana.yaml
apiVersion: gateway.networking.k8s.io/v1beta1
kind: HTTPRoute
metadata:
  name: kibana-route
  namespace: logging
spec:
  hostnames:
    - "${KIBANA_HOST}"        
  parentRefs:
  - group: gateway.networking.k8s.io
    namespace: default
    kind: Gateway
    name: ${APP_GATEWAY_NAME}
    sectionName: http
  - group: gateway.networking.k8s.io
    namespace: default
    kind: Gateway
    name: ${APP_GATEWAY_NAME}
    sectionName: https
  rules:
  - backendRefs:
    - name: eck-kibana-kb-http   # kibana-service created by eck-kibana helm chart
      port: 5601                 # default port for kibana service
EOF

envsubst < helm-values/logging/httproute-kibana.yaml
```

```bash
kubectl apply -f helm-values/logging/httproute-kibana.yaml
```

!!! info "info"
    Traffic to `${KIBANA_HOST}` on the shared Gateway is routed to this Service `eck-kibana-kb-http` on port `5601`.

### 5.3 TargetGroupConfiguration for Kibana

```bash
cat <<'EOF' > helm-values/logging/target-grp-kibana.yaml
apiVersion: gateway.k8s.aws/v1beta1
kind: TargetGroupConfiguration
metadata:
  name: kibana-tg-config
  namespace: logging
spec:
  targetReference:
    name: eck-kibana-kb-http      # Kibana Service created by eck-kibana helm chart
  defaultConfiguration:
    targetType: ip
    protocol: HTTPS
    healthCheckConfig:
      healthCheckProtocol: HTTPS
      healthCheckPath: /api/status
EOF
```

```bash
kubectl apply -f helm-values/logging/target-grp-kibana.yaml
```

!!! info "info"
    `protocol: HTTPS` and `healthCheckProtocol: HTTPS` are used because the ALB terminates TLS and health checks the Kibana HTTPS endpoint on `/api/status`.

### 5.4 Verify Gateway resources

```bash
kubectl get httproute -n logging
kubectl get targetgroupconfiguration -n logging
```

Step 6 — Retrieve credentials and verify logs
---------------------------------------------

### 6.1 Retrieve `elastic` user password

```bash
kubectl get secret eck-elasticsearch-es-elastic-user \
  -n logging \
  -o go-template='{{.data.elastic | base64decode}}'; echo
```

### 6.2 Access Kibana

Open the Kibana URL in a browser:

```text
https://${KIBANA_HOST}
```

Log in with:

- Username: `elastic`.  
- Password: value from the secret above.

Navigate to **Discover**, select the Filebeat index pattern (for example `filebeat-*`), and filter on `kubernetes.namespace` or `app` labels to inspect application logs.

## Quick reference

```bash
# Create logging namespace
kubectl get namespace logging >/dev/null 2>&1 || kubectl create namespace logging

# Add elastic helm repository
helm repo add elastic https://helm.elastic.co
helm repo update

# Install ECK operator
helm install eck-operator elastic/eck-operator \
  --version 3.4.0 \
  -n logging

helm install eck-elasticsearch elastic/eck-elasticsearch \
  --version 0.19.0 \
  -n logging

# Deploy eck-beats
helm upgrade -i eck-beats elastic/eck-beats \
  --version 0.19.0 \
  -f helm-values/logging/eck-beats-values.yaml \
  -n logging

# Install eck-kibana
helm install eck-kibana elastic/eck-kibana \
  --version 0.19.0 \
  -f helm-values/logging/eck-kibana-values.yaml \
  -n logging

# Retrieve elastic user password
kubectl get secret eck-elasticsearch-es-elastic-user \
  -n logging \
  -o go-template='{{.data.elastic | base64decode}}'; echo

sleep 60

# Verify ECK components
kubectl get pods,svc,deploy,sts,ds,sa,elastic -n logging

# Expose Kibana via Gateway API and ALB
kubectl apply -f helm-values/logging/httproute-kibana.yaml
kubectl apply -f helm-values/logging/target-grp-kibana.yaml

# Verify Gateway resources
kubectl get httproute,targetgroupconfiguration -n logging
```
