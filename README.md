# NetOps GitOps Repository

Repository for SDC/Kubenet network configurations managed via ArgoCD.

## Architecture

```
GitHub (Source) → ArgoCD (Sync) → SDC (Delivery) → gNMI → Switches
```

## Quick Start

### 1. Clone and Edit
```bash
git clone https://github.com/reinaldosaraiva/netops-gitops.git
cd netops-gitops

# Edit a config
vim clusters/kind-arista-lab/configs/interfaces/arista-leaf1-interface-desc.yaml

# Commit and push
git add . && git commit -m "feat: update config" && git push
```

### 2. ArgoCD syncs automatically (or force sync)
```bash
argocd app sync sdc-network-configs
```

### 3. Verify on switch
```bash
gnmic -a 172.20.20.21:6030 --insecure -u admin -p admin \
  get --path /interfaces/interface[name=Ethernet1]/config
```

## Structure

```
clusters/
└── kind-arista-lab/
    └── configs/
        ├── interfaces/    # Interface descriptions
        ├── vlans/         # VLAN configurations
        └── routing/       # BGP/OSPF configs
```

## Targets

| Target | Provider | Address | Credentials |
|--------|----------|---------|-------------|
| spine-1-arista | eos.arista.sdcio.dev | 172.20.20.11 | admin/admin |
| leaf-1-arista | eos.arista.sdcio.dev | 172.20.20.21 | admin/admin |
| leaf-2-arista | eos.arista.sdcio.dev | 172.20.20.22 | admin/admin |
| nokia-spine-1 | srl.nokia.sdcio.dev | 172.40.40.11 | admin/admin123 |
| nokia-spine-2 | srl.nokia.sdcio.dev | 172.40.40.12 | admin/admin123 |
| nokia-leaf-1 | srl.nokia.sdcio.dev | 172.40.40.21 | admin/admin123 |
| nokia-leaf-2 | srl.nokia.sdcio.dev | 172.40.40.22 | admin/admin123 |

## Access

| Service | URL | Credentials |
|---------|-----|-------------|
| ArgoCD UI | https://10.251.12.84:30443 | admin / JNtpkYEjCif1WrP4 |
| Server SSH | ssh failsafe@10.251.12.84 | Xj497scHQGaEiRv |

## ConfigSet Examples

### Arista (OpenConfig)
```yaml
apiVersion: config.sdcio.dev/v1alpha1
kind: Config
metadata:
  name: arista-interface-desc
  namespace: sdc
  labels:
    config.sdcio.dev/targetName: leaf-1-arista
    config.sdcio.dev/targetNamespace: sdc
spec:
  priority: 10
  config:
  - path: /
    value:
      interfaces:
        interface:
        - name: Ethernet1
          config:
            description: "SDC Managed"
```

### Nokia SR Linux (Native)
```yaml
apiVersion: config.sdcio.dev/v1alpha1
kind: Config
metadata:
  name: nokia-vlan10
  namespace: sdc
  labels:
    config.sdcio.dev/targetName: nokia-spine-1
    config.sdcio.dev/targetNamespace: sdc
spec:
  priority: 20
  config:
  - path: /
    value:
      interface:
      - name: ethernet-1/1
        admin-state: enable
        vlan-tagging: true
        subinterface:
        - index: 10
          admin-state: enable
          type: routed
          vlan:
            encap:
              single-tagged:
                vlan-id: 10
```

## Commands

```bash
# ArgoCD
argocd login 172.18.0.4:30443 --insecure -u admin -p JNtpkYEjCif1WrP4
argocd app list
argocd app get sdc-network-configs
argocd app sync sdc-network-configs

# SDC
kubectl get targets -n sdc
kubectl get configs -n sdc
kubectl describe config <name> -n sdc

# gNMI
gnmic -a <ip>:<port> --insecure -u <user> -p <pass> get --path <yang-path>
```

## Documentation

- [Session 2026-01-15: GitOps Setup](docs/SESSION_2026-01-15_GITOPS_SETUP.md)

## Contributing

1. Create feature branch
2. Make changes
3. Submit PR
4. ArgoCD syncs after merge
