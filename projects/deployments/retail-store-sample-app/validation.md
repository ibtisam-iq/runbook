# Phase 10 — End-to-End Validation

### ALB & Target Groups

```bash
aws elbv2 describe-load-balancers \
  --query "LoadBalancers[].[LoadBalancerName,DNSName,State.Code]" \
  --output table
# k8s-ecomeks-ca3679ea54   k8s-ecomeks-ca3679ea54-681063282.us-east-1.elb.amazonaws.com   active

aws elbv2 describe-target-groups \
  --query "TargetGroups[].[TargetGroupName,Port,Protocol]" \
  --output table
# k8s-monitori-promethe-7e40748f...   9090   HTTP  (Prometheus)
# k8s-monitori-promethe-5084c1bf...   3000   HTTP  (Grafana)
# k8s-ui-ui-c4951b805b               8080   HTTP  (UI)
```

All three target groups report `healthy` in the ALB console resource map.

![ALB Resource Map and Target Groups](https://raw.githubusercontent.com/ibtisam-iq/retail-store-sample-app/main/assets/03-alb-resource-map-and-target-groups.png)

### Application

```bash
curl https://retail-microservices.ibtisam-iq.com
# INCOMING TRANSMISSION — 23:47 UTC
# TO: FIELD AGENT | FROM: HEADQUARTERS, SUPPLIES DIVISION
# RE: GADGET REPOSITORY ACCESS
# Agent, welcome to the repository...
```

Browser: `https://retail-microservices.ibtisam-iq.com` → **"The most public Secret Shop"** ✅

![Retail Store Live over HTTPS](https://raw.githubusercontent.com/ibtisam-iq/retail-store-sample-app/main/assets/04-retail-store-live-over-https.png)

### DNS Resolution

```bash
nslookup retail-microservices.ibtisam-iq.com
# retail-microservices.ibtisam-iq.com → k8s-ecomeks-ca3679ea54-681063282.us-east-1.elb.amazonaws.com
# Addresses: 44.196.200.40, 3.216.252.243
```

### TLS Certificate

```bash
curl -Lv https://retail-microservices.ibtisam-iq.com 2>&1 | grep -E "subject|issuer|SSL"
# subject: CN=retail-microservices.ibtisam-iq.com
# issuer: C=US; O=Amazon; CN=Amazon RSA 2048 M01
# SSL certificate verify ok.
# SSL connection using TLSv1.2 / ECDHE-RSA-AES128-GCM-SHA256
```

### CloudFormation Stacks Summary

| Stack | Created | Status |
|---|---|---|
| `eksctl-ibtisam-iq-eks-cluster-cluster` | 2026-06-06 23:09 | ✅ CREATE_COMPLETE |
| `eks-nodes-stack` | 2026-06-06 23:25 | ✅ CREATE_COMPLETE |
| `eksctl-...-iamserviceaccount-kube-system-aws-load-balancer-controller` | 2026-06-06 23:33 | ✅ CREATE_COMPLETE |
| `eksctl-...-iamserviceaccount-kube-system-ebs-csi-controller-sa` | 2026-06-06 23:35 | ✅ CREATE_COMPLETE |
| `eksctl-...-iamserviceaccount-cart-cart` | 2026-06-06 23:44 | ✅ CREATE_COMPLETE |
| `eksctl-...-iamserviceaccount-orders-orders` | 2026-06-06 23:48 | ✅ CREATE_COMPLETE |
| `eksctl-...-iamserviceaccount-amazon-cloudwatch-fluent-bit` | 2026-06-07 01:17 | ✅ CREATE_COMPLETE |

![](https://raw.githubusercontent.com/ibtisam-iq/retail-store-sample-app/main/assets/01-cloudformation-eks-cluster-stack-create-complete.png)
