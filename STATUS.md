# NetOps GitOps Status

**Last Updated:** 2026-01-15 21:10 UTC
**Status:** OPERATIONAL

---

## Overview

| Metric | Value |
|--------|-------|
| Resources Managed via GitOps | 26 |
| SDC Configs (Ready) | 14/14 |
| SDC Targets (Ready) | 7/7 |
| Monitoring Stack | Telegraf + InfluxDB + Grafana |
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

### Nokia SR Linux (Native YANG) - BGP Underlay

| Config | Target | AS | Router-ID | Status |
|--------|--------|----|-----------| -------|
| bgp-spine1 | nokia-spine-1 | 65000 | 10.255.0.1 | Ready |
| bgp-spine2 | nokia-spine-2 | 65000 | 10.255.0.2 | Ready |
| bgp-leaf1 | nokia-leaf-1 | 65001 | 10.255.0.11 | Ready |
| bgp-leaf2 | nokia-leaf-2 | 65002 | 10.255.0.12 | Ready |

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

### 2026-01-15 (Session 5): Grafana Dashboard Improvements - BGP Status Visualization

**Summary:**
- Improved Grafana BGP Session States visualization
- Fixed Flux query issues with InfluxDB datasource
- Implemented semaphore-style colored tables for BGP status
- External access to Grafana via socat proxy (same pattern as ArgoCD)

**Grafana Dashboard Panels:**

| Panel | Type | Data Source | Description |
|-------|------|-------------|-------------|
| Interface Traffic (Nokia) | timeseries | InfluxDB | in/out octets as bps |
| Interface Traffic (Arista) | timeseries | InfluxDB | in/out octets as bps |
| Nokia Spines BGP | table | InfluxDB | BGP status spine-1, spine-2 |
| Nokia Leafs BGP | table | InfluxDB | BGP status leaf-1, leaf-2 |
| CPU Utilization | timeseries | InfluxDB | System CPU % |
| Memory Usage | timeseries | InfluxDB | System memory bytes |

**BGP Status Tables (Semaphore Style):**

```
┌──────────────────────────────┐  ┌──────────────────────────────┐
│     Nokia Spines BGP         │  │      Nokia Leafs BGP         │
├──────────┬────────┬──────────┤  ├──────────┬────────┬──────────┤
│  Switch  │  Peer  │  Status  │  │  Switch  │  Peer  │  Status  │
├──────────┼────────┼──────────┤  ├──────────┼────────┼──────────┤
│172.40.40.│10.0.x.x│ UP/DOWN  │  │172.40.40.│10.0.x.x│ UP/DOWN  │
│  11/12   │        │ (colored)│  │  21/22   │        │ (colored)│
└──────────┴────────┴──────────┘  └──────────┴────────┴──────────┘

Status Colors:
- Green (UP): established, active
- Red (DOWN): idle
- Yellow (CONNECTING): connect
```

**Technical Fixes Applied:**

| Issue | Root Cause | Solution |
|-------|------------|----------|
| Table columns concatenated | Flux returns separate tables per tag | Added `group()` to merge |
| Stat panel "No data" | String values incompatible with stat | Changed to table with color-background |
| Datasource UID invalid | Template variable `${DS_INFLUXDB}` | Replaced with actual UID |
| BGP query empty (5min) | on_change subscription, old data | Extended range to 1h |

**Flux Query Pattern (Working):**

```flux
from(bucket: "network-telemetry")
  |> range(start: -1h)
  |> filter(fn: (r) => r["_measurement"] == "bgp_neighbor")
  |> filter(fn: (r) => r["_field"] == "session_state")
  |> filter(fn: (r) => r["source"] =~ /172\.40\.40\.(11|12)/)  // Spines
  |> last()
  |> group()  // CRITICAL: merge tables
  |> keep(columns: ["source", "peer_address", "_value"])
  |> rename(columns: {source: "Switch", peer_address: "Peer", _value: "Status"})
```

**External Access (socat proxy):**

```bash
# Grafana proxy service (same pattern as ArgoCD)
# File: /etc/systemd/system/grafana-proxy.service
[Service]
ExecStart=/usr/bin/socat TCP-LISTEN:30300,bind=0.0.0.0,fork,reuseaddr TCP:172.18.0.4:30300

# Access
http://10.251.12.84:30300 (admin/netops-grafana)
```

**Commits:**
- `fae217a` fix(grafana): format BGP table with clean column names
- `f42b03d` fix(grafana): use keep+rename for proper BGP table columns
- `109562b` fix(grafana): add group() to merge BGP table rows
- `d80f569` feat(grafana): semaphore-style BGP status panels
- `54fdcb5` fix(grafana): simplify BGP stat queries with values:true
- `27bed9b` fix(grafana): use tables with colored backgrounds for BGP status

**Lessons Learned:**

1. **Flux `group()` is essential**: Without it, each tag combination creates separate table
2. **Stat panels + strings = problematic**: Use table with color-background for string states
3. **on_change subscriptions**: Data only sent when state changes, use longer time ranges
4. **Provisioned dashboards**: Cannot use template variables like `${DS_INFLUXDB}`

---

### 2026-01-15 (Session 4): BGP Configs + Monitoring Stack (Telegraf/InfluxDB/Grafana)

**Summary:**
- Added BGP configs for all 4 Nokia switches via GitOps
- Deployed full monitoring stack: Telegraf, InfluxDB, Grafana
- Telegraf collecting gNMI telemetry from all 7 switches
- Grafana dashboard available at NodePort 30300

**BGP Configs Created:**

| Config | AS | Peers | Status |
|--------|----|----- -|--------|
| bgp-spine1 | 65000 | leaf-1 (10.0.1.1) | Ready |
| bgp-spine2 | 65000 | leaf-1 (10.0.3.1), leaf-2 (10.0.4.1) | Ready |
| bgp-leaf1 | 65001 | spine-1 (10.0.1.0), spine-2 (10.0.3.0) | Ready |
| bgp-leaf2 | 65002 | spine-2 (10.0.4.0) | Ready |

**Monitoring Stack:**

| Component | Image | Status | Access |
|-----------|-------|--------|--------|
| Telegraf | telegraf:1.29-alpine | Running | gNMI collector |
| InfluxDB | influxdb:2.7-alpine | Running | ClusterIP:8086 |
| Grafana | grafana/grafana:10.3.1 | Running | NodePort:30300 |

**Telegraf gNMI Subscriptions:**

| Target | Subscriptions |
|--------|---------------|
| Nokia (4 switches) | interface_stats, interface_oper_state, bgp_neighbor, system_cpu, system_memory |
| Arista (3 switches) | arista_interface_counters, arista_interface_state, arista_system |

**Access Credentials:**
- Grafana: http://<server-ip>:30300 (admin/netops-grafana)
- InfluxDB: org=netops, bucket=network-telemetry, token=netops-token-secret

**Files Created:**
- `clusters/kind-arista-lab/configs/routing/bgp-*.yaml` (4 files)
- `clusters/kind-arista-lab/monitoring/telegraf.yaml`
- `clusters/kind-arista-lab/monitoring/influxdb.yaml`
- `clusters/kind-arista-lab/monitoring/grafana.yaml`

**Commits:**
- `0d1e1b3` feat(sdc): add BGP configs and monitoring stack (Telegraf/InfluxDB/Grafana)
- `a4e19dc` fix(bgp): use array for export-policy (Nokia SR Linux YANG)
- `8bc1271` fix(telegraf): correct gNMI TLS config syntax

---

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
6. **Nokia export-policy is array**: YANG model requires `export-policy: [policy-name]` not string
7. **Telegraf gNMI TLS**: Use `insecure_skip_verify = true` directly, not nested `[inputs.gnmi.tls]`
8. **Flux group() for tables**: Essential to merge separate Flux tables into single Grafana table
9. **Grafana stat + strings**: Use table with color-background instead of stat panel for string values
10. **on_change subscriptions**: Data sent only on state change; use longer time ranges (1h+)

---

## Next Steps (Roadmap)

### Immediate (Next Session)

| Task | Priority | Description |
|------|----------|-------------|
| Arista BGP Config | High | Add BGP configs for Arista switches (similar to Nokia) |
| Dashboard Improvements | Medium | Add Arista interface status panel, LLDP neighbors |
| Alerting | Medium | Configure Grafana alerts for BGP down, interface errors |

### Short Term

| Task | Priority | Description |
|------|----------|-------------|
| OSPF Configs | High | Add OSPF routing for Nokia underlay |
| EVPN-VXLAN | High | Extend MAC-VRF to EVPN for multi-site L2 |
| Prometheus Integration | Medium | Add Prometheus for alerting (AlertManager) |
| Network Topology Panel | Low | Grafana topology visualization plugin |

### Long Term

| Task | Priority | Description |
|------|----------|-------------|
| CI/CD Pipeline | Medium | GitHub Actions for config validation before merge |
| Config Backup | Medium | Periodic config backup to Git (diff detection) |
| Capacity Planning | Low | Historical data analysis dashboards |
| Multi-Cluster | Low | Extend GitOps to multiple SDC clusters |

### Technical Debt

| Item | Description |
|------|-------------|
| Hardcoded IPs | Move switch IPs to ConfigMap or Helm values |
| Datasource UID | Use Grafana API to auto-discover UID |
| Dashboard as Code | Consider Grafonnet for dashboard generation |

---

## Documentation

| Document | Description |
|----------|-------------|
| `docs/diagrams/topology-arista-nokia.md` | Complete architecture and topology diagram |
| `docs/SESSION_2026-01-15_GITOPS_SETUP.md` | Session 1 detailed notes |
| `scripts/README.md` | Debug pod and gNMI subscribe usage guide |
| `STATUS.md` | This file - current status and roadmap |

---

## Quick Access

| Service | URL | Credentials |
|---------|-----|-------------|
| ArgoCD | https://10.251.12.84:30443 | admin / JNtpkYEjCif1WrP4 |
| Grafana | http://10.251.12.84:30300 | admin / netops-grafana |
| GitHub | https://github.com/reinaldosaraiva/netops-gitops | - |

| Switch SSH | Address | Credentials |
|------------|---------|-------------|
| Nokia | 172.40.40.x | admin / admin123 |
| Arista | 172.20.20.x | admin / admin |

---

*Generated: 2026-01-15 21:10 UTC*
