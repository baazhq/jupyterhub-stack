# Kubespray Complete Guide

**Version**: v2.29.1  
**Date**: 2026-01-05  
**Source**: [github.com/kubernetes-sigs/kubespray](https://github.com/kubernetes-sigs/kubespray)

---

## 📖 Overview

Kubespray is a composition of Ansible playbooks that enables you to deploy a **production-ready Kubernetes cluster** on bare metal, virtual machines, or cloud infrastructure. It supports:

- ✅ High availability (HA) clusters
- ✅ Multi-platform deployment (AWS, GCP, Azure, OpenStack, vSphere, bare metal)
- ✅ Choice of network plugins (Calico, Cilium, Flannel, etc.)
- ✅ Multiple container runtimes (containerd, CRI-O, Docker)
- ✅ Cluster lifecycle management (add/remove nodes, upgrades)

### Supported Kubernetes Version

Kubespray v2.29.1 supports **Kubernetes v1.30-v1.33**.

---

## 1️⃣ Prerequisites

### 1.1 Control Machine (Ansible Host)

The machine from which you run Kubespray playbooks needs:

| Requirement | Version/Details |
|-------------|-----------------|
| **Python** | 3.9+ |
| **Ansible** | 10.7.0+ (ansible-core 2.17+) |
| **Jinja2** | 2.11+ |
| **python-netaddr** | Required for IP manipulation |

#### Install Dependencies

```bash
# Create Python virtual environment (recommended)
python3 -m venv venv
source venv/bin/activate

# Install Python dependencies
pip install -r requirements.txt
```

**Contents of requirements.txt**:
```
ansible==10.7.0
cryptography==46.0.2  # For community.crypto module
jmespath==1.0.1       # For json_query templating
netaddr==1.3.0        # For IP address manipulation
```

> [!TIP]
> Using a virtual environment prevents conflicts with system Python packages.

---

### 1.2 Target Nodes (Cluster Hosts)

All nodes that will be part of the Kubernetes cluster must meet:

| Requirement | Details |
|-------------|---------|
| **Operating System** | Ubuntu 22.04/24.04, RHEL 8/9, Rocky Linux 8/9, Debian 12, Fedora 39/40 |
| **Memory (Control Plane)** | Minimum 2 GB RAM |
| **Memory (Worker)** | Minimum 1 GB RAM |
| **Internet Access** | Required for pulling container images (or configure offline mode) |
| **IPv4 Forwarding** | Must be enabled |
| **Firewall** | Disabled or properly configured |
| **SSH Access** | Password-less SSH from control machine |
| **Privilege Escalation** | `sudo` access for the SSH user |

#### Prepare Target Nodes

```bash
# On each target node, ensure:

# 1. Enable IPv4 forwarding
sudo sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf

# 2. Disable swap (Kubernetes requirement)
sudo swapoff -a
# Comment out swap entries in /etc/fstab

# 3. Disable firewall (or configure properly)
sudo systemctl disable --now firewalld  # RHEL/Rocky
sudo ufw disable                         # Ubuntu

# 4. Set up SSH key-based authentication from control machine
# (From control machine)
ssh-copy-id user@node-ip
```

---

### 1.3 SSH Configuration

Kubespray connects to all nodes via SSH. Ensure:

```bash
# Test SSH connectivity to all nodes
ssh -i ~/.ssh/id_rsa user@node1 "hostname"
ssh -i ~/.ssh/id_rsa user@node2 "hostname"
# ... repeat for all nodes

# Verify sudo works without password
ssh user@node1 "sudo whoami"
# Should output: root
```

---

## 2️⃣ Cluster Configuration

### 2.1 Configure Inventory File

Edit `inventory/datacouch/inventory.ini`:

```ini
# Define all nodes with their SSH accessible IP addresses
# Format: hostname ansible_host=<IP> [ip=<internal_ip>] [etcd_member_name=<name>]

[kube_control_plane]
master1 ansible_host=192.168.1.10 ip=192.168.1.10 etcd_member_name=etcd1

[etcd:children]
kube_control_plane

[kube_node]
worker1 ansible_host=192.168.1.20 ip=192.168.1.20
worker2 ansible_host=192.168.1.21 ip=192.168.1.21
worker3 ansible_host=192.168.1.22 ip=192.168.1.22

[k8s_cluster:children]
kube_control_plane
kube_node
```

---

### 2.2.1 Configuring Public + Private IPs

In cloud environments or when accessing nodes over the internet, you'll have:
- **Public IP**: For SSH access from your control machine
- **Private IP**: For Kubernetes internal communication between nodes

#### Inventory Variables for Dual-IP Setup

| Variable | Purpose | Example |
|----------|---------|--------|
| `ansible_host` | **Public IP** - Used by Ansible to SSH to the node | `203.0.113.10` |
| `ip` | **Private IP** - Used for Kubernetes internal traffic (pods, services, etcd) | `10.0.0.1` |
| `access_ip` | (Optional) Alternative IP for node access, defaults to `ip` | `10.0.0.1` |
| `etcd_member_name` | Name for etcd cluster membership | `etcd1` |


> [!IMPORTANT]
> **Key Points**:
> - Kubernetes components (kubelet, etcd, API server) bind to the `ip` (private IP)
> - Ansible uses `ansible_host` (public IP) for SSH connections
> - Nodes communicate with each other using their private IPs
> - The `ip` variable MUST be an IP that nodes can reach each other on

#### Example: On-Premises with Single IP

If all nodes are on the same network (typical on-prem):

```ini
# When public IP = private IP, you can omit the ip variable
# or set them to the same value

[kube_control_plane]
master1 ansible_host=192.168.1.10 etcd_member_name=etcd1

[etcd:children]
kube_control_plane

[kube_node]
worker1 ansible_host=192.168.1.20
worker2 ansible_host=192.168.1.21
worker3 ansible_host=192.168.1.22

[k8s_cluster:children]
kube_control_plane
kube_node
```

> [!TIP]
> When `ip` is not specified, Kubespray defaults to using the IP from `ansible_host`.

---

### 2.2.2 Inventory Variable Reference

| Variable | Required | Description |
|----------|----------|-------------|
| `ansible_host` | ✅ Yes | IP/hostname for SSH access |
| `ip` | ⚠️ Recommended | Internal IP for Kubernetes services |
| `access_ip` | ❌ Optional | Alternative access IP (defaults to `ip`) |
| `etcd_member_name` | ✅ For etcd nodes | Unique name for etcd member |
| `ansible_user` | ❌ Optional | SSH user (default from ansible.cfg) |
| `ansible_ssh_private_key_file` | ❌ Optional | Per-node SSH key |

---

### 2.3 Configure Cluster Settings

#### Global Settings (`group_vars/all/all.yml`)

```yaml
# Binaries installation directory
bin_dir: /usr/local/bin

# API server load balancer (for HA)
# Use if you have an external load balancer
# apiserver_loadbalancer_domain_name: "lb.example.com"
# loadbalancer_apiserver:
#   address: 192.168.1.100
#   port: 6443

# Local API server load balancer (nginx on each node)
loadbalancer_apiserver_localhost: true
loadbalancer_apiserver_type: nginx
loadbalancer_apiserver_port: 6443

# Upstream DNS servers
upstream_dns_servers:
  - 8.8.8.8
  - 8.8.4.4

# NTP configuration (important for cluster time sync)
ntp_enabled: true
ntp_manage_config: true
ntp_servers:
  - "0.pool.ntp.org iburst"
  - "1.pool.ntp.org iburst"
```

#### Kubernetes Settings (`group_vars/k8s_cluster/k8s-cluster.yml`)

```yaml
# Kubernetes version (automatically set by Kubespray release)
# Override if needed:
# kube_version: v1.30.0

# Container runtime: docker, containerd, or crio
container_manager: containerd

# Network plugin: calico, cilium, flannel, kube-ovn, kube-router
kube_network_plugin: calico

# Pod network CIDR (must not overlap with existing networks)
kube_pods_subnet: 10.233.64.0/18

# Service network CIDR
kube_service_addresses: 10.233.0.0/18

# Cluster name (used as DNS domain)
cluster_name: cluster.local

# Proxy mode: iptables, ipvs, or nftables
kube_proxy_mode: ipvs

# DNS settings
dns_mode: coredns
enable_nodelocaldns: true

# Download kubectl to control machine
kubeconfig_localhost: true
kubectl_localhost: true

# Automatic certificate renewal
auto_renew_certificates: false
```


---

### 2.4 Configure Add-ons (Optional)

Edit `group_vars/k8s_cluster/addons.yml`:

```yaml
# Helm package manager
helm_enabled: true

# Metrics Server (required for HPA)
metrics_server_enabled: true

# NGINX Ingress Controller
ingress_nginx_enabled: true
ingress_nginx_host_network: false

# MetalLB load balancer (for bare metal)
metallb_enabled: true
metallb_speaker_enabled: true
metallb_ip_range:
  - "192.168.1.200-192.168.1.250"

# Cert-Manager
cert_manager_enabled: true

# CoreDNS
coredns_deployment_replicas: 2
```

---

## 3️⃣ Cluster Creation

### 3.1 Deploy the Cluster

```bash
# Full cluster deployment
ansible-playbook -i inventory/datacouch/inventory.ini cluster.yml \
  -b \
  -v \
  --private-key=~/.ssh/id_rsa
```

**Command Explanation**:

| Flag | Purpose |
|------|---------|
| `-i inventory/...` | Specifies the inventory file with node definitions |
| `cluster.yml` | Main playbook that deploys the entire cluster |
| `-b` / `--become` | Run tasks with privilege escalation (sudo) |
| `-v` | Verbose output (use `-vv` or `-vvv` for more detail) |
| `--private-key=...` | SSH private key for authentication |

> [!NOTE]
> **Deployment Time**: Initial deployment typically takes 15-30 minutes depending on network speed and number of nodes.

### 3.2 Verify Deployment

```bash
# Check if playbook created kubeconfig artifact
ls -la inventory/datacouch/artifacts/

# Use the kubeconfig
export KUBECONFIG=inventory/datacouch/artifacts/admin.conf

# Verify cluster nodes
kubectl get nodes

# Verify system pods
kubectl get pods -n kube-system
```

**Expected Output**:
```
NAME       STATUS   ROLES           AGE   VERSION
master1    Ready    control-plane   10m   v1.30.0
worker1    Ready    <none>          10m   v1.30.0
worker2    Ready    <none>          10m   v1.30.0
worker3    Ready    <none>          10m   v1.30.0
```

---

### 3.3 Access the Cluster

#### From Control Plane Nodes

```bash
# SSH to any control plane node
ssh user@master1

# kubectl is available
kubectl get nodes
```

#### From Your Machine

```bash
# Copy kubeconfig from artifacts
mkdir -p ~/.kube
cp inventory/mycluster/artifacts/admin.conf ~/.kube/config

# Edit if using external IP (if server address is internal IP)
# Change server: https://<internal-ip>:6443 to external IP if needed
vim ~/.kube/config

# Test connection
kubectl get nodes
```

---

## 4️⃣ Adding Nodes

The easiest operation - adds new compute capacity to the cluster.

#### Step 1: Update Inventory

Add the new node(s) to `inventory.ini`:

```ini
[kube_node]
worker1 ansible_host=192.168.1.20
worker2 ansible_host=192.168.1.21
worker3 ansible_host=192.168.1.22
worker4 ansible_host=192.168.1.23  # NEW NODE
worker5 ansible_host=192.168.1.24  # NEW NODE
```

#### Step 2: Refresh Facts Cache

```bash
# Always refresh facts before using --limit
ansible-playbook -i inventory/mycluster/inventory.ini playbooks/facts.yml \
  -b \
  --private-key=~/.ssh/id_rsa
```

**Purpose**: Ensures Ansible has current information about all nodes, including the existing cluster state.

#### Step 3: Run Scale Playbook

```bash
# Add only the new nodes (faster than running cluster.yml)
ansible-playbook -i inventory/mycluster/inventory.ini scale.yml \
  -b \
  -v \
  --private-key=~/.ssh/id_rsa \
  --limit=worker4,worker5
```

**Command Explanation**:

| Flag | Purpose |
|------|---------|
| `scale.yml` | Lightweight playbook that adds new nodes without reconfiguring existing ones |
| `--limit=worker4,worker5` | Only run against the new nodes (much faster) |

**Alternative**: Run without limit to ensure consistency:
```bash
ansible-playbook -i inventory/mycluster/inventory.ini scale.yml -b -v
```

#### Step 4: Verify

```bash
kubectl get nodes
# Should show worker4 and worker5 as Ready
```

---

## 5️⃣ Removing Nodes

### 5.1 Removing Worker Nodes

#### Step 1: Run Remove-Node Playbook

```bash
# Remove specific nodes (node still in inventory)
ansible-playbook -i inventory/mycluster/inventory.ini remove-node.yml \
  -b \
  -v \
  --private-key=~/.ssh/id_rsa \
  -e "node=worker4,worker5"
```

**What this playbook does**:
1. **Drains** the node (evicts all pods safely)
2. **Cordons** the node (marks as unschedulable)
3. **Stops** Kubernetes services (kubelet, kube-proxy)
4. **Deletes** certificates and configuration
5. **Removes** the node from the cluster (`kubectl delete node`)
6. **Resets** the node to pre-Kubernetes state

#### Step 2: Remove from Inventory

After playbook completes, remove the node entries from `inventory.ini`.

#### For Unreachable Nodes

If a node is offline/unreachable:

```bash
# Skip the node reset step
ansible-playbook -i inventory/mycluster/inventory.ini remove-node.yml \
  -b \
  -e "node=worker4" \
  -e "reset_nodes=false" \
  -e "allow_ungraceful_removal=true"
```

| Variable | Purpose |
|----------|---------|
| `reset_nodes=false` | Skip SSH-based cleanup on the node |
| `allow_ungraceful_removal=true` | Allow removal even if pod eviction fails |

---



## 6️⃣ Performing Upgrades

### 6.1 Upgrade Principles

> [!WARNING]
> **Golden Rule**: Never skip minor versions. Upgrade one minor version at a time.
> 
> ✅ v2.27.0 → v2.28.0 → v2.29.0  
> ❌ v2.27.0 → v2.29.0 (skipping v2.28.0)

### 6.2 Graceful Cluster Upgrade

The recommended approach that includes pod draining and cordoning:

```bash
# 1. Update Kubespray to new version
git fetch --all --tags
git checkout v2.30.0

# 2. Update Python dependencies (may have changed)
pip install -r requirements.txt

# 3. Review and merge inventory changes
# Compare new sample with your inventory
diff -r inventory/sample/group_vars inventory/mycluster/group_vars

# 4. Run upgrade playbook
ansible-playbook -i inventory/mycluster/inventory.ini upgrade-cluster.yml \
  -b \
  -v \
  --private-key=~/.ssh/id_rsa
```

**What upgrade-cluster.yml does**:
1. **Cordons** each node (marks unschedulable)
2. **Drains** pods from the node
3. **Upgrades** components (etcd, kubelet, control plane)
4. **Uncordons** the node
5. Repeats for each node sequentially

---

### 6.3 Upgrade Options

#### Control Upgrade Speed

```bash
# Upgrade one node at a time
ansible-playbook upgrade-cluster.yml -b -i inventory/mycluster/inventory.ini \
  -e "serial=1"

# Default: 20% of nodes at a time
```

#### Pause Before Each Node

```bash
# Manual confirmation before each node
ansible-playbook upgrade-cluster.yml -b -i inventory/mycluster/inventory.ini \
  -e "upgrade_node_confirm=true"

# Automatic pause (60 seconds)
ansible-playbook upgrade-cluster.yml -b -i inventory/mycluster/inventory.ini \
  -e "upgrade_node_pause_seconds=60"
```

#### Post-Upgrade Pause (Before Uncordoning)

```bash
# Pause after upgrade, before uncordoning
ansible-playbook upgrade-cluster.yml -b -i inventory/mycluster/inventory.ini \
  -e "upgrade_node_post_upgrade_confirm=true"
```

Use this to:
- Reboot nodes for kernel updates
- Run manual verification tests
- Apply node-level patches

---

### 6.4 Node-Based Upgrade (Partial)

Upgrade specific nodes instead of the whole cluster:

```bash
# 1. Refresh facts for all nodes first
ansible-playbook playbooks/facts.yml -b -i inventory/mycluster/inventory.ini

# 2. Upgrade control plane and etcd first (REQUIRED)
ansible-playbook upgrade-cluster.yml -b -i inventory/mycluster/inventory.ini \
  --limit "kube_control_plane:etcd"

# 3. Upgrade workers in batches
ansible-playbook upgrade-cluster.yml -b -i inventory/mycluster/inventory.ini \
  --limit "worker1:worker2:worker3"

ansible-playbook upgrade-cluster.yml -b -i inventory/mycluster/inventory.ini \
  --limit "worker4:worker5:worker6"
```

---

### 6.5 Component-Specific Upgrades

Upgrade individual components (use with caution):

```bash
# Upgrade containerd/docker
ansible-playbook cluster.yml -b -i inventory/mycluster/inventory.ini \
  --tags=docker

# Upgrade etcd only
ansible-playbook cluster.yml -b -i inventory/mycluster/inventory.ini \
  --tags=etcd

# Upgrade kubelet
ansible-playbook cluster.yml -b -i inventory/mycluster/inventory.ini \
  --tags=node --skip-tags=k8s-gen-certs

# Upgrade control plane components
ansible-playbook cluster.yml -b -i inventory/mycluster/inventory.ini \
  --tags=master

# Upgrade network plugin
ansible-playbook cluster.yml -b -i inventory/mycluster/inventory.ini \
  --tags=network

# Upgrade add-ons
ansible-playbook cluster.yml -b -i inventory/mycluster/inventory.ini \
  --tags=apps
```



### 6.7 Upgrade Verification

After upgrade completes:

```bash
# Check Kubernetes version
kubectl version

# Verify all nodes are Ready
kubectl get nodes

# Check component versions
kubectl get nodes -o wide

# Verify system pods
kubectl get pods -n kube-system

# Run a test deployment
kubectl create deployment nginx --image=nginx
kubectl expose deployment nginx --port=80 --type=NodePort
kubectl get svc nginx
# Test access, then cleanup
kubectl delete deployment nginx
kubectl delete svc nginx
```

---

## 7️⃣ Additional Operations

### 7.1 Reset Cluster

Completely remove Kubernetes from all nodes:

```bash
ansible-playbook -i inventory/mycluster/inventory.ini reset.yml \
  -b \
  --private-key=~/.ssh/id_rsa
```

> [!CAUTION]
> This is **destructive** - it removes all Kubernetes data and configurations.





## 8️⃣ Playbook Reference

| Playbook | Purpose | When to Use |
|----------|---------|-------------|
| `cluster.yml` | Full cluster deployment/update | Initial deployment, adding control plane nodes |
| `scale.yml` | Add worker nodes | Adding worker nodes only |
| `remove-node.yml` | Remove nodes from cluster | Removing any node type |
| `upgrade-cluster.yml` | Graceful cluster upgrade | Kubernetes version upgrades |
| `reset.yml` | Complete cluster teardown | Removing entire cluster |
| `recover-control-plane.yml` | Recover failed control plane | Control plane node failure |
| `playbooks/facts.yml` | Refresh Ansible facts | Before using `--limit` |

---

## 9️⃣ Troubleshooting

### Common Issues

#### Issue: Playbook Fails with SSH Errors

```bash
# Test SSH connectivity
ansible all -i inventory/mycluster/inventory.ini -m ping

# Increase verbosity
ansible-playbook cluster.yml -i inventory/mycluster/inventory.ini -vvv
```

#### Issue: Nodes Not Joining Cluster

```bash
# Check kubelet logs on the failing node
journalctl -u kubelet -f

# Verify certificates
openssl x509 -in /etc/kubernetes/pki/apiserver.crt -text -noout
```

#### Issue: etcd Cluster Issues

```bash
# Check etcd health (run on control plane node)
ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  endpoint health
```

#### Issue: Upgrade Fails Mid-Way

```bash
# Resume from failed point
ansible-playbook upgrade-cluster.yml -b -i inventory/mycluster/inventory.ini \
  --start-at-task="<task name that failed>"
```

---

## 🔟 Best Practices

### Planning

- ✅ **Use version control** for your inventory directory
- ✅ **Document all customizations** made to group_vars
- ✅ **Test upgrades** in a staging environment first
- ✅ **Backup etcd** before any upgrade or node removal

### Operations

- ✅ **Use `--limit` with caution** - always run `facts.yml` first
- ✅ **Monitor during upgrades** - watch `kubectl get nodes` and pods
- ✅ **Keep Kubespray updated** - security patches are important
- ✅ **Maintain odd number of etcd nodes** (3, 5, or 7)

### Security

- ✅ **Disable anonymous auth** in production
- ✅ **Enable encryption at rest** for secrets
- ✅ **Use network policies** to restrict pod communication
- ✅ **Rotate certificates** before expiry

---

## 📚 Quick Command Reference

```bash
# Deploy cluster
ansible-playbook -i inventory/mycluster/inventory.ini cluster.yml -b

# Add workers
ansible-playbook -i inventory/mycluster/inventory.ini scale.yml -b --limit=newnode

# Remove node
ansible-playbook -i inventory/mycluster/inventory.ini remove-node.yml -b -e "node=nodename"

# Upgrade cluster
ansible-playbook -i inventory/mycluster/inventory.ini upgrade-cluster.yml -b

# Reset cluster
ansible-playbook -i inventory/mycluster/inventory.ini reset.yml -b

# Refresh facts (before using --limit)
ansible-playbook -i inventory/mycluster/inventory.ini playbooks/facts.yml -b
```

---

## 📎 Additional Resources

- [Official Kubespray Documentation](https://kubespray.io/)
- [GitHub Repository](https://github.com/kubernetes-sigs/kubespray)
- [Kubernetes Slack - #kubespray channel](https://kubernetes.slack.com)
- [Ansible Documentation](https://docs.ansible.com/)
