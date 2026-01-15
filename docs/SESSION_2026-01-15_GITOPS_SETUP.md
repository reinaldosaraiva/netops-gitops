# Session 2026-01-15: NetOps GitOps Setup

**Data:** 2026-01-15
**Objetivo:** Implementar GitOps para gerenciamento de configuracoes de rede SDC/Kubenet
**Status:** COMPLETE (100% - todas configs Ready)

---

## Executive Summary

Implementacao bem-sucedida de workflow GitOps para automacao de rede usando:
- **ArgoCD** para continuous delivery de configuracoes
- **SDC (Software Defined Configuration)** para aplicacao via gNMI
- **GitHub** como single source of truth

### Resultados

| Metrica | Valor |
|---------|-------|
| Configs gerenciados via GitOps | 11 |
| Targets SDC operacionais | 7/7 |
| Configs Ready | 11/11 |
| Tempo de setup ArgoCD | ~5 minutos |
| Sync automatico | Habilitado |
| BGP Migration | COMPLETE |

---

## Arquitetura Implementada

```
┌─────────────────────────────────────────────────────────────────┐
│                     NETOPS GITOPS ARCHITECTURE                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────┐     ┌──────────────┐     ┌──────────────┐    │
│  │   GitHub     │────▶│   ArgoCD     │────▶│     SDC      │    │
│  │   (Source)   │     │   (Sync)     │     │  (Delivery)  │    │
│  └──────────────┘     └──────────────┘     └──────────────┘    │
│         │                    │                    │             │
│         │                    │                    │             │
│         ▼                    ▼                    ▼             │
│  ┌──────────────┐     ┌──────────────┐     ┌──────────────┐    │
│  │  ConfigSets  │     │  Kubernetes  │     │   gNMI SET   │    │
│  │   (YAML)     │     │   (CRDs)     │     │  (Protocol)  │    │
│  └──────────────┘     └──────────────┘     └──────────────┘    │
│                                                   │             │
│                                                   ▼             │
│                              ┌─────────────────────────────┐   │
│                              │      NETWORK SWITCHES       │   │
│                              │  ┌─────────┐  ┌─────────┐   │   │
│                              │  │ Arista  │  │  Nokia  │   │   │
│                              │  │  cEOS   │  │ SR Linux│   │   │
│                              │  └─────────┘  └─────────┘   │   │
│                              └─────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Fluxo de Dados

```
1. Developer edita YAML no GitHub
         │
         ▼
2. ArgoCD detecta mudanca (webhook/polling)
         │
         ▼
3. ArgoCD aplica Config CRD no Kubernetes
         │
         ▼
4. SDC config-server le o CRD
         │
         ▼
5. SDC traduz para gNMI SET request
         │
         ▼
6. gNMI aplica configuracao no switch
         │
         ▼
7. Switch confirma aplicacao
         │
         ▼
8. SDC atualiza status do CRD para Ready
```

---

## Componentes Instalados

### 1. ArgoCD (v2.x)

**Instalacao:**
```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

**Exposicao via socat (persistente):**
```bash
# Systemd service criado
/etc/systemd/system/argocd-proxy.service

# Conteudo:
[Unit]
Description=ArgoCD Port Forward (socat)
After=network.target docker.service

[Service]
Type=simple
ExecStart=/usr/bin/socat TCP-LISTEN:30443,bind=0.0.0.0,fork,reuseaddr TCP:172.18.0.4:30443
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

**Acesso:**
| Campo | Valor |
|-------|-------|
| URL | https://10.251.12.84:30443 |
| Username | admin |
| Password | JNtpkYEjCif1WrP4 |

### 2. Repositorio GitOps

**URL:** https://github.com/reinaldosaraiva/netops-gitops

**Estrutura:**
```
netops-gitops/
├── README.md
├── .gitignore
├── apps/
│   └── sdc-configs.yaml          # ArgoCD Application
├── clusters/
│   └── kind-arista-lab/
│       └── configs/
│           ├── interfaces/       # Interface descriptions
│           │   ├── arista-spine1-interface-desc.yaml
│           │   ├── arista-leaf1-interface-desc.yaml
│           │   └── arista-leaf2-interface-desc.yaml
│           ├── vlans/            # VLAN configurations
│           │   ├── nokia-vlan10-spine1.yaml
│           │   ├── nokia-vlan10-spine2.yaml
│           │   ├── nokia-vlan10-leaf1.yaml
│           │   └── nokia-vlan10-leaf2.yaml
│           └── routing/          # BGP/OSPF configs (futuro)
└── docs/
    └── SESSION_2026-01-15_GITOPS_SETUP.md
```

### 3. ArgoCD Application

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: sdc-network-configs
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/reinaldosaraiva/netops-gitops.git
    targetRevision: main
    path: clusters/kind-arista-lab/configs
    directory:
      recurse: true
  destination:
    server: https://kubernetes.default.svc
    namespace: sdc
  syncPolicy:
    automated:
      prune: true      # Remove recursos deletados do Git
      selfHeal: true   # Corrige drift automaticamente
```

---

## Targets SDC

| Target | Provider | Version | Address | Status |
|--------|----------|---------|---------|--------|
| spine-1-arista | eos.arista.sdcio.dev | 4.34.1F | 172.20.20.11 | READY |
| leaf-1-arista | eos.arista.sdcio.dev | 4.34.1F | 172.20.20.21 | READY |
| leaf-2-arista | eos.arista.sdcio.dev | 4.34.1F | 172.20.20.22 | READY |
| nokia-spine-1 | srl.nokia.sdcio.dev | 24.10.1 | 172.40.40.11 | READY |
| nokia-spine-2 | srl.nokia.sdcio.dev | 24.10.1 | 172.40.40.12 | READY |
| nokia-leaf-1 | srl.nokia.sdcio.dev | 24.10.1 | 172.40.40.21 | READY |
| nokia-leaf-2 | srl.nokia.sdcio.dev | 24.10.1 | 172.40.40.22 | READY |

---

## ConfigSets Gerenciados

### Arista (OpenConfig YANG)

```yaml
# Exemplo: arista-spine1-interface-desc.yaml
apiVersion: config.sdcio.dev/v1alpha1
kind: Config
metadata:
  name: arista-spine1-interface-desc
  namespace: sdc
  labels:
    config.sdcio.dev/targetName: spine-1-arista
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
            description: "SDC Managed - Uplink to LEAF-1"
```

### Nokia SR Linux (Native YANG)

```yaml
# Exemplo: nokia-vlan10-spine1.yaml
apiVersion: config.sdcio.dev/v1alpha1
kind: Config
metadata:
  name: vlan10-subinterface-spine1
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

---

## Problema Resolvido: nokia-spine-2 (BGP Migration)

### Sintoma Original
Config `vlan10-subinterface-spine2` com status `Unrecoverable`

### Causa Raiz
```
Error: vlan tagging true inconsistent with subinterface 0
```

O switch `nokia-spine-2` possuia `subinterface 0` em `ethernet-1/1` com IP 10.0.3.0/31 (usado para BGP P2P). Nokia SR Linux nao permite `vlan-tagging: true` quando existe `subinterface 0` (untagged).

### Solucao Implementada

**Abordagem:** Migracao atomica do BGP de subinterface 0 para subinterface 1 com VLAN tag.

**Passos executados:**

1. **Remover config SDC temporariamente** (evitar conflito de sessao exclusiva)
   ```bash
   kubectl delete config vlan10-subinterface-spine2 -n sdc
   ```

2. **Migrar BGP no leaf-1** (ethernet-1/50)
   ```bash
   gnmic set --delete /interface[name=ethernet-1/50]/subinterface[index=0] \
     --update /interface[name=ethernet-1/50]/vlan-tagging=true \
     --update /interface[name=ethernet-1/50]/subinterface[index=1]/...
   ```

3. **Migrar BGP no spine-2** (ethernet-1/1)
   ```bash
   gnmic set --delete /interface[name=ethernet-1/1]/subinterface[index=0] \
     --update /interface[name=ethernet-1/1]/vlan-tagging=true \
     --update /interface[name=ethernet-1/1]/subinterface[index=1]/...
   ```

4. **Restaurar config via GitOps**
   - Commit novo nokia-vlan10-spine2.yaml
   - ArgoCD sync automatico
   - SDC aplica config com sucesso

### Topologia Apos Migracao

```
                nokia-spine-1
               /      |      \
          e1/1.10  e1/2.0   e1/3.0
         (VLAN10)  (BGP)    (BGP)
              |       |        |
              |   10.0.1.x  10.0.2.x
              |       |        |
          e1/1.10  e1/50.1  e1/1.0
         (VLAN10)  (BGP)    (BGP)
              |       |        |
        nokia-leaf-1  |   nokia-leaf-2
                      |
               nokia-spine-2
                  e1/1.1 ← VLAN tag 1 (BGP)
                  e1/1.10 ← VLAN 10 (SDC)
                 (10.0.3.0/31)
```

### Resultado

| Config | Status Antes | Status Depois |
|--------|--------------|---------------|
| vlan10-subinterface-spine2 | Unrecoverable | Ready |

**Todos os 11 configs agora estao Ready.**

---

## Comandos de Referencia

### Verificar ArgoCD
```bash
# Login
argocd login 172.18.0.4:30443 --insecure --username admin --password JNtpkYEjCif1WrP4

# Listar apps
argocd app list

# Status da app
argocd app get sdc-network-configs

# Sync manual
argocd app sync sdc-network-configs
```

### Verificar SDC
```bash
# Targets
kubectl get targets -n sdc

# Configs
kubectl get configs -n sdc

# Detalhes de um config
kubectl describe config <nome> -n sdc
```

### Verificar via gNMI
```bash
# Nokia
gnmic -a 172.40.40.11:57401 --insecure -u admin -p admin123 \
  get --path /interface[name=ethernet-1/1] --encoding json_ietf

# Arista
gnmic -a 172.20.20.11:6030 --insecure -u admin -p admin \
  get --path /interfaces/interface[name=Ethernet1]/config --encoding json_ietf
```

### Workflow GitOps
```bash
# Clone repo
git clone https://github.com/reinaldosaraiva/netops-gitops.git
cd netops-gitops

# Editar config
vim clusters/kind-arista-lab/configs/interfaces/arista-leaf1-interface-desc.yaml

# Commit e push
git add .
git commit -m "feat: update interface description"
git push

# ArgoCD sincroniza automaticamente em ~3 minutos
# Ou forcar sync:
argocd app sync sdc-network-configs
```

---

## Proximos Passos

1. **Expandir configuracoes** (Prioridade Alta)
   - Adicionar configs de BGP via GitOps
   - Adicionar configs de VLANs adicionais (20, 30)
   - Implementar configs de ACLs

2. **Melhorias de seguranca** (Prioridade Media)
   - Configurar branch protection no GitHub
   - Implementar code review obrigatorio
   - Adicionar validacao de YAML pre-commit (yamllint, kube-linter)

3. **Monitoramento** (Prioridade Media)
   - Configurar alertas ArgoCD (Slack/Teams)
   - Dashboard de status dos configs
   - Metricas de drift detection

4. **Automacao Avancada** (Prioridade Baixa)
   - CI/CD para validacao de configs
   - Testes automatizados de conectividade
   - Rollback automatico em caso de falha

---

## Licoes Aprendidas

### 1. Exposicao de servicos em KinD
KinD usa rede Docker interna (172.18.0.0/16). Para expor servicos externamente, necessario:
- iptables NAT, ou
- socat port forwarding (mais simples)

### 2. Target labels imutaveis no SDC
Labels `config.sdcio.dev/targetName` sao imutaveis apos criacao. Para mudar o target, necessario deletar e recriar o config.

### 3. Nokia SR Linux vlan-tagging
`vlan-tagging: true` e incompativel com `subinterface 0`. Planejar topologia considerando esta restricao.

### 4. ArgoCD directory recurse
Usar `directory.recurse: true` no Application para sincronizar subdiretorios automaticamente.

---

**Documentado por:** Claude Code
**Ultima atualizacao:** 2026-01-15 18:20 UTC
**BGP Migration completada:** 2026-01-15 18:17 UTC
