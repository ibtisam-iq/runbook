# Deploy MetalLB Load Balancer on Bare-Metal Kubernetes

On cloud-managed Kubernetes (EKS, GKE, AKS), creating a `Service` of type
`LoadBalancer` automatically provisions a cloud load balancer and assigns a
stable external IP. On bare-metal kubeadm clusters, no such integration
exists — the Service stays in `<pending>` for `EXTERNAL-IP` forever.

**MetalLB** fills this gap. It is a load balancer implementation for bare-metal
clusters that watches for `LoadBalancer` Services and assigns IP addresses
from a pool we define. This is what enables `ingress-nginx` to receive a real
IP on bare-metal instead of a random `NodePort`.

!!! info "Official Documentation"
    - [MetalLB Installation](https://metallb.universe.tf/installation/)
    - [MetalLB Configuration](https://metallb.universe.tf/configuration/)
    - [MetalLB GitHub](https://github.com/metallb/metallb)

---

## How MetalLB Works

MetalLB deploys two components into the `metallb-system` namespace:

| Component | Kind | Role |
|---|---|---|
| `controller` | Deployment | Watches Services; assigns IPs from the pool |
| `speaker` | DaemonSet | Runs on every node; announces IPs to the network |

MetalLB supports two announcement protocols. Choose based on the network:

| Mode | How It Works | Best For |
|---|---|---|
| **Layer 2 (L2)** | Speaker responds to ARP requests for the assigned IP | Home labs, simple bare-metal, single subnet |
| **BGP** | Speaker peers with the router via BGP and advertises the IP | Data centers, multi-subnet, production HA |

!!! note "This runbook covers Layer 2 mode"
    L2 mode requires zero router configuration and works on any flat network.
    BGP mode requires a router that speaks BGP and is beyond the scope of
    this runbook.

    **L2 limitation:** Only one node handles traffic for a given IP at a time
    (the node whose speaker won the ARP election). Failover is automatic but
    not instant — clients may see a brief interruption (~10s) during node failure.

---

## Prerequisites

- A running kubeadm bare-metal cluster
- `kubectl` configured and all nodes `Ready`
- A range of **unused IP addresses on the local subnet** to give to MetalLB
  (these must not be assigned to any node or used by the DHCP server)
- `ingress-nginx` already deployed (see `deploy-ingress-nginx-controller.md`)

!!! warning "Find the subnet range before proceeding"
    Run `ip addr show` on any cluster node to find the subnet (e.g.,
    `192.168.1.0/24`). Then pick a small range of IPs that are **outside**
    the DHCP lease range. Example: if DHCP assigns `.100–.200`, it can
    safely use `192.168.1.240–192.168.1.250` for MetalLB.

---

## Step 1 — Enable Strict ARP (If Using IPVS Mode)

Skip this step if the cluster uses the default `iptables` kube-proxy mode.
Only required if `kube-proxy` is configured in IPVS mode.

```bash
# Check if IPVS mode is active
kubectl get configmap kube-proxy -n kube-system -o yaml | grep mode
```

If the output shows `mode: "ipvs"`, enable strict ARP:

```bash
kubectl get configmap kube-proxy -n kube-system -o yaml | \
  sed -e "s/strictARP: false/strictARP: true/" | \
  kubectl apply -f - -n kube-system
```

---

## Step 2 — Deploy MetalLB

```bash
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.15.3/config/manifests/metallb-native.yaml
```

This creates the `metallb-system` namespace and deploys the `controller`
Deployment and `speaker` DaemonSet.

!!! note
    The installation manifest deploys MetalLB components but leaves them
    **completely idle**. No IPs are assigned, no traffic is handled until
    applying the configuration CRs in the next steps.

Verify both components are running:

```bash
kubectl get pods -n metallb-system
```

Expected output:

```
NAME                          READY   STATUS    RESTARTS
controller-xxxxxxxxxx-xxxxx   1/1     Running   0
speaker-xxxxx                 1/1     Running   0
speaker-yyyyy                 1/1     Running   0   # one per node
```

---

## Step 3 — Define an IP Address Pool

Create an `IPAddressPool` CR that tells MetalLB which IPs it is allowed to
assign to `LoadBalancer` Services:

```yaml
# metallb-ipaddresspool.yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: first-pool
  namespace: metallb-system
spec:
  addresses:
    - <start-ip>-<end-ip>   # e.g., 192.168.1.240-192.168.1.250
```

```bash
kubectl apply -f metallb-ipaddresspool.yaml
```

!!! tip "Multiple ranges are supported"
    Multiple CIDR blocks or ranges can define in a single pool:

    ```yaml
    spec:
      addresses:
        - 192.168.1.240-192.168.1.250
        - 192.168.1.100/32    # single IP
    ```

---

## Step 4 — Configure L2 Advertisement

Create an `L2Advertisement` CR to tell MetalLB to announce the IPs from
the pool using Layer 2 / ARP:

```yaml
# metallb-l2advertisement.yaml
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: l2-advert
  namespace: metallb-system
spec:
  ipAddressPools:
    - first-pool
```

```bash
kubectl apply -f metallb-l2advertisement.yaml
```

!!! note
    Omitting `spec.ipAddressPools` causes MetalLB to advertise IPs from
    **all** pools via L2. Specifying the pool name explicitly is a safer
    practice when there are multiple pools with different purposes.

---

## Step 5 — Verify MetalLB Assigned an IP to ingress-nginx

```bash
kubectl get svc -n ingress-nginx
```

Expected output (before MetalLB):

```
NAME                       TYPE           CLUSTER-IP     EXTERNAL-IP   PORT(S)
ingress-nginx-controller   LoadBalancer   10.96.x.x      <pending>     80:3xxxx/TCP
```

Expected output (after MetalLB):

```
NAME                       TYPE           CLUSTER-IP     EXTERNAL-IP     PORT(S)
ingress-nginx-controller   LoadBalancer   10.96.x.x      192.168.1.240   80:3xxxx/TCP,443:3xxxx/TCP
```

!!! success
    Once `EXTERNAL-IP` shows a real IP from the pool, MetalLB is working.
    All HTTP/HTTPS traffic sent to `192.168.1.240` on the local network
    will now reach the `ingress-nginx` controller directly on ports 80 and 443.

---

## Troubleshooting

### EXTERNAL-IP stays `<pending>` after applying CRs

```bash
kubectl logs -n metallb-system deploy/controller
```

Check for errors like `no available IPs` (pool exhausted) or
`no IPAddressPool matches` (pool selector mismatch).

### Speaker pod is not running on a node

```bash
kubectl get pods -n metallb-system -o wide
kubectl describe pod <speaker-pod> -n metallb-system
```

The speaker runs as a privileged DaemonSet. If Pod Security Admission is
enforced, the `metallb-system` namespace must be labeled:

```bash
kubectl label namespace metallb-system \
  pod-security.kubernetes.io/enforce=privileged \
  pod-security.kubernetes.io/audit=privileged \
  pod-security.kubernetes.io/warn=privileged
```

### IP is assigned but traffic does not reach the Service

Verify the ARP entry on the local machine:

```bash
arp -n | grep <assigned-ip>
```

If missing, check that the router/switch is on the same L2 segment as the
cluster nodes and is not blocking ARP.

!!! warning "MetalLB does not work on most cloud providers"
    Cloud VMs (AWS EC2, GCP, Azure) use SDN that blocks the ARP announcements
    MetalLB relies on in L2 mode. Use the cloud provider's native LoadBalancer
    integration instead. See [MetalLB Cloud Compatibility](https://metallb.universe.tf/installation/clouds/).
