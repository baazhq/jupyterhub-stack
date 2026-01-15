# Infrastructure Discovery Tool

A comprehensive bash script to discover and report system infrastructure information including compute, network, and storage details.

## Quick Start

```bash
# Make executable
chmod +x infra-discovery.sh

# Run with sudo for full access
sudo ./infra-discovery.sh

# Save to file
sudo ./infra-discovery.sh > server-report.txt
```

---

## Prerequisites

### Required (Built-in on most Linux distributions)

| Command | Description | Package |
|---------|-------------|---------|
| `bash` | Shell interpreter | bash |
| `lspci` | List PCI devices | pciutils |
| `lsblk` | List block devices | util-linux |
| `ip` | Network configuration | iproute2 |
| `df` | Disk space usage | coreutils |
| `mount` | Mount information | util-linux |
| `free` | Memory usage | procps |

### Optional (Enhanced Discovery)

| Command | Description | Ubuntu/Debian | RHEL/Rocky/CentOS |
|---------|-------------|---------------|-------------------|
| `numactl` | NUMA topology | `apt install numactl` | `yum install numactl` |
| `nvme` | NVMe disk details | `apt install nvme-cli` | `yum install nvme-cli` |
| `pvs/vgs/lvs` | LVM information | `apt install lvm2` | `yum install lvm2` |
| `nvidia-smi` | NVIDIA GPU info | nvidia-driver-xxx | nvidia-driver |

---

## Install All Optional Dependencies

### Ubuntu/Debian
```bash
sudo apt update
sudo apt install -y numactl nvme-cli lvm2 pciutils
```

### RHEL/Rocky/CentOS
```bash
sudo yum install -y numactl nvme-cli lvm2 pciutils
```

---

## What It Discovers

### Compute
- CPU model, cores, threads, architecture
- Memory total/available
- Swap configuration
- NUMA topology
- GPU (NVIDIA, AMD, Intel)

### Network
- Interface names, IPs, MACs
- Link speeds and MTU
- PCIe devices and link speeds
- Network bonding

### Storage
- Block devices (lsblk)
- Mount points and filesystems
- fstab configuration
- RAID (hardware and software)
- LVM volumes
- NVMe devices

---

## Usage Examples

```bash
# Run locally
sudo ./infra-discovery.sh

# Run on remote server
ssh user@server 'bash -s' < infra-discovery.sh

# Run via Ansible on all nodes
ansible all -i inventory.ini -m script -a "infra-discovery.sh" --become
```

---

## Output

The script outputs colored, formatted text to stdout. Redirect to a file for logging:

```bash
sudo ./infra-discovery.sh | tee infra-report-$(hostname)-$(date +%Y%m%d).txt
```

---

## Permissions

- **Without sudo**: Basic information only
- **With sudo**: Full hardware details including NVMe, RAID, LVM

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "command not found" | Install the missing package (see table above) |
| "Permission denied" | Run with `sudo` |
| Missing GPU info | Install nvidia-smi or rocm-smi |
| Empty NUMA output | Install numactl package |
