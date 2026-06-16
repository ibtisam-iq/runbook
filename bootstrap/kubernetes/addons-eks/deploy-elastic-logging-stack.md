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

- **ECK operator** — manages Elasticsearch, Kibana, and Beats via CRDs  
- **Elasticsearch** — stores and indexes logs on EBS-backed volumes  
- **Filebeat (eck-beats)** — DaemonSet log shipper, reads container logs and sends to Elasticsearch  
- **Kibana** — UI for log search and dashboards  
- **Gateway API + AWS Load Balancer Controller** — exposes Kibana at an HTTPS hostname via ALB

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

- https://runbook.ibtisam-iq.com/bootstrap/kubernetes/addons-eks/install-ebs-csi-driver/

Environment variables
---------------------

```bash
export CLUSTER_NAME=silver-stack-eks
export REGION=us-east-1

# DNS hostname for Kibana (must exist in Route 53 and be covered by an ACM certificate)
export KIBANA_HOST=kibana.ibtisam.qzz.io
```

Step 1 — Create logging namespace
---------------------------------

Create a dedicated namespace for logging components:

```bash
kubectl create namespace logging
```

Step 2 — Install ECK operator
-----------------------------

Add the Elastic Helm repository:

```bash
helm repo add elastic https://helm.elastic.co
helm repo update
```

Install the **ECK operator** into the `logging` namespace:

```bash
helm install eck-operator elastic/eck-operator \
  --version 3.3.0 \
  -n logging
```

Verify that the operator pod is running:

```bash
kubectl get pods -n logging
```

Step 3 — Deploy Elasticsearch via eck-elasticsearch
---------------------------------------------------

!!! info
    Most EKS clusters already have a suitable default StorageClass (`gp2` or `gp3`) configured when the EBS CSI driver runbook is followed.  
    This runbook relies on that default StorageClass and does not create a new one.

Install the **eck-elasticsearch** chart into the `logging` namespace:

```bash
helm install eck-elasticsearch elastic/eck-elasticsearch \
  --version 0.18.0 \
  -n logging
```

Check pods and Elasticsearch custom resource:

```bash
kubectl get pods -n logging
kubectl get elasticsearch -n logging
```

Verify that a PersistentVolume and PersistentVolumeClaim have been provisioned using the cluster default StorageClass:

```bash
kubectl get pv
kubectl get pvc -n logging
```

Step 4 — Deploy Filebeat via eck-beats
--------------------------------------

Filebeat runs as a DaemonSet and ships container logs to Elasticsearch.

### 4.1 Create values file for eck-beats

```bash
mkdir -p helm-values/logging

cat <<'EOF' > helm-values/logging/eck-beats-values.yaml
version: 9.3.0

type: filebeat

elasticsearchRef:
  name: eck-elasticsearch
  namespace: logging

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

### 4.2 Install eck-beats

```bash
helm upgrade -i eck-beats elastic/eck-beats \
  --version 0.18.0 \
  -f helm-values/logging/eck-beats-values.yaml \
  -n logging
```

Verify Beats health and Filebeat pods:

```bash
kubectl get beats -n logging
kubectl get pods -n logging
```

Step 5 — Deploy Kibana via eck-kibana
--------------------------------------

### 5.1 Create values file for eck-kibana

```bash
mkdir -p helm-values/logging

cat <<'EOF' > helm-values/logging/eck-kibana-values.yaml
elasticsearchRef:
  name: eck-elasticsearch
  namespace: logging
EOF
```

### 5.2 Install eck-kibana

```bash
helm install eck-kibana elastic/eck-kibana \
  --version 0.18.0 \
  -f helm-values/logging/eck-kibana-values.yaml \
  -n logging
```

Verify:

```bash
kubectl get kibana -n logging
kubectl get pods -n logging
```

Step 6 — Expose Kibana via Gateway API and ALB
----------------------------------------------

An HTTPRoute and TargetGroupConfiguration are required to expose Kibana through the shared `app-alb-gateway`.

### 6.1 HTTPRoute for Kibana

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
    name: app-alb-gateway
    sectionName: http
  - group: gateway.networking.k8s.io
    namespace: default
    kind: Gateway
    name: app-alb-gateway
    sectionName: https
  rules:
  - backendRefs:
    - name: eck-kibana-kb-http
      port: 5601
EOF

envsubst < helm-values/logging/httproute-kibana.yaml | kubectl apply -f -
```

### 6.2 TargetGroupConfiguration for Kibana

```bash
cat <<'EOF' > helm-values/logging/target-grp-kibana.yaml
apiVersion: gateway.k8s.aws/v1beta1
kind: TargetGroupConfiguration
metadata:
  name: kibana-tg-config
  namespace: logging
spec:
  targetReference:
    name: eck-kibana-kb-http
  defaultConfiguration:
    targetType: ip
    protocol: HTTPS
    healthCheckConfig:
      healthCheckProtocol: HTTPS
      healthCheckPath: /api/status
EOF

kubectl apply -f helm-values/logging/target-grp-kibana.yaml
```

### 6.3 Verify Gateway resources

```bash
kubectl get httproute -n logging
kubectl get targetgroupconfiguration -n logging
```

Step 7 — Retrieve credentials and verify logs
---------------------------------------------

### 7.1 Retrieve `elastic` user password

```bash
kubectl get secret eck-elasticsearch-es-elastic-user \
  -n logging \
  -o go-template='{{.data.elastic | base64decode}}'
echo
```

### 7.2 Access Kibana

Open the Kibana URL in a browser:

```text
https://${KIBANA_HOST}
```

Log in with:

- Username: `elastic`  
- Password: value from the secret above

Navigate to **Discover**, select the Filebeat index pattern (for example `filebeat-*`), and filter on `kubernetes.namespace` or `app` labels to inspect application logs.

File location
-------------

Recommended location in the runbook repository:

```text
bootstrap/kubernetes/addons-eks/deploy-elastic-logging-stack.md
```
