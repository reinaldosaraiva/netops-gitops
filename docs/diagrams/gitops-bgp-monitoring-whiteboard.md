# NetOps GitOps BGP Monitoring - Whiteboard Diagram

> Diagrama estilo whiteboard educacional do pipeline GitOps para monitoramento BGP

## Diagrama Principal

```mermaid
flowchart TB
    subgraph OVERVIEW["SECTION 1: GITOPS PIPELINE OVERVIEW"]
        direction TB
        GH["fa:fa-github GitHub<br/>netops-gitops repo"]
        ARGO["fa:fa-sync ArgoCD<br/>Sync Controller"]
        SDC["fa:fa-cogs SDC<br/>Config Server"]

        GH -->|"1. Push configs"| ARGO
        ARGO -->|"2. Apply manifests"| SDC
    end

    subgraph OPERATION["SECTION 2: DATA COLLECTION FLOW"]
        direction TB

        subgraph NOKIA["Nokia SR Linux"]
            NS1["spine-1<br/>172.40.40.11"]
            NS2["spine-2<br/>172.40.40.12"]
            NL1["leaf-1<br/>172.40.40.21"]
            NL2["leaf-2<br/>172.40.40.22"]
        end

        subgraph ARISTA["Arista cEOS"]
            AS1["spine-1<br/>172.20.20.11"]
            AL1["leaf-1<br/>172.20.20.21"]
            AL2["leaf-2<br/>172.20.20.22"]
        end

        SDC -->|"3. gNMI SET"| NOKIA
        SDC -->|"3. gNMI SET"| ARISTA

        TEL["fa:fa-satellite-dish Telegraf<br/>gNMI Collector"]
        NOKIA -->|"4. gNMI Subscribe<br/>on_change"| TEL
        ARISTA -->|"4. gNMI Subscribe<br/>sample 10s"| TEL

        INFLUX["fa:fa-database InfluxDB<br/>network-telemetry"]
        TEL -->|"5. Write metrics"| INFLUX

        GRAF["fa:fa-chart-line Grafana<br/>Dashboards"]
        INFLUX -->|"6. Flux queries"| GRAF
    end

    subgraph CONCEPTS["SECTION 3: KEY CONCEPTS"]
        direction TB
        K1["<b>gNMI Subscriptions</b><br/>• on_change: BGP state<br/>• sample 10s: counters"]
        K2["<b>Flux Query Pattern</b><br/>• filter → last → group<br/>• keep → rename"]
        K3["<b>Value Mappings</b><br/>• active → UP (green)<br/>• idle → DOWN (red)"]
        K4["<b>GitOps Benefits</b><br/>• Version control<br/>• Auto-sync<br/>• Audit trail"]
    end

    style GH fill:#90EE90,stroke:#228B22,color:#000
    style ARGO fill:#87CEEB,stroke:#4682B4,color:#000
    style SDC fill:#DDA0DD,stroke:#9932CC,color:#000
    style TEL fill:#FFB347,stroke:#FF8C00,color:#000
    style INFLUX fill:#87CEFA,stroke:#4169E1,color:#000
    style GRAF fill:#98FB98,stroke:#32CD32,color:#000
    style NOKIA fill:#FFE4B5,stroke:#DEB887,color:#000
    style ARISTA fill:#E6E6FA,stroke:#9370DB,color:#000
    style K1 fill:#FFFACD,stroke:#DAA520,color:#000
    style K2 fill:#FFFACD,stroke:#DAA520,color:#000
    style K3 fill:#FFFACD,stroke:#DAA520,color:#000
    style K4 fill:#FFFACD,stroke:#DAA520,color:#000
```

## BGP Status Dashboard Layout

```mermaid
flowchart TB
    subgraph DASHBOARD["GRAFANA DASHBOARD: Network Overview"]
        direction TB

        subgraph ROW1["Traffic Panels"]
            P1["Interface Traffic<br/>(Nokia)<br/>━━━━━━━━<br/>timeseries"]
            P2["Interface Traffic<br/>(Arista)<br/>━━━━━━━━<br/>timeseries"]
        end

        subgraph ROW2["BGP Status (Semaphore Style)"]
            P3["Nokia Spines BGP<br/>┌────┬────┬────┐<br/>│Switch│Peer│Status│<br/>├────┼────┼────┤<br/>│.11 │10.x│ UP │<br/>│.12 │10.x│ UP │<br/>└────┴────┴────┘"]
            P4["Nokia Leafs BGP<br/>┌────┬────┬────┐<br/>│Switch│Peer│Status│<br/>├────┼────┼────┤<br/>│.21 │10.x│ UP │<br/>│.22 │10.x│ UP │<br/>└────┴────┴────┘"]
        end

        subgraph ROW3["System Metrics"]
            P5["CPU Utilization<br/>━━━━━━━━<br/>timeseries"]
            P6["Memory Usage<br/>━━━━━━━━<br/>timeseries"]
        end
    end

    style P1 fill:#E0FFFF,stroke:#00CED1,color:#000
    style P2 fill:#E0FFFF,stroke:#00CED1,color:#000
    style P3 fill:#90EE90,stroke:#228B22,color:#000
    style P4 fill:#90EE90,stroke:#228B22,color:#000
    style P5 fill:#FFE4E1,stroke:#FF6347,color:#000
    style P6 fill:#FFE4E1,stroke:#FF6347,color:#000
```

## Data Flow Detail

```mermaid
sequenceDiagram
    autonumber
    participant GH as GitHub
    participant AC as ArgoCD
    participant SDC as SDC Controller
    participant SW as Switches
    participant TEL as Telegraf
    participant IDB as InfluxDB
    participant GF as Grafana

    Note over GH,GF: GitOps Configuration Pipeline
    GH->>AC: Push commit (configs/*.yaml)
    AC->>AC: Detect OutOfSync
    AC->>SDC: Apply Config CRD
    SDC->>SW: gNMI SET (BGP config)
    SW-->>SDC: OK

    Note over SW,GF: Telemetry Collection Pipeline
    loop Every 10s (sample) or on state change
        SW->>TEL: gNMI Subscribe response
        TEL->>IDB: Write to network-telemetry bucket
    end

    Note over IDB,GF: Visualization Pipeline
    GF->>IDB: Flux query (last 1h)
    IDB-->>GF: BGP session states
    GF->>GF: Apply value mappings (UP/DOWN colors)
```

## Legend

| Symbol | Meaning |
|--------|---------|
| Green boxes | Input/Source components |
| Blue boxes | Processing components |
| Orange boxes | Collection components |
| Purple boxes | Controller components |
| Yellow boxes | Key concepts/notes |

## Technical Details

### Flux Query (BGP Status)

```flux
from(bucket: "network-telemetry")
  |> range(start: -1h)
  |> filter(fn: (r) => r["_measurement"] == "bgp_neighbor")
  |> filter(fn: (r) => r["_field"] == "session_state")
  |> last()
  |> group()                    // Merge separate tables
  |> keep(columns: ["source", "peer_address", "_value"])
  |> rename(columns: {
      source: "Switch",
      peer_address: "Peer",
      _value: "Status"
  })
```

### Value Mappings (Grafana)

| State | Display | Color |
|-------|---------|-------|
| established | UP | Green |
| active | UP | Green |
| idle | DOWN | Red |
| connect | CONNECTING | Yellow |

### gNMI Subscriptions (Telegraf)

| Target | Path | Mode |
|--------|------|------|
| Nokia | `/network-instance[name=default]/protocols/bgp/neighbor[peer-address=*]/session-state` | on_change |
| Nokia | `/interface[name=*]/statistics` | sample 10s |
| Arista | `/interfaces/interface/state/counters` | sample 10s |

---

*Generated: 2026-01-15 | Style: Whiteboard Educational*
