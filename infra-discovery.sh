#!/bin/bash
#
# Infrastructure Discovery Script
# Discovers compute, network, and storage information
# Usage: ./infra-discovery.sh [--json]
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Output format (text or json)
OUTPUT_FORMAT="text"
if [[ "$1" == "--json" ]]; then
    OUTPUT_FORMAT="json"
fi

print_header() {
    if [[ "$OUTPUT_FORMAT" == "text" ]]; then
        echo ""
        echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════════════════════${NC}"
        echo -e "${BOLD}${CYAN}  $1${NC}"
        echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════════════════════${NC}"
    fi
}

print_section() {
    if [[ "$OUTPUT_FORMAT" == "text" ]]; then
        echo ""
        echo -e "${BOLD}${GREEN}▶ $1${NC}"
        echo -e "${GREEN}────────────────────────────────────────${NC}"
    fi
}

# ============================================================================
# COMPUTE DISCOVERY
# ============================================================================

discover_cpu() {
    print_section "CPU Information"
    
    # Brand/Vendor
    local vendor=$(grep "vendor_id" /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)
    echo -e "${YELLOW}Brand:${NC} $vendor"
    
    # Architecture
    echo -e "${YELLOW}Architecture:${NC} $(uname -m)"
    local model=$(grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)
    echo -e "${YELLOW}Model:${NC} $model"
    
    # CPU count (sockets)
    local sockets=$(grep "physical id" /proc/cpuinfo | sort -u | wc -l)
    [ "$sockets" -eq 0 ] && sockets=1
    echo -e "${YELLOW}CPU Count:${NC} $sockets"
    
    # Core count
    local cores_per_cpu=$(grep "cpu cores" /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)
    [ -z "$cores_per_cpu" ] && cores_per_cpu=$(grep -c "^processor" /proc/cpuinfo)
    local total_cores=$((sockets * cores_per_cpu))
    echo -e "${YELLOW}Core Count:${NC} $total_cores"
    
    # Thread count
    local threads=$(nproc)
    echo -e "${YELLOW}Thread Count:${NC} $threads"
}

discover_memory() {
    print_section "Memory Information"

    
    # Physical RAM slots (requires dmidecode)
    echo -e "\n${YELLOW}Physical RAM Slots:${NC}"
    if command -v dmidecode &> /dev/null; then
        local total_slots=$(dmidecode -t memory 2>/dev/null | grep -c "Memory Device$" || echo "0")
        local used_slots=$(dmidecode -t memory 2>/dev/null | grep "Size:" | grep -cv "No Module Installed" || echo "0")
        local available_slots=$((total_slots - used_slots))
        
        echo "  Total Slots:     $total_slots"
        echo "  Used Slots:      $used_slots"
        echo "  Available Slots: $available_slots"
        
        # Show installed DIMMs
        echo -e "\n${YELLOW}Installed DIMMs:${NC}"
        dmidecode -t memory 2>/dev/null | grep -A 5 "Memory Device" | grep -E "(Size|Type|Speed|Locator):" | grep -v "No Module Installed" | head -20
    else
        echo "  dmidecode not installed (apt install dmidecode)"
    fi
    
    echo -e "${YELLOW}Total Memory:${NC}"
    free -h | grep -E "^(Mem|Swap)" | column -t
    
    echo -e "\n${YELLOW}Memory Details:${NC}"
    cat /proc/meminfo | grep -E "^(MemTotal|MemFree|MemAvailable|Buffers|Cached|SwapTotal|SwapFree|HugePages)"    
}

discover_swap() {
    print_section "Swap Configuration"
    
    echo -e "${YELLOW}Swap Status:${NC}"
    swapon --show 2>/dev/null || echo "No swap configured"
    
    echo -e "\n${YELLOW}Swap Usage:${NC}"
    free -h | grep Swap
    
    echo -e "\n${YELLOW}Swappiness:${NC}"
    cat /proc/sys/vm/swappiness
}

discover_numa() {
    print_section "NUMA Topology"
    
    if command -v numactl &> /dev/null; then
        echo -e "${YELLOW}NUMA Nodes:${NC}"
        numactl --hardware 2>/dev/null || echo "NUMA info not available"
        
        echo -e "\n${YELLOW}NUMA Statistics:${NC}"
        numastat 2>/dev/null || echo "numastat not available"
    else
        echo "numactl not installed. Install with: apt install numactl"
        
        # Fallback to /sys
        if [ -d /sys/devices/system/node ]; then
            echo -e "\n${YELLOW}NUMA Nodes from /sys:${NC}"
            ls -d /sys/devices/system/node/node* 2>/dev/null | wc -l
            for node in /sys/devices/system/node/node*; do
                echo "  $(basename $node): CPUs $(cat $node/cpulist)"
            done
        fi
    fi
}

discover_gpu() {
    print_section "GPU Information"
    
    # Helper function to get PCIe generation from link speed
    get_pcie_gen() {
        local speed="$1"
        case "$speed" in
            *"2.5 GT/s"*) echo "Gen1" ;;
            *"5 GT/s"*|*"5GT/s"*) echo "Gen2" ;;
            *"8 GT/s"*|*"8GT/s"*) echo "Gen3" ;;
            *"16 GT/s"*|*"16GT/s"*) echo "Gen4" ;;
            *"32 GT/s"*|*"32GT/s"*) echo "Gen5" ;;
            *"64 GT/s"*|*"64GT/s"*) echo "Gen6" ;;
            *) echo "Unknown" ;;
        esac
    }
    
    # Check for NVIDIA GPUs
    echo -e "${YELLOW}NVIDIA GPUs:${NC}"
    if command -v nvidia-smi &> /dev/null; then
        nvidia-smi --query-gpu=index,name,memory.total,memory.free,driver_version,pci.bus_id \
            --format=csv,noheader,nounits 2>/dev/null | \
        while IFS=, read -r idx name mem_total mem_free driver pci; do
            echo "  GPU $idx: $name"
            echo "    Memory: ${mem_total}MB total, ${mem_free}MB free"
            echo "    Driver: $driver"
            echo "    PCI: $pci"
        done
        
        echo -e "\n${YELLOW}NVIDIA-SMI Full Output:${NC}"
        nvidia-smi
    else
        echo "  nvidia-smi not found - no NVIDIA GPU or driver not installed"
    fi
    
    # GPU PCIe Details
    echo -e "\n${YELLOW}GPU PCIe Details:${NC}"
    lspci | grep -iE "VGA|3D|NVIDIA|AMD/ATI" | while read line; do
        pci_addr=$(echo "$line" | awk '{print $1}')
        echo "  $line"
        local pci_path="/sys/bus/pci/devices/0000:$pci_addr"
        if [ -f "$pci_path/current_link_speed" ]; then
            local link_speed=$(cat "$pci_path/current_link_speed" 2>/dev/null)
            local link_width=$(cat "$pci_path/current_link_width" 2>/dev/null)
            local pcie_gen=$(get_pcie_gen "$link_speed")
            echo "    PCIe: ${pcie_gen} x${link_width} (${link_speed})"
        fi
    done
}

# ============================================================================
# NETWORK DISCOVERY
# ============================================================================

discover_network_interfaces() {
    print_section "Physical Network Interfaces"
    
    echo -e "${YELLOW}Physical Interfaces:${NC}"
    
    for iface in $(ls /sys/class/net/); do
        # Skip loopback
        [ "$iface" == "lo" ] && continue
        
        # Skip virtual interfaces (no device directory = virtual)
        [ ! -L "/sys/class/net/$iface/device" ] && continue
        
        # Skip common virtual interface patterns
        case "$iface" in
            veth*|docker*|br-*|virbr*|cni*|flannel*|cali*|tunl*|dummy*|bond*|team*)
                continue
                ;;
        esac
        
        echo -e "\n  ${CYAN}$iface:${NC}"
        
        # Speed
        if [ -f /sys/class/net/$iface/speed ]; then
            local speed=$(cat /sys/class/net/$iface/speed 2>/dev/null)
            if [ -n "$speed" ] && [ "$speed" -gt 0 ] 2>/dev/null; then
                if [ "$speed" -ge 1000 ]; then
                    echo "    Speed: $((speed / 1000)) Gbps"
                else
                    echo "    Speed: ${speed} Mbps"
                fi
            else
                echo "    Speed: Link down or unknown"
            fi
        fi
        
        # MAC Address
        if [ -f /sys/class/net/$iface/address ]; then
            echo "    MAC: $(cat /sys/class/net/$iface/address)"
        fi
        
        # Driver
        if [ -L /sys/class/net/$iface/device/driver ]; then
            local driver=$(basename $(readlink /sys/class/net/$iface/device/driver))
            echo "    Driver: $driver"
        fi
        
        # State
        if [ -f /sys/class/net/$iface/operstate ]; then
            echo "    State: $(cat /sys/class/net/$iface/operstate)"
        fi
        
        # IP Address
        local ip=$(ip -4 addr show $iface 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
        [ -n "$ip" ] && echo "    IPv4: $ip"
        
        # PCIe info for this NIC
        local pci_addr=$(ethtool -i $iface 2>/dev/null | grep "bus-info" | awk '{print $2}' | sed 's/0000://')
        if [ -n "$pci_addr" ] && [ -f "/sys/bus/pci/devices/0000:$pci_addr/current_link_speed" ]; then
            local link_speed=$(cat "/sys/bus/pci/devices/0000:$pci_addr/current_link_speed" 2>/dev/null)
            local link_width=$(cat "/sys/bus/pci/devices/0000:$pci_addr/current_link_width" 2>/dev/null)
            echo "    PCIe: x${link_width} (${link_speed})"
        fi
    done
}

discover_storage_pcie() {
    print_section "Storage PCIe Devices"
    
    # Helper function to get PCIe generation from link speed
    get_pcie_gen() {
        local speed="$1"
        case "$speed" in
            *"2.5 GT/s"*) echo "Gen1" ;;
            *"5 GT/s"*|*"5GT/s"*) echo "Gen2" ;;
            *"8 GT/s"*|*"8GT/s"*) echo "Gen3" ;;
            *"16 GT/s"*|*"16GT/s"*) echo "Gen4" ;;
            *"32 GT/s"*|*"32GT/s"*) echo "Gen5" ;;
            *"64 GT/s"*|*"64GT/s"*) echo "Gen6" ;;
            *) echo "Unknown" ;;
        esac
    }
    
    echo -e "${YELLOW}NVMe Devices:${NC}"
    lspci | grep -i "nvme\|Non-Volatile" | while read line; do
        pci_addr=$(echo "$line" | awk '{print $1}')
        echo "  $line"
        local pci_path="/sys/bus/pci/devices/0000:$pci_addr"
        if [ -f "$pci_path/current_link_speed" ]; then
            local link_speed=$(cat "$pci_path/current_link_speed" 2>/dev/null)
            local link_width=$(cat "$pci_path/current_link_width" 2>/dev/null)
            local pcie_gen=$(get_pcie_gen "$link_speed")
            echo "    PCIe: ${pcie_gen} x${link_width} (${link_speed})"
        fi
    done
}

discover_network_bonding() {
    print_section "Network Bonding/Teaming"
    
    if [ -d /proc/net/bonding ]; then
        for bond in /proc/net/bonding/*; do
            echo -e "${YELLOW}Bond: $(basename $bond)${NC}"
            cat "$bond"
        done
    else
        echo "No bonding configured"
    fi
}

# ============================================================================
# STORAGE DISCOVERY
# ============================================================================

discover_disks() {
    print_section "Block Devices (lsblk)"
    
    echo -e "${YELLOW}Disk Overview:${NC}"
    lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,MODEL,SERIAL,TRAN
    
    echo -e "\n${YELLOW}Disk Details:${NC}"
    lsblk -o NAME,SIZE,ROTA,DISC-MAX,RQ-SIZE,MIN-IO,OPT-IO,PHY-SEC,LOG-SEC
}

discover_mountpoints() {
    print_section "Mount Points"
    
    echo -e "${YELLOW}Current Mounts:${NC}"
    df -hT | grep -v "tmpfs\|devtmpfs\|overlay" | column -t
    
    echo -e "\n${YELLOW}All Filesystems:${NC}"
    df -hT | column -t
    
    echo -e "\n${YELLOW}Mount Options:${NC}"
    mount | grep -E "^/dev" | column -t
}

discover_fstab() {
    print_section "Fstab Configuration"
    
    echo -e "${YELLOW}/etc/fstab contents:${NC}"
    cat /etc/fstab | grep -v "^#" | grep -v "^$" | column -t
}

discover_raid() {
    print_section "RAID Configuration"
    
    # Software RAID (mdadm)
    echo -e "${YELLOW}Software RAID (mdadm):${NC}"
    if [ -f /proc/mdstat ]; then
        cat /proc/mdstat
    else
        echo "No software RAID configured"
    fi
    
    # Hardware RAID
    echo -e "\n${YELLOW}Hardware RAID Controllers:${NC}"
    lspci | grep -i raid || echo "No hardware RAID controller detected"
}

discover_lvm() {
    print_section "LVM Configuration"
    
    echo -e "${YELLOW}Physical Volumes:${NC}"
    pvs 2>/dev/null || echo "LVM not configured or insufficient permissions"
    
    echo -e "\n${YELLOW}Volume Groups:${NC}"
    vgs 2>/dev/null || echo "LVM not configured or insufficient permissions"
    
    echo -e "\n${YELLOW}Logical Volumes:${NC}"
    lvs 2>/dev/null || echo "LVM not configured or insufficient permissions"
}

discover_nvme() {
    print_section "NVMe Devices"
    
    if command -v nvme &> /dev/null; then
        echo -e "${YELLOW}NVMe List:${NC}"
        nvme list 2>/dev/null || echo "No NVMe devices or insufficient permissions"
    else
        echo "nvme-cli not installed"
        echo -e "\n${YELLOW}NVMe devices from lsblk:${NC}"
        lsblk | grep nvme || echo "No NVMe devices found"
    fi
}


# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    print_header "INFRASTRUCTURE DISCOVERY REPORT"
    echo -e "${CYAN}Host:${NC} $(hostname)"
    echo -e "${CYAN}Date:${NC} $(date)"
    echo -e "${CYAN}Kernel:${NC} $(uname -r)"
    echo -e "${CYAN}OS:${NC} $(cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '"')"
    
    # Compute
    print_header "🖥️  COMPUTE INFORMATION"
    discover_cpu
    discover_memory
    discover_swap
    discover_numa
    discover_gpu
    
    # Network
    print_header "🌐 NETWORK INFORMATION"
    discover_network_interfaces
    discover_network_bonding
    
    # Storage
    print_header "💾 STORAGE INFORMATION"
    discover_disks
    discover_storage_pcie
    discover_mountpoints
    discover_fstab
    discover_raid
    discover_lvm
    discover_nvme
    
    print_header "DISCOVERY COMPLETE"
    echo ""
}

# Run main function
main "$@"
