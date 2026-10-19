# azure-vwan-egress

Virtual WAN que centraliza la **salida a internet** de las VNets de aplicación mediante Azure Firewall detrás de un **NAT Gateway StandardV2** (alta disponibilidad, IPs de salida estables). La entrada de tráfico sigue siendo por las subnets públicas de cada VNet.

> Estado: desplegado y probado el 2026-10-19 (57 recursos, salida a internet verificada desde 2 zonas) y **dado de baja por completo**. Resultados en [docs/evidencia.md](docs/evidencia.md).

Por qué la salida vive en una VNet de egress y no en el hub: el NAT Gateway no está soportado en el hub de Virtual WAN. Ver [docs/design.md](docs/design.md).

## Arquitectura

```mermaid
flowchart LR
    NET(("Internet"))

    subgraph APP1["app1 (10.1.0.0/16) - sin NAT propio"]
        direction TB
        PUB["Subnets de ENTRADA<br/>public · appgw · apim<br/>salida directa (0/0 → Internet)"]
        PRIV["Subnets privadas<br/>app · data · aks · privatelink<br/>+ containerapps · func · aks-virtual-nodes"]
        VMS["VM z1 · VM z2<br/>(prueba, sin IP pública)"]
    end

    subgraph WAN["Virtual WAN"]
        HUB["Virtual hub 10.250.0.0/23<br/>rt-spokes · rt-egress"]
    end

    subgraph EG["vnet-egress (10.251.0.0/24)"]
        FW["Azure Firewall Standard<br/>3 zonas · salida abierta"]
        NAT["NAT Gateway StandardV2<br/>zona-redundante · IP estable"]
    end

    NET == "ENTRADA" ==> PUB
    PUB -. "salida directa" .-> NET
    PRIV -- "0.0.0.0/0 aprendido del hub" --> HUB
    VMS -.-> PRIV
    HUB -- "ruta estática 0/0 → IP del firewall" --> FW
    FW -- "SNAT" --> NAT
    NAT == "SALIDA" ==> NET
```

Las subnets de Azure abarcan todas las zonas de disponibilidad: las dos VMs de prueba están en zonas distintas (1 y 2) dentro de la misma subnet `snet-app`.

## Recursos

- **Transit:** Virtual WAN Standard, virtual hub y 2 tablas de rutas.
- **Salida central:** `vnet-egress` con Azure Firewall (3 zonas, salida abierta) detrás de un NAT Gateway StandardV2.
- **`app1`:** VNet de aplicación con las mismas 10 capas que `azure-virtual-network`, sin NAT propio, y dos VMs de prueba (zonas 1 y 2) sin IP pública.

Detalle por tipo:

Virtual WAN Standard, virtual hub, 2 tablas de rutas, VNet de egress con `AzureFirewallSubnet`, Azure Firewall Standard (3 zonas) con política de salida abierta, NAT Gateway StandardV2 + IP pública, Log Analytics y diagnóstico del firewall.

## Uso

```bash
export TF_VAR_subscription_id=<SUBSCRIPTION_ID>
terraform init
terraform plan
terraform apply   # el hub tarda 20-30 min
```

Los spokes se conectan con [`modules/spoke-connection`](modules/spoke-connection) y deben cumplir [docs/spoke-contract.md](docs/spoke-contract.md).

## Probar la salida

```bash
terraform output egress_public_ip     # IP del NAT Gateway
for z in 1 2; do
  az vm run-command invoke -g <RESOURCE_GROUP> -n vm-app1-test-z$z --command-id RunShellScript \
    --scripts "curl -s --max-time 15 https://ifconfig.me" --query "value[0].message" -o tsv
done
```

Las dos VMs (zonas 1 y 2) deben devolver la misma IP, igual a `egress_public_ip`.

## Outputs

`virtual_hub_id`, `route_table_spokes_id`, `route_table_egress_id`, `egress_public_ip`, `firewall_private_ip`, `app1_vnet_id`, `test_vm_names`.

## Costo

≈ US$1,6 por hora (~US$38 al día), el 80 % es el Azure Firewall. Una prueba de 2 horas cuesta ~US$4. Pensado para levantar, probar y dar de baja el mismo día. Detalle en [docs/design.md](docs/design.md).
