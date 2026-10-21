# Evidencia de la prueba (2026-10-19)

Se desplegaron los 57 recursos (hub, VNet de egress con Azure Firewall y NAT Gateway StandardV2, `app1` con 10 capas), se probó la salida a internet desde dos VMs en zonas distintas y luego se destruyó todo. Los identificadores de suscripción y la IP pública real se omiten.

## Despliegue

| | |
|---|---|
| Recursos creados | 57 (`Apply complete! Resources: 57 added`) |
| Duración | ~34 min (el hub y su conexión son lo más lento) |
| Cambio posterior | VM única → 2 VMs, una por zona (4 creados, 2 destruidos, ~1 min) |

## Resultados

| Prueba | Resultado |
|---|---|
| VMs sin IP pública, en `snet-app` (subnet privada, sin default outbound) | `vm-app1-test-z1` (zona 1) y `vm-app1-test-z2` (zona 2), ambas `Succeeded` |
| IP de salida vista desde internet (`curl https://ifconfig.me`) | Ambas devuelven `<NAT_PUBLIC_IP>`, igual a la IP del NAT Gateway |
| Ráfaga HTTPS (12 peticiones a microsoft.com por VM) | 24 de 24 con HTTP 200, ~80 ms de media, MTU 1500 |
| HTTP plano (example.com, 6 por VM) | 12 de 12 con HTTP 200 |
| Ráfaga variada (microsoft, github, google, aws, terraform registry, ifconfig; 8 por sitio) | 48 de 48 por VM (96 de 96) |
| Rutas efectivas de la NIC | `0.0.0.0/0` y `10.251.0.0/24` con origen *VirtualNetworkGateway* (inyectadas por el hub); sin UDR en la subnet |
| Hub | `conn-app1` con `internet security = True`, `conn-egress` con `False`; `rt-spokes` contiene `0.0.0.0/0` y el prefijo de egress |
| Firewall | Estado `Succeeded`, 3 zonas, Standard; logs `AZFWNetworkRule`: tráfico de ambas VMs con `Action = Allow`, regla `allow-all-outbound` |
| NAT Gateway | `StandardV2`, asociado solo a `AzureFirewallSubnet` |

## Observación honesta

En los primeros minutos tras crear las VMs, la VM de la zona 2 tuvo una petición lenta (18,6 s) y 2 de 3 repeticiones que agotaron los 30 s de timeout, con la conexión TCP abierta en milisegundos. No se repitió en las 144 peticiones posteriores. No se identificó la causa; la hipótesis (no verificada) es el calentamiento de rutas del hub o de la VM recién creada. Si esto se vuelve a desplegar conviene repetir la prueba desde los primeros minutos.

## Lo que esta prueba NO cubre

- Aislamiento entre spokes (solo hay `app1`).
- Entrada por las subnets públicas (no hay Application Gateway ni balanceador desplegados).
- AKS, Container Apps y Function dentro de `app1` (las subnets existen, los servicios no).
- Filtrado por FQDN (la salida del firewall se dejó abierta por un supuesto de diseño).

## Baja completa

`terraform destroy` terminó con `Destroy complete! Resources: 59 destroyed` (los 57 originales más los 2 recursos de la VM única que se reemplazó). Los recursos estuvieron activos ~68 min en total (del inicio del apply, 18:12 UTC, al fin del destroy, ~19:20 UTC), unos US$2 a precio de lista.

Verificación posterior contra Azure (todo en 0): Virtual WANs, virtual hubs, VNets, firewalls, políticas de firewall, NAT Gateways, IPs públicas, NSG, ASG, route tables, NICs, VMs, discos y Log Analytics; el estado de Terraform quedó vacío. En el resource group solo quedan los recursos que ya existían antes de esta prueba (identidades administradas, storage accounts, un action group y una zona DNS).
