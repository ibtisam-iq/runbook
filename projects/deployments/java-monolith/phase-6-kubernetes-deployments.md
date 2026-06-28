# Phase 6: Kubernetes Deployments

After validating the application on containerless EC2 (Phase 4) and serverless ECS Fargate (Phase 5), the final evolution was shifting to full Kubernetes orchestration.

To demonstrate true platform portability, I deployed the application across two entirely different Kubernetes environments—a local Bare-Metal cluster and a production Amazon EKS cluster—using a single set of declarative manifests managed via **Kustomize**.

## Stage 1 — Infrastructure Provisioning

Before orchestrating the application, I provisioned the underlying clusters:

### 1. Bare-Metal Cluster (Local)
I built a custom cluster on an ephemeral iximiuz dev machine using my own automated [`kubeadm` script](https://runbook.ibtisam-iq.com/bootstrap/kubernetes/cluster-kubeadm/). This provided a fast, localized environment to test the Kubernetes deployment logic.

### 2. Amazon EKS (Production)
I provisioned a production-grade EKS cluster within a constrained KodeKloud sandbox environment using Terraform. The full IaC scripts and architectural workarounds for this cluster are thoroughly documented in my companion [EKS on KodeKloud (Terraform) Runbook](https://runbook.ibtisam-iq.com/iac/terraform/provisioning/eks-on-kodekloud-terraform/).

---

## Stage 2 — Kustomize Architecture & Base Manifests

With the infrastructure running, I applied a DRY (Don't Repeat Yourself) architecture using Kustomize. Instead of duplicating YAML files for each cluster, I abstracted the core application logic into a `base` configuration.

### The `base` Directory
The base manifests contain the foundational resources required across all environments:

- **Namespace:** `bankapp`
- **ConfigMap & Secret:** Application configuration and database credentials.
- **StatefulSet (MySQL):** The database deployment and its headless service.
- **Deployment (Spring Boot):** The core Java application and its cluster-internal service.

!!! note
    **Secret Management**
    While the `base/secret.yaml` currently holds placeholder base64 strings for demonstration, in a true production environment, I utilize **HashiCorp Vault** (via the External Secrets Operator) to dynamically inject database credentials into the cluster.

### Storage Class Decoupling
A critical mistake in multi-environment Kubernetes is hardcoding `storageClassName` (e.g., `gp3`) into the base database PVC. This instantly breaks the deployment on bare-metal clusters. 

I intentionally omitted the `storageClassName` from the base `mysql-pvc.yaml`. Instead, it is dynamically injected via Kustomize patches later in the respective overlays.

---

## Stage 3 — Environment Overlays

To handle the vast networking and storage differences between the two clusters, I created two distinct Kustomize overlays. All environment-specific values (such as database endpoints, storage classes, and certificate ARNs) are injected centrally via the `kustomization.yaml` files. Individual resource files remain untouched.

### Overlay A: Bare-Metal (Local)

This overlay is tailored for the `kubeadm` local cluster.

- **Storage:** A patch injects the `local-path` provisioner into the MySQL PVC, allowing the local cluster to provision a HostPath volume for persistence.
- **Routing:** I utilized the `nginx` Gateway API (`nginx-gateway-fabric`). Because bare-metal clusters lack native AWS ALB integration, HTTP-to-HTTPS redirection is handled explicitly within the decoupled `HTTPRoute` manifest.
- **Certificates:** TLS termination is managed dynamically using `cert-manager`, which resolves the HTTP-01 challenge directly inside the cluster to provision Let's Encrypt certificates.

**Deployment Execution:**
```bash
kubectl apply -k k8s/overlays/bare-metal
```

### Overlay B: Amazon EKS (Production)

This overlay natively leverages AWS cloud integrations for the Terraform-provisioned EKS cluster.

- **Storage:** A patch configures the AWS EBS `gp3` StorageClass for high-performance database persistence.
- **Routing & Custom Domain:** The traditional `Ingress` and NGINX Gateway are omitted. Instead, this overlay leverages the **AWS Load Balancer Controller** to dynamically provision an external Application Load Balancer (ALB) via the Gateway API. The ALB is then mapped to my custom domain using **Amazon Route 53**.
- **Certificates (Reusability):** TLS termination happens at the edge. The ACM certificate ARN is injected via a strategic Kustomize patch targeting the `LoadBalancerConfiguration`. Because the **Route 53 Hosted Zone** and **ACM Certificates** are constant infrastructure, they were originally created during the Phase 4 (EC2) containerless deployment and seamlessly reused across Phase 5 (ECS) and this Phase 6 (EKS) deployment.
- **Strategic Autoscaling:** I exclusively introduced a `HorizontalPodAutoscaler` (HPA) in the EKS overlay to scale the application between 2 and 5 replicas. Autoscaling relies on the Kubernetes Metrics Server, which is standard in production but unnecessary in local bare-metal environments (where an HPA would just cause errors).

**Deployment Execution:**
```bash
# Deployed after updating the RDS endpoint and ACM certificate ARN in kustomization.yaml
kubectl apply -k k8s/overlays/eks
```

---

## Stage 4 — Deployment Verification

Regardless of the overlay used, the verification commands remain identical.

```bash
# Verify workloads
kubectl get all -n bankapp

# Verify Gateway API routing
kubectl get gateways -n bankapp
kubectl get httproute -n bankapp
```
