# Phase 4 & 5: EKS Add-ons & ACM Certificate

### 4A - AWS Load Balancer Controller

!!! info "For more details, see: [Deploy AWS Load Balancer Controller](https://runbook.ibtisam-iq.com/bootstrap/kubernetes/addons-eks/deploy-aws-load-balancer-controller/)

```bash
# 1. Download and create IAM policy
curl -O https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.14.1/docs/install/iam_policy.json

aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file://iam_policy.json

# 2. Create IRSA (IAM Role for Service Account)
eksctl create iamserviceaccount \
  --cluster=$CLUSTER_NAME \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --attach-policy-arn=arn:aws:iam::$ACCOUNT_ID:policy/AWSLoadBalancerControllerIAMPolicy \
  --role-name aws-load-balancer-controller \
  --override-existing-serviceaccounts \
  --region $REGION \
  --approve

# 3. Install via Helm
helm repo add eks https://aws.github.io/eks-charts
helm repo update eks

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --set clusterName="$CLUSTER_NAME" \
  --set region="$REGION" \
  --set vpcId="$VPC_ID" \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --version 1.14.0
```

#### Verify

```bash
kubectl get deploy -n kube-system aws-load-balancer-controller
# NAME                           READY   UP-TO-DATE   AVAILABLE
# aws-load-balancer-controller   2/2     2            2

kubectl get sa -n kube-system aws-load-balancer-controller -o yaml | grep role-arn
# eks.amazonaws.com/role-arn: arn:aws:iam::730335615031:role/aws-load-balancer-controller
```

---

### 4B - EBS CSI Driver

!!! info "For more details, see: [Install EBS CSI Driver](https://runbook.ibtisam-iq.com/bootstrap/kubernetes/addons-eks/install-ebs-csi-driver/)"

```bash
# 1. Create IAM role only (no SA creation yet - addon creates it)
eksctl create iamserviceaccount \
  --name ebs-csi-controller-sa \
  --namespace kube-system \
  --cluster $CLUSTER_NAME \
  --role-name AmazonEKS_EBS_CSI_DriverRole \
  --role-only \
  --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
  --approve

ROLE_ARN=$(aws iam get-role --role-name AmazonEKS_EBS_CSI_DriverRole --query "Role.Arn" --output text)

# 2. Install addon
aws eks create-addon \
  --cluster-name $CLUSTER_NAME \
  --addon-name aws-ebs-csi-driver \
  --resolve-conflicts OVERWRITE
```

!!! warning "SA annotation race condition"
    The addon creates `ebs-csi-controller-sa` asynchronously. Wait for it to appear before annotating - polling with `kubectl get deploy -n kube-system | grep ebs-csi` until `0/2` appears works, then annotate and restart.

```bash
# 3. Annotate SA and restart controller
kubectl annotate serviceaccount ebs-csi-controller-sa \
  -n kube-system \
  eks.amazonaws.com/role-arn=$ROLE_ARN --overwrite

kubectl rollout restart deployment ebs-csi-controller -n kube-system
kubectl rollout status deployment ebs-csi-controller -n kube-system
# deployment "ebs-csi-controller" successfully rolled out
```

### Set gp3 as Default StorageClass

```bash
kubectl apply -f - <<EOF
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

kubectl patch storageclass gp2 \
  -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'

kubectl get sc
# NAME            PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION
# gp2             kubernetes.io/aws-ebs   Delete          WaitForFirstConsumer   false
# gp3 (default)   ebs.csi.aws.com         Delete          WaitForFirstConsumer   true
```

---

## Phase 5 - ACM Certificate (TLS for Custom Domain)

```bash
export CERT_ARN=$(aws acm request-certificate \
  --domain-name retail-microservices.ibtisam-iq.com \
  --validation-method DNS \
  --region us-east-1 \
  --query CertificateArn \
  --output text)
echo $CERT_ARN
# arn:aws:acm:us-east-1:730335615031:certificate/f0afb980-b86d-47cd-beaf-e8494affd00a
```

### Get DNS Validation Record

```bash
aws acm describe-certificate \
  --certificate-arn $CERT_ARN \
  --region us-east-1 \
  --query "Certificate.DomainValidationOptions[0].ResourceRecord"
# {
#   "Name":  "_ab1c5499789efdc982a79ac4fa03a4ee.retail-microservices.ibtisam-iq.com.",
#   "Type":  "CNAME",
#   "Value": "_9d76931dd1cbceac5d14293b7463ce92.jkddzztszm.acm-validations.aws."
# }
```

!!! note "DNS Validation"
    I added the CNAME record to the `ibtisam-iq.com` DNS zone in Cloudflare. ACM polls until the record resolves, then marks the certificate as `ISSUED`.

```bash
# Block until ISSUED (usually ~10-15 min)
aws acm wait certificate-validated --certificate-arn $CERT_ARN --region us-east-1

aws acm describe-certificate --certificate-arn $CERT_ARN --region us-east-1 \
  --query "Certificate.Status"
# "ISSUED"
```

---
