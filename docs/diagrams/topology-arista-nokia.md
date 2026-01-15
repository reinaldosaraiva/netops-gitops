# Topologia Data Center - Arista cEOS + Nokia SR Linux

## Visão Geral da Arquitetura

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                        DATA CENTER FABRIC TOPOLOGY                            │
│                     GitOps + SDC/gNMI Configuration                          │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│    ┌─────────────────────────────┐    ┌─────────────────────────────┐        │
│    │     ARISTA cEOS LAB         │    │      NOKIA SR LINUX LAB     │        │
│    │     172.20.20.0/24          │    │      172.40.40.0/24         │        │
│    └─────────────────────────────┘    └─────────────────────────────┘        │
│                                                                              │
│                           ┌───────────┐                                      │
│                           │  ArgoCD   │                                      │
│                           │  GitOps   │                                      │
│                           └─────┬─────┘                                      │
│                                 │                                            │
│                           ┌─────▼─────┐                                      │
│                           │    SDC    │                                      │
│                           │ Operator  │                                      │
│                           └─────┬─────┘                                      │
│                                 │ gNMI                                       │
│               ┌─────────────────┼─────────────────┐                          │
│               │                 │                 │                          │
│               ▼                 ▼                 ▼                          │
│          ┌────────┐       ┌────────┐        ┌────────┐                       │
│          │ Arista │       │ Arista │        │ Nokia  │                       │
│          │ SPINE  │       │ LEAFs  │        │ Fabric │                       │
│          └────────┘       └────────┘        └────────┘                       │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

## Arista cEOS Lab (172.20.20.0/24)

```
                    ┌─────────────────────────┐
                    │       SPINE-1           │
                    │    172.20.20.11         │
                    │    cEOS 4.34.1F         │
                    │                         │
                    │  Eth1        Eth2       │
                    └───┬──────────┬──────────┘
                        │          │
           ┌────────────┘          └────────────┐
           │                                    │
    ┌──────▼──────┐                      ┌──────▼──────┐
    │   LEAF-1    │                      │   LEAF-2    │
    │172.20.20.21 │                      │172.20.20.22 │
    │cEOS 4.34.1F │                      │cEOS 4.34.1F │
    │             │                      │             │
    │    Eth1     │                      │    Eth1     │
    └─────────────┘                      └─────────────┘
```

### Dispositivos Arista

| Device | Management IP | Role | OS Version | Interfaces |
|--------|---------------|------|------------|------------|
| spine-1-arista | 172.20.20.11 | L3 Spine | cEOS 4.34.1F | Eth1→LEAF-1, Eth2→LEAF-2 |
| leaf-1-arista | 172.20.20.21 | L2 Leaf | cEOS 4.34.1F | Eth1→SPINE-1 |
| leaf-2-arista | 172.20.20.22 | L2 Leaf | cEOS 4.34.1F | Eth1→SPINE-1 |

### Conexões Físicas Arista

| Source | Interface | Destination | Interface | Link Type |
|--------|-----------|-------------|-----------|-----------|
| spine-1-arista | Ethernet1 | leaf-1-arista | Ethernet1 | Uplink |
| spine-1-arista | Ethernet2 | leaf-2-arista | Ethernet1 | Uplink |

---

## Nokia SR Linux Lab (172.40.40.0/24)

```
           ┌─────────────────┐              ┌─────────────────┐
           │    SPINE-1      │              │    SPINE-2      │
           │  172.40.40.11   │              │  172.40.40.12   │
           │  SR Linux 24.10 │              │  SR Linux 24.10 │
           │                 │              │                 │
           │ eth-1/1  (BGP)  │              │ eth-1/1  eth-1/2│
           └────┬────────────┘              └────┬──────┬─────┘
                │                                │      │
                │ 10.0.1.0/31                    │      │ 10.0.4.0/31
                │                          10.0.3.0/31  │
     ┌──────────▼────────────┐              ┌────▼──────▼─────┐
     │       LEAF-1          │              │      LEAF-2     │
     │    172.40.40.21       │              │   172.40.40.22  │
     │    SR Linux 24.10     │              │   SR Linux 24.10│
     │                       │              │                 │
     │ eth-1/49     eth-1/50 │              │     eth-1/50    │
     └───────────────────────┘              └─────────────────┘
```

### Dispositivos Nokia

| Device | Management IP | gNMI Port | Role | IRB VLAN 10 |
|--------|---------------|-----------|------|-------------|
| nokia-spine-1 | 172.40.40.11 | 57401 | L3 Spine + IRB Gateway | 192.168.10.1/24 |
| nokia-spine-2 | 172.40.40.12 | 57401 | L3 Spine + IRB Gateway | 192.168.10.2/24 |
| nokia-leaf-1 | 172.40.40.21 | 57401 | L2/L3 Leaf | 192.168.10.11/24 |
| nokia-leaf-2 | 172.40.40.22 | 57401 | L2/L3 Leaf | 192.168.10.12/24 |

### BGP Underlay Nokia

| Peering | Local AS | Remote AS | Local IP | Remote IP | Status |
|---------|----------|-----------|----------|-----------|--------|
| spine-1 ↔ leaf-1 | 65000 | 65001 | 10.0.1.0 | 10.0.1.1 | ESTABLISHED |
| spine-2 ↔ leaf-1 | 65000 | 65001 | 10.0.3.0 | 10.0.3.1 | ESTABLISHED |
| spine-2 ↔ leaf-2 | 65000 | 65002 | 10.0.4.0 | 10.0.4.1 | ESTABLISHED |

### MAC-VRF VLAN 10 Nokia

```
┌─────────────────────────────────────────────────────────────────┐
│                    MAC-VRF "vlan10"                             │
│                  (L2 Bridged Domain)                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  spine-1                spine-2                                 │
│  ┌─────────┐           ┌─────────┐                              │
│  │ irb0.10 │           │ irb0.10 │                              │
│  │.10.1/24 │           │.10.2/24 │                              │
│  │         │           │         │                              │
│  │eth-1/1  │           │eth-1/1  │                              │
│  │  .10    │           │  .10    │eth-1/2.10                    │
│  └────┬────┘           └────┬────┴────┐                         │
│       │                     │         │                         │
│       │ VLAN 10 tagged      │         │ VLAN 10 tagged          │
│       │                     │         │                         │
│  ┌────▼────┐           ┌────▼─────────▼─┐                       │
│  │leaf-1   │           │     leaf-2     │                       │
│  │ irb0.10 │           │     irb0.10    │                       │
│  │.10.11/24│           │    .10.12/24   │                       │
│  │         │           │                │                       │
│  │eth-1/49 │eth-1/50   │    eth-1/50    │                       │
│  │  .10    │  .10      │      .10       │                       │
│  └─────────┘           └────────────────┘                       │
│                                                                 │
│  Conectividade: FULL MESH via L2 bridging + IRB routing         │
└─────────────────────────────────────────────────────────────────┘
```

---

## GitOps Pipeline

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   GitHub    │────►│   ArgoCD    │────►│     SDC     │────►│  Switches   │
│   Repo      │     │   Sync      │     │  Operator   │     │  (gNMI)     │
└─────────────┘     └─────────────┘     └─────────────┘     └─────────────┘
     │                    │                   │                    │
     │  netops-gitops/    │  Watch &          │  Config            │  Apply
     │  configs/          │  Apply            │  CRDs              │  Config
     │                    │                   │                    │
     ▼                    ▼                   ▼                    ▼
  YAML Files         K8s Configs         gNMI SetRequest     Running Config
```

---

## SDC Configs Status

| Config | Target | Status | Priority |
|--------|--------|--------|----------|
| arista-spine1-interface-desc | spine-1-arista | Ready | 10 |
| arista-leaf1-interface-desc | leaf-1-arista | Ready | 10 |
| arista-leaf2-interface-desc | leaf-2-arista | Ready | 10 |
| macvrf-vlan10-spine1 | nokia-spine-1 | Ready | 30 |
| macvrf-vlan10-spine2 | nokia-spine-2 | Ready | 30 |
| macvrf-vlan10-leaf1 | nokia-leaf-1 | Ready | 30 |
| macvrf-vlan10-leaf2 | nokia-leaf-2 | Ready | 30 |

---

## Acesso aos Dispositivos

### Arista cEOS
```bash
# SSH
ssh admin@172.20.20.11  # spine-1
ssh admin@172.20.20.21  # leaf-1
ssh admin@172.20.20.22  # leaf-2
# Password: admin
```

### Nokia SR Linux
```bash
# SSH
ssh admin@172.40.40.11  # nokia-spine-1
ssh admin@172.40.40.12  # nokia-spine-2
ssh admin@172.40.40.21  # nokia-leaf-1
ssh admin@172.40.40.22  # nokia-leaf-2
# Password: admin123

# gNMI
gnmic -a 172.40.40.11:57401 -u admin -p admin123 --insecure get --path /
```

---

*Gerado: 2026-01-15 | Lab: kind-arista-lab*
