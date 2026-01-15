# NetOps GitOps Repository

Repository for SDC/Kubenet network configurations managed via ArgoCD.

## Structure

```
clusters/
└── kind-arista-lab/
    ├── targets/      # SDC Target definitions
    └── configs/      # ConfigSets (interface, vlan, routing)
```

## Access

- **ArgoCD**: https://10.251.12.84:30443
- **Credentials**: admin / JNtpkYEjCif1WrP4

## Targets

| Target | Provider | Address |
|--------|----------|---------|
| spine-1-arista | eos.arista.sdcio.dev | 172.20.20.11 |
| leaf-1-arista | eos.arista.sdcio.dev | 172.20.20.21 |
| leaf-2-arista | eos.arista.sdcio.dev | 172.20.20.22 |
| nokia-spine-1 | srl.nokia.sdcio.dev | 172.40.40.11 |
| nokia-spine-2 | srl.nokia.sdcio.dev | 172.40.40.12 |
| nokia-leaf-1 | srl.nokia.sdcio.dev | 172.40.40.21 |
| nokia-leaf-2 | srl.nokia.sdcio.dev | 172.40.40.22 |

