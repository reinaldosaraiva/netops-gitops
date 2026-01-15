# Network Scripts

Scripts for network troubleshooting and monitoring.

## gnmi-subscribe-logs.sh

Real-time streaming telemetry from network switches via gNMI Subscribe.

### Prerequisites

```bash
# Install gnmic
bash -c "$(curl -sL https://get-gnmic.openconfig.net)"
```

### Usage

```bash
# Stream interface statistics (updates every 10s)
./gnmi-subscribe-logs.sh nokia-spine-1 interface

# Get system info once
./gnmi-subscribe-logs.sh arista-spine-1 system --once

# Stream BGP state with custom interval
./gnmi-subscribe-logs.sh nokia-leaf-1 bgp --sample-interval 5
```

### Subscription Types

| Type | Description |
|------|-------------|
| `system` | System information and events |
| `interface` | Interface statistics and counters |
| `cpu` | CPU utilization |
| `memory` | Memory usage |
| `bgp` | BGP session state |
| `lldp` | LLDP neighbor information |

### Switches

| Switch | Address |
|--------|---------|
| nokia-spine-1 | 172.40.40.11:57401 |
| nokia-spine-2 | 172.40.40.12:57401 |
| nokia-leaf-1 | 172.40.40.21:57401 |
| nokia-leaf-2 | 172.40.40.22:57401 |
| arista-spine-1 | 172.20.20.11:6030 |
| arista-leaf-1 | 172.20.20.21:6030 |
| arista-leaf-2 | 172.20.20.22:6030 |

## Debug Pod

For interactive troubleshooting from within Kubernetes cluster:

```bash
# Apply debug pod
kubectl apply -f clusters/kind-arista-lab/debug/network-debug-pod.yaml

# Access shell
kubectl exec -it network-debug -n sdc -- bash

# Inside pod - SSH to Nokia switch
ssh -o StrictHostKeyChecking=no admin@172.40.40.11
# Password: admin123

# Inside pod - SSH to Arista switch
ssh -o StrictHostKeyChecking=no admin@172.20.20.11
# Password: admin

# Ping all switches
kubectl exec -it network-debug -n sdc -- sh -c '
for ip in 172.40.40.11 172.40.40.12 172.40.40.21 172.40.40.22; do
  echo -n "$ip: "; ping -c 1 -W 2 $ip > /dev/null && echo OK || echo FAIL
done
'
```
