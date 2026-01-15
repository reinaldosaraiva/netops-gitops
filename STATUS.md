# NetOps GitOps Status

**Last Updated:** 2026-01-15 20:20 UTC
**Status:** OPERATIONAL

---

## Overview

| Metric | Value |
|--------|-------|
| Resources Managed via GitOps | 12 |
| SDC Configs (Ready) | 10/10 |
| SDC Targets (Ready) | 7/7 |
| Debug Pod | Running (heartbeat logs) |
| ArgoCD Sync Status | Synced |
| GitHub Repo | https://github.com/reinaldosaraiva/netops-gitops |

---

## Config Status Summary

### Arista cEOS (OpenConfig YANG)

| Config | Target | Status | Priority |
|--------|--------|--------|----------|
| arista-spine1-interface-desc | spine-1-arista | Ready | 10 |
| arista-spine1-topology | spine-1-arista | Ready | 15 |
| arista-leaf1-interface-desc | leaf-1-arista | Ready | 10 |
| arista-leaf1-topology | leaf-1-arista | Ready | 15 |
| arista-leaf2-interface-desc | leaf-2-arista | Ready | 10 |
| arista-leaf2-topology | leaf-2-arista | Ready | 15 |

### Nokia SR Linux (Native YANG) - MAC-VRF with IRB

| Config | Target | IRB IP | Status |
|--------|--------|--------|--------|
| macvrf-vlan10-spine1 | nokia-spine-1 | 192.168.10.1/24 | Ready |
| macvrf-vlan10-spine2 | nokia-spine-2 | 192.168.10.2/24 | Ready |
| macvrf-vlan10-leaf1 | nokia-leaf-1 | 192.168.10.11/24 | Ready |
| macvrf-vlan10-leaf2 | nokia-leaf-2 | 192.168.10.12/24 | Ready |

---

## VLAN 10 Connectivity Matrix

```
           spine-1    spine-2    leaf-1     leaf-2
           .10.1      .10.2      .10.11     .10.12
spine-1    -          3.14ms     3.78ms     4.79ms
spine-2    3.14ms     -          3.43ms     4.57ms
leaf-1     3.78ms     3.43ms     -          4.44ms
leaf-2     4.79ms     4.57ms     4.44ms     -

Status: FULL MESH CONNECTIVITY
```

---

## Recent Changes

### 2026-01-15 (Session 3): Debug Pod + gNMI Subscribe Monitoring

**Summary:**
- Implemented network debug pod for interactive troubleshooting
- Added gNMI Subscribe script for streaming telemetry
- Heartbeat logging visible in ArgoCD UI
- Updated ArgoCD to sync debug folder

**Resources Added:**

| Resource | Type | Purpose |
|----------|------|---------|
| network-debug | Pod | Interactive shell, SSH to switches, ping tests |
| network-debug-scripts | ConfigMap | Helper scripts for Nokia/Arista SSH |

**Debug Pod Features:**
- Image: nicolaka/netshoot (SSH, ping, tcpdump, curl)
- Heartbeat logs every 60s with ping latency to all switches
- Visible in ArgoCD UI: Applications > sdc-network-configs > network-debug > Logs

**gNMI Subscribe Script:**
```bash
# Stream interface statistics
./scripts/gnmi-subscribe-logs.sh nokia-spine-1 interface

# Stream BGP state
./scripts/gnmi-subscribe-logs.sh nokia-spine-1 bgp --sample-interval 5

# Single query
./scripts/gnmi-subscribe-logs.sh arista-spine-1 system --once
```

**Subscription Types:** system, interface, cpu, memory, bgp, lldp

**Heartbeat Sample Output:**
```
--- Heartbeat 2026-01-15T20:15:20+00:00 ---
Nokia Switches:
  172.40.40.11    OK (1.54ms)
  172.40.40.12    OK (2.55ms)
  172.40.40.21    OK (2.60ms)
  172.40.40.22    OK (1.44ms)
Arista Switches:
  172.20.20.11    OK (0.284ms)
  172.20.20.21    OK (0.250ms)
  172.20.20.22    OK (0.230ms)
```

**Files Created:**
- `clusters/kind-arista-lab/debug/network-debug-pod.yaml`
- `scripts/gnmi-subscribe-logs.sh`
- `scripts/README.md`

**Commits:**
- `40f39b1` feat(debug): add network debug pod and gNMI subscribe script
- `7a94eb9` fix(argocd): remove include pattern for simpler sync
- `ca20ffe` feat(debug): add heartbeat logging to network-debug pod

---

### 2026-01-15 (Session 2): MAC-VRF Migration + Arista Topology

**Summary:**
- Migrated VLAN 10 from L3 routed to MAC-VRF with IRB (L2 bridged)
- Achieved full mesh ping connectivity between all 4 Nokia switches
- Added topology configs for Arista switches (hostname, interface descriptions)
- Created architecture documentation with topology diagrams

**Technical Details:**

1. **MAC-VRF VLAN 10 Migration**
   - Problem: L3 routed subinterfaces were isolated (no inter-switch connectivity)
   - Solution: Implemented MAC-VRF with IRB interfaces
   - Config structure:
     - Bridged subinterfaces (type: bridged) in mac-vrf network-instance
     - IRB interfaces (irb0.10) for L3 gateway
     - IRB in both mac-vrf and default network-instance
   - Result: Full L2 bridging with L3 routing capability

2. **Arista Topology Configs**
   - Added hostname configuration via SDC
   - Interface descriptions with topology information
   - Labels: `topology: spine-leaf`, `role: spine/leaf`

3. **Documentation**
   - Created `docs/diagrams/topology-arista-nokia.md`
   - Comprehensive architecture diagram
   - BGP underlay peering table
   - MAC-VRF VLAN 10 bridge domain visualization

**Files Created/Modified:**
- `clusters/kind-arista-lab/configs/vlans/macvrf-vlan10-*.yaml` (4 files)
- `clusters/kind-arista-lab/configs/interfaces/arista-*-topology.yaml` (3 files)
- `docs/diagrams/topology-arista-nokia.md`

**Commits:**
- `8009374` feat(sdc): migrate VLAN 10 from L3 routed to MAC-VRF with IRB
- `3222118` feat(arista): add topology configs and architecture diagram

---

### 2026-01-15 (Session 1): GitOps Implementation + BGP Migration

**Summary:**
- Implemented full GitOps workflow: GitHub -> ArgoCD -> SDC -> gNMI -> Switches
- Resolved Nokia SR Linux constraint: `vlan-tagging` incompatible with `subinterface 0`
- Successfully migrated BGP link on spine-2/leaf-1 from untagged to VLAN-tagged

**Technical Details:**

1. **ArgoCD Setup**
   - Installed via manifests on KinD cluster
   - Exposed via NodePort (30443) with optional proxy forwarding
   - Automated sync with prune enabled

2. **BGP Migration (spine-2 <-> leaf-1)**
   - Problem: `ethernet-1/1.0` had BGP P2P link (10.0.3.0/31)
   - Nokia constraint: Cannot enable `vlan-tagging` with `subinterface 0`
   - Solution: Atomic migration to `subinterface 1` with VLAN tag 1
   - Result: Both BGP link AND VLAN 10 now work on same interface

3. **GitOps Workflow Validated**
   - Config changes via Git commits
   - ArgoCD auto-sync applies to SDC
   - SDC translates to gNMI SET
   - Switches updated automatically

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     GitOps Pipeline                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  GitHub ──────► ArgoCD ──────► SDC ──────► Switches            │
│  (Source)      (Sync)        (gNMI)      (Config)              │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Lab Topology

```
        ARISTA LAB (172.20.20.0/24)          NOKIA LAB (172.40.40.0/24)

              SPINE-1                        SPINE-1      SPINE-2
             (.20.11)                        (.40.11)     (.40.12)
              /    \                            |     \  /    |
             /      \                           |      \/     |
          LEAF-1  LEAF-2                     LEAF-1 ───────LEAF-2
         (.20.21) (.20.22)                  (.40.21)      (.40.22)
```

### Targets

| Target | Provider | Address | gNMI Port |
|--------|----------|---------|-----------|
| spine-1-arista | eos.arista.sdcio.dev | 172.20.20.11 | 6030 |
| leaf-1-arista | eos.arista.sdcio.dev | 172.20.20.21 | 6030 |
| leaf-2-arista | eos.arista.sdcio.dev | 172.20.20.22 | 6030 |
| nokia-spine-1 | srl.nokia.sdcio.dev | 172.40.40.11 | 57401 |
| nokia-spine-2 | srl.nokia.sdcio.dev | 172.40.40.12 | 57401 |
| nokia-leaf-1 | srl.nokia.sdcio.dev | 172.40.40.21 | 57401 |
| nokia-leaf-2 | srl.nokia.sdcio.dev | 172.40.40.22 | 57401 |

---

## BGP Underlay (Nokia)

| Peering | Local AS | Remote AS | Local IP | Remote IP | Status |
|---------|----------|-----------|----------|-----------|--------|
| spine-1 <-> leaf-1 | 65000 | 65001 | 10.0.1.0 | 10.0.1.1 | ESTABLISHED |
| spine-2 <-> leaf-1 | 65000 | 65001 | 10.0.3.0 | 10.0.3.1 | ESTABLISHED |
| spine-2 <-> leaf-2 | 65000 | 65002 | 10.0.4.0 | 10.0.4.1 | ESTABLISHED |

---

## Access Information

| Service | URL/Command | Credentials |
|---------|-------------|-------------|
| ArgoCD UI | https://<server-ip>:30443 | See local credentials |
| Server SSH | Contact admin for access | - |
| GitHub Repo | https://github.com/reinaldosaraiva/netops-gitops | - |
| Arista SSH | ssh admin@172.20.20.x | admin |
| Nokia SSH | ssh admin@172.40.40.x | admin123 |

---

## Commands Reference

```bash
# ArgoCD
argocd login 172.18.0.4:30443 --insecure -u admin -p JNtpkYEjCif1WrP4
argocd app sync sdc-network-configs --prune

# SDC
kubectl get targets -n sdc
kubectl get configs -n sdc
kubectl describe config <name> -n sdc

# Debug Pod - Interactive Shell
kubectl exec -it network-debug -n sdc -- bash

# Debug Pod - SSH to Nokia
kubectl exec -it network-debug -n sdc -- ssh -o StrictHostKeyChecking=no admin@172.40.40.11

# Debug Pod - View heartbeat logs
kubectl logs network-debug -n sdc -f

# gNMI Subscribe - Interface streaming
gnmic -a 172.40.40.11:57401 --insecure -u admin -p admin123 \
  subscribe --path /interface[name=*]/statistics \
  --stream-mode sample --sample-interval 5s

# gNMI - Nokia (single query)
gnmic -a 172.40.40.11:57401 --insecure -u admin -p admin123 \
  get --path /network-instance[name=vlan10] --type config

# gNMI - Arista (single query)
gnmic -a 172.20.20.11:6030 --insecure -u admin -p admin \
  get --path /interfaces/interface[name=Ethernet1]/config

# Ping Test (from Nokia switch)
ssh admin@172.40.40.11
ping 192.168.10.2 network-instance default -c 3
```

---

## Lessons Learned

1. **Nokia SR Linux vlan-tagging constraint**: Cannot have `vlan-tagging: true` when `subinterface 0` exists
2. **MAC-VRF vs L3 Routed**: Use MAC-VRF with IRB for L2 bridged domains; L3 routed creates isolated segments
3. **SDC target labels are immutable**: Must delete and recreate config to change target
4. **ArgoCD prune option**: Essential for GitOps (removes configs deleted from Git)
5. **IRB interface naming**: Nokia uses `irb0.N` format; N matches subinterface index

---

## Documentation

| Document | Description |
|----------|-------------|
| `docs/diagrams/topology-arista-nokia.md` | Complete architecture and topology diagram |
| `docs/SESSION_2026-01-15_GITOPS_SETUP.md` | Session 1 detailed notes |
| `scripts/README.md` | Debug pod and gNMI subscribe usage guide |

---

*Generated: 2026-01-15 20:20 UTC*
