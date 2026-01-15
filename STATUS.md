# NetOps GitOps Status

**Last Updated:** 2026-01-15 18:20 UTC
**Status:** OPERATIONAL

---

## Overview

| Metric | Value |
|--------|-------|
| Configs Managed via GitOps | 11 |
| SDC Targets (Ready) | 7/7 |
| ArgoCD Sync Status | Synced |
| GitHub Repo | https://github.com/reinaldosaraiva/netops-gitops |

---

## Config Status Summary

### Arista (OpenConfig YANG)

| Config | Target | Status |
|--------|--------|--------|
| arista-spine1-interface-desc | spine-1-arista | Ready |
| arista-leaf1-interface-desc | leaf-1-arista | Ready |
| arista-leaf2-interface-desc | leaf-2-arista | Ready |

### Nokia SR Linux (Native YANG)

| Config | Target | Status |
|--------|--------|--------|
| vlan10-subinterface-spine1 | nokia-spine-1 | Ready |
| vlan10-subinterface-spine2 | nokia-spine-2 | Ready |
| vlan10-subinterface-leaf1 | nokia-leaf-1 | Ready |
| vlan10-subinterface-leaf2 | nokia-leaf-2 | Ready |
| svi-vlan10-spine1 | spine-1 | Ready |
| svi-vlan10-spine2 | spine-2 | Ready |
| svi-vlan10-leaf1 | leaf-1 | Ready |
| svi-vlan10-leaf2 | leaf-2 | Ready |

---

## Recent Changes

### 2026-01-15: GitOps Implementation + BGP Migration

**Summary:**
- Implemented full GitOps workflow: GitHub -> ArgoCD -> SDC -> gNMI -> Switches
- Resolved Nokia SR Linux constraint: `vlan-tagging` incompatible with `subinterface 0`
- Successfully migrated BGP link on spine-2/leaf-1 from untagged to VLAN-tagged

**Technical Details:**

1. **ArgoCD Setup**
   - Installed via manifests on KinD cluster
   - Exposed via socat proxy (10.251.12.84:30443 -> 172.18.0.4:30443)
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

**Files Modified:**
- `clusters/kind-arista-lab/configs/vlans/nokia-vlan10-spine2.yaml`
- `docs/SESSION_2026-01-15_GITOPS_SETUP.md`

---

## Architecture

```
GitHub (Source) -> ArgoCD (Sync) -> SDC (Delivery) -> gNMI -> Switches
```

### Targets

| Target | Provider | Address | Credentials |
|--------|----------|---------|-------------|
| spine-1-arista | eos.arista.sdcio.dev | 172.20.20.11 | admin/admin |
| leaf-1-arista | eos.arista.sdcio.dev | 172.20.20.21 | admin/admin |
| leaf-2-arista | eos.arista.sdcio.dev | 172.20.20.22 | admin/admin |
| nokia-spine-1 | srl.nokia.sdcio.dev | 172.40.40.11 | admin/admin123 |
| nokia-spine-2 | srl.nokia.sdcio.dev | 172.40.40.12 | admin/admin123 |
| nokia-leaf-1 | srl.nokia.sdcio.dev | 172.40.40.21 | admin/admin123 |
| nokia-leaf-2 | srl.nokia.sdcio.dev | 172.40.40.22 | admin/admin123 |

---

## Access Information

| Service | URL/Command | Credentials |
|---------|-------------|-------------|
| ArgoCD UI | https://10.251.12.84:30443 | admin / JNtpkYEjCif1WrP4 |
| Server SSH | ssh failsafe@10.251.12.84 | Xj497scHQGaEiRv |
| GitHub Repo | https://github.com/reinaldosaraiva/netops-gitops | - |

---

## Commands Reference

```bash
# ArgoCD
argocd login 172.18.0.4:30443 --insecure -u admin -p JNtpkYEjCif1WrP4
argocd app sync sdc-network-configs

# SDC
kubectl get targets -n sdc
kubectl get configs -n sdc
kubectl describe config <name> -n sdc

# gNMI (Nokia example)
gnmic -a 172.40.40.12:57401 --insecure -u admin -p admin123 \
  get --path /interface[name=ethernet-1/1] --encoding json_ietf
```

---

## Lessons Learned

1. **Nokia SR Linux vlan-tagging constraint**: Cannot have `vlan-tagging: true` when `subinterface 0` exists
2. **SDC target labels are immutable**: Must delete and recreate config to change target
3. **ArgoCD prune option**: Essential for GitOps (removes configs deleted from Git)
4. **KinD networking**: Requires port forwarding for external access (socat/iptables)

---

**Documentation:** See `docs/SESSION_2026-01-15_GITOPS_SETUP.md` for detailed session notes.
