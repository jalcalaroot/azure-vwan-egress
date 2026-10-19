# Contrato para las VNets de aplicación (spokes)

Para usar la salida central, una VNet con la estructura de `azure-virtual-network` debe cumplir lo siguiente. **Estos cambios aún no están aplicados en ese repo** (ver `CLAUDE.md`).

## 1. Direccionamiento único

Cada VNet conectada necesita un address space propio y sin solapes con el hub (`10.250.0.0/23`), la VNet de egress (`10.251.0.0/24`) ni otros spokes. Virtual WAN no enruta prefijos duplicados.

| VNet | Address space |
|---|---|
| `vnet-jalcalaroot` (hoy, `azure-virtual-network`) | 10.0.0.0/16 |
| siguiente spoke | 10.1.0.0/16 |
| siguiente | 10.2.0.0/16 |

`spoke_address_space` (`10.0.0.0/13`) cubre de 10.0.0.0 a 10.7.255.255; ampliarlo si se necesitan más.

## 2. Quitar el NAT propio

Eliminar `azurerm_nat_gateway`, su IP pública y sus asociaciones del repo del spoke. Las subnets privadas (`app`, `data`, `aks`, `privatelink`) mantienen `default_outbound_access_enabled = false`: su salida pasa a ser la ruta 0/0 que aprenden del hub, sin UDR.

## 3. Conectar la VNet al hub

```hcl
module "vwan_connection" {
  source = "github.com/jalcalaroot/azure-vwan-egress//modules/spoke-connection"

  name                  = "conn-${azurerm_virtual_network.this.name}"
  virtual_hub_id        = var.vwan_hub_id
  virtual_network_id    = azurerm_virtual_network.this.id
  route_table_spokes_id = var.vwan_route_table_spokes_id
  route_table_egress_id = var.vwan_route_table_egress_id
}
```

Los tres IDs son outputs de este repo (`virtual_hub_id`, `route_table_spokes_id`, `route_table_egress_id`).

## 4. Subnets de entrada: salida directa (route table con 0.0.0.0/0 → Internet)

Las subnets por las que **entra** tráfico desde internet deben seguir saliendo directo, o las respuestas volverían por el firewall (ruta asimétrica) y se romperían las conexiones entrantes:

| Subnet | Motivo |
|---|---|
| `public` | Entrada por IP pública / balanceador |
| `appgw` | Application Gateway v2 **exige** 0.0.0.0/0 → Internet |
| `apim` | APIM con gateway público: respuesta simétrica y endpoints de gestión |

Asociar a cada una una route table con `0.0.0.0/0 → Internet`. Una UDR gana sobre la ruta aprendida del hub. Consecuencia: **la salida de lo que viva en esas subnets no es central** (usa su IP pública / default outbound). Si se quiere centralizar también esa salida, hay que hacer entrar el tráfico por el firewall (DNAT), que es otro diseño.

## 5. Si una subnet privada lleva su propia route table

La opción **"Propagate gateway routes" debe quedar en `true`**; si está en `false`, Virtual WAN no puede inyectar el 0/0 y la subnet se queda sin salida.

## 6. Servicios que hay que verificar al desplegar (no confirmados)

| Servicio | Duda |
|---|---|
| AKS | `outbound_type`: `userDefinedRouting` (la salida va por la ruta de la subnet) en lugar de `loadBalancer`, que crearía una IP de salida propia y saltaría el hub. Comprobar si AKS acepta la ruta aprendida de vWAN sin una UDR explícita. |
| Container Apps | El entorno debe ser de perfiles de carga de trabajo para soportar UDR/rutas propias. |
| Function App (integración VNet) | Con "route all" su salida pasa por el hub; con la opción por defecto no. |
| Private endpoints | Siguen locales a cada spoke (misma VNet); no dependen del hub. |

## 7. Qué no cambia

NSGs con salida abierta, ASGs, contrato de puertos y reglas por subnet de `azure-virtual-network` siguen igual. El NSG de `nsg-snet-*` sigue evaluando la salida antes de que el tráfico llegue al hub.
