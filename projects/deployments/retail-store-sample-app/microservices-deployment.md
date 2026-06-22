# Phase 7 — Microservices Deployment via Helmfile

### Prepare Ingress Values for UI

!!! info "Why are we editing a values file during deployment?"
    Throughout this project, the upstream Helm charts have been kept pristine and all configuration overrides were pre-authored in dedicated `values-*.yaml` files.
    However, the UI service requires an ALB Ingress with a dynamically generated **ACM Certificate ARN** (created in Phase 5). Because this ARN is generated at runtime and unique to the AWS environment, it must be manually injected into this single `values-alb-ingress.yaml` file before we execute the grand `helmfile apply` command.

Edit `src/ui/chart/values-alb-ingress.yaml` and paste the ACM cert ARN:

```yaml
service:
  type: ClusterIP
  port: 80

ingress:
  enabled: true
  className: alb
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/healthcheck-path: /actuator/health/liveness
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:us-east-1:730335615031:certificate/f0afb980-b86d-47cd-beaf-e8494affd00a
    alb.ingress.kubernetes.io/group.name: ecom-eks
    alb.ingress.kubernetes.io/backend-protocol: HTTP
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80},{"HTTPS":443}]'
    alb.ingress.kubernetes.io/ssl-redirect: "443"
  tls:
    hosts:
      - retail-microservices.ibtisam-iq.com
```

### Deploy All Services

```bash
helmfile -f helmfile/helmfile-eks.yaml apply
```

Helmfile deployed five Helm releases:

| Release | Namespace | Backend | Storage |
|---|---|---|---|
| `catalog` | `catalog` | MySQL 8.0 (StatefulSet) | gp3 PVC 1Gi |
| `cart` | `cart` | DynamoDB (IRSA-bound) | — |
| `orders` | `orders` | PostgreSQL 16.1 (StatefulSet) + SQS | gp3 PVC 1Gi |
| `checkout` | `checkout` | Redis 6.0-alpine | — |
| `ui` | `ui` | ALB Ingress (HTTPS) | — |

### Verify

```bash
# All pods running
kubectl get po -A

# PVCs bound
kubectl get pvc -A
# NAMESPACE   NAME                    STATUS   STORAGECLASS   CAPACITY
# catalog     data-catalog-mysql-0    Bound    gp3            1Gi
# orders      data-orders-postgresql-0 Bound   gp3            1Gi

# Ingress provisioned
kubectl get ingress -A
# NAMESPACE  NAME  CLASS  HOSTS                                    ADDRESS
# ui         ui    alb    retail-microservices.ibtisam-iq.com      k8s-ecomeks-ca3679ea54-681063282.us-east-1.elb.amazonaws.com

# Add CNAME in DNS:
# retail-microservices.ibtisam-iq.com → k8s-ecomeks-ca3679ea54-681063282.us-east-1.elb.amazonaws.com
```

### Validate HTTP→HTTPS Redirect & TLS

```bash
# HTTP should 301 redirect
curl -I http://retail-microservices.ibtisam-iq.com
# HTTP/1.1 301 Moved Permanently
# Location: https://retail-microservices.ibtisam-iq.com:443

# HTTPS should 200 OK
curl -I https://retail-microservices.ibtisam-iq.com
# HTTP/2 200
# content-type: text/plain;charset=UTF-8
```

---
