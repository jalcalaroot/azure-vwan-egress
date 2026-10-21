# Diagramas de la solución

Los diagramas se dibujan solos en GitHub (Mermaid); cada uno tiene también una imagen en [`img/`](img/) por si se ven desde un editor sin soporte de Mermaid. Reflejan lo que se desplegó y probó el 2026-10-19, más las reglas de dominio añadidas el 2026-10-21 (aún sin desplegar). Los CIDR son los del repo.

## 1. Arquitectura general

```mermaid
flowchart TB
    NET(("Internet"))

    subgraph APP1["app1 - vnet-app1 10.1.0.0/16 - sin NAT propio"]
        direction TB
        subgraph ENTRADA["Subnets de ENTRADA: salida directa por UDR 0/0 a Internet"]
            PUB["snet-public"]
            AGW["snet-appgw"]
            APIM["snet-apim"]
        end
        subgraph PRIV["Subnets privadas: salida por el hub"]
            subgraph SAPP["snet-app 10.1.8.0/22 - privada, sin default outbound"]
                VM1["vm-app1-test-z1<br/>zona 1 - 10.1.8.x<br/>sin IP publica"]
                VM2["vm-app1-test-z2<br/>zona 2 - 10.1.8.x<br/>sin IP publica"]
            end
            AKS["snet-aks"]
            PL["snet-privatelink"]
            OTR["snet-containerapps<br/>snet-func<br/>snet-aks-virtual-nodes"]
        end
        DATA["snet-data<br/>SIN internet: 0/0 a None"]
    end

    subgraph WAN["Virtual WAN Standard"]
        HUB["Virtual hub vhub-eastus 10.250.0.0/23<br/>rt-spokes  y  rt-egress"]
    end

    subgraph EG["vnet-egress 10.251.0.0/24"]
        FW["Azure Firewall Standard<br/>3 zonas - IP privada 10.251.0.4<br/>politica: inteligencia de amenazas Deny, DNS proxy, Policy Analytics"]
        NAT["NAT Gateway StandardV2<br/>zona-redundante - IP publica estable"]
    end

    LAW[("Log Analytics<br/>logs AZFW")]

    NET == "ENTRADA" ==> PUB
    NET == "ENTRADA" ==> AGW
    NET == "ENTRADA" ==> APIM
    PUB -. "salida directa" .-> NET
    VM1 -- "0/0 aprendido del hub" --> HUB
    VM2 -- "0/0 aprendido del hub" --> HUB
    AKS --> HUB
    PL --> HUB
    OTR --> HUB
    HUB -- "ruta estatica 0/0 a 10.251.0.4" --> FW
    FW -- "SNAT" --> NAT
    NAT == "SALIDA" ==> NET
    FW -. "diagnostico" .-> LAW
```

<details><summary>Ver como imagen</summary>

![Diagrama 1](img/diagrama-1.png)

</details>

## 2. Camino de un paquete de salida

```mermaid
sequenceDiagram
    autonumber
    participant VM as VM en snet-app (10.1.8.x)
    participant H as Hub (rt-spokes)
    participant F as Azure Firewall (10.251.0.4)
    participant N as NAT Gateway
    participant I as Internet

    VM->>H: 0.0.0.0/0 aprendido del hub (sin UDR en la subnet)
    H->>F: ruta estatica 0/0 de conn-egress, siguiente salto 10.251.0.4
    Note over F: evalua inteligencia de amenazas, reglas de red y de aplicacion, y registra
    F->>N: SNAT: la subnet del firewall tiene el NAT Gateway
    N->>I: sale con la IP publica del NAT
    I-->>N: respuesta
    N-->>F: vuelve a la instancia que abrio la conexion
    F-->>H: ruta hacia 10.1.0.0/16 (rt-egress)
    H-->>VM: respuesta
```

<details><summary>Ver como imagen</summary>

![Diagrama 2](img/diagrama-2.png)

</details>

## 3. Enrutamiento de Virtual WAN

```mermaid
flowchart LR
    subgraph CONN["Conexiones al hub"]
        CA["conn-app1<br/>internet security = true"]
        CE["conn-egress<br/>internet security = false<br/>ruta estatica 0/0 a 10.251.0.4"]
    end

    subgraph RT["Tablas de rutas del hub"]
        RS["rt-spokes<br/>0.0.0.0/0 a firewall<br/>10.251.0.0/24"]
        RE["rt-egress<br/>10.1.0.0/16 (app1)"]
    end

    CA -- "se ASOCIA a" --> RS
    CA -- "PROPAGA su prefijo a" --> RE
    CE -- "se ASOCIA a" --> RE
    CE -- "PROPAGA 0/0 y su prefijo a" --> RS
```

<details><summary>Ver como imagen</summary>

![Diagrama 3](img/diagrama-3.png)

</details>

Los spokes solo tienen en `rt-spokes` la ruta al firewall: no ven a otros spokes (aislamiento). El firewall ve el prefijo de cada spoke en `rt-egress`, que es lo que le permite devolver las respuestas.

## 4. Cómo evalúa el firewall un paquete

```mermaid
flowchart TD
    P["Paquete de un spoke"] --> TI{"Inteligencia de amenazas:<br/>destino malicioso conocido?"}
    TI -- "si" --> D1["DENY y alerta"]
    TI -- "no" --> R1{"Red 100: destino privado<br/>RFC1918?"}
    R1 -- "si" --> D2["DENY"]
    R1 -- "no" --> R2{"Red 200: TCP distinto de 80 y 443,<br/>UDP distinto de 443, o ICMP?"}
    R2 -- "si" --> A1["ALLOW"]
    R2 -- "no" --> W{"Es HTTP 80 o HTTPS 443?"}
    W -- "no (UDP 443)" --> D3["DENY por defecto"]
    W -- "si" --> C{"Aplicacion 250: categoria negada?<br/>(vacia hasta decidir Premium)"}
    C -- "si" --> D4["DENY"]
    C -- "no" --> AW{"Aplicacion 300: allow-all-web"}
    AW -- "HTTPS con SNI o HTTP" --> A2["ALLOW y registra el DOMINIO"]
    AW -- "HTTPS sin SNI" --> D5["DENY por defecto (a verificar)"]
```

<details><summary>Ver como imagen</summary>

![Diagrama 4](img/diagrama-4.png)

</details>

Las reglas de red se evalúan antes que las de aplicación y son terminantes; por eso la regla de red 200 excluye el tráfico web.

## 5. Zonas de disponibilidad

```mermaid
flowchart LR
    subgraph Z1["Zona 1"]
        VM1["vm-app1-test-z1"]
        FW1["instancia del firewall"]
    end
    subgraph Z2["Zona 2"]
        VM2["vm-app1-test-z2"]
        FW2["instancia del firewall"]
    end
    subgraph Z3["Zona 3"]
        FW3["instancia del firewall"]
    end
    SUB["snet-app: UNA subnet que abarca las 3 zonas"]
    NATZ["NAT Gateway StandardV2: zona-redundante"]

    VM1 --- SUB
    VM2 --- SUB
    FW1 --> NATZ
    FW2 --> NATZ
    FW3 --> NATZ
```

<details><summary>Ver como imagen</summary>

![Diagrama 5](img/diagrama-5.png)

</details>

Las subnets de Azure no pertenecen a una zona; solo los recursos que se colocan en ellas (VM, firewall) son zonales o zona-redundantes.
