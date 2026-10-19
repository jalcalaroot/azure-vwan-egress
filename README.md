# azure-vwan-egress

Virtual WAN que centraliza la **salida a internet** de las VNets de aplicación mediante Azure Firewall detrás de un **NAT Gateway StandardV2** (alta disponibilidad, IPs de salida estables). La entrada de tráfico sigue siendo por las subnets públicas de cada VNet.

> Estado: diseñado y validado (`terraform validate`, `tflint`, `plan`: 17 recursos). **No desplegado.**

Por qué la salida vive en una VNet de egress y no en el hub: el NAT Gateway no está soportado en el hub de Virtual WAN. Ver [docs/design.md](docs/design.md).

## Recursos

Virtual WAN Standard, virtual hub, 2 tablas de rutas, VNet de egress con `AzureFirewallSubnet`, Azure Firewall Standard (3 zonas) con política de salida abierta, NAT Gateway StandardV2 + IP pública, Log Analytics y diagnóstico del firewall.

## Uso

```bash
export TF_VAR_subscription_id=<SUBSCRIPTION_ID>
terraform init
terraform plan
terraform apply   # el hub tarda 20-30 min
```

Los spokes se conectan con [`modules/spoke-connection`](modules/spoke-connection) y deben cumplir [docs/spoke-contract.md](docs/spoke-contract.md).

## Outputs

`virtual_hub_id`, `route_table_spokes_id`, `route_table_egress_id`, `egress_public_ip`, `firewall_private_ip`.

## Costo

≈ US$1,51 por hora (~US$36 al día, ~US$1.100 al mes), el 80 % es el Azure Firewall. Pensado para levantar, probar y dar de baja el mismo día. Detalle en [docs/design.md](docs/design.md).
