# azure-vwan-egress

Virtual WAN que centraliza la **salida a internet** de las VNets de aplicación mediante Azure Firewall detrás de un **NAT Gateway StandardV2** (alta disponibilidad, IPs de salida estables). La entrada de tráfico sigue siendo por las subnets públicas de cada VNet.

> Estado: desplegado y probado el 2026-10-19 (57 recursos, salida a internet verificada desde 2 zonas) y **dado de baja por completo**. Resultados en [docs/evidencia.md](docs/evidencia.md).

Por qué la salida vive en una VNet de egress y no en el hub: el NAT Gateway no está soportado en el hub de Virtual WAN. Ver [docs/design.md](docs/design.md).

## Arquitectura

![Arquitectura general](docs/img/diagrama-1.png)

Todos los diagramas (arquitectura, camino de un paquete, enrutamiento de Virtual WAN, evaluación de reglas del firewall y zonas de disponibilidad) están en [docs/diagrama.md](docs/diagrama.md).

Las VMs de prueba (`vm-app1-test-z1` y `-z2`, sin IP pública) viven en `snet-app`, la subnet privada de `app1`. Las subnets de Azure abarcan todas las zonas de disponibilidad: las dos VMs están en zonas distintas (1 y 2) dentro de la misma subnet.

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
