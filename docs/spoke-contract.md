# Contract for application VNets (spokes)

What a VNet with the layered structure of [`azure-virtual-network`](https://github.com/jalcalaroot/azure-virtual-network) must do to use the central egress. `app1` already follows it (`app1_*.tf`).

## 1. Unique address space

Every connected VNet needs its own address space, with no overlap with the hub (`10.250.0.0/23`), the egress VNet (`10.251.0.0/24`) or other spokes. Virtual WAN does not route duplicate prefixes.

| VNet | Address space |
|---|---|
| `vnet-jalcalaroot` (`azure-virtual-network`) | `10.0.0.0/16` |
| `vnet-app1` | `10.1.0.0/16` |
| next spoke | `10.2.0.0/16` |

`spoke_address_space` (`10.0.0.0/13`) covers `10.0.0.0`–`10.7.255.255`; widen it if more are needed.

## 2. No NAT Gateway of its own

Remove the NAT Gateway, its public IP and associations. The private subnets (`app`, `data`, `aks`, `privatelink`) keep `default_outbound_access_enabled = false`; their egress is the `0.0.0.0/0` route learned from the hub, with no UDR.

## 3. Connect the VNet to the hub

```hcl
module "vwan_connection" {
  source = "github.com/jalcalaroot/azure-vwan-firewall-egress//modules/spoke-connection"

  name                  = "conn-${azurerm_virtual_network.this.name}"
  virtual_hub_id        = var.vwan_hub_id
  virtual_network_id    = azurerm_virtual_network.this.id
  route_table_spokes_id = var.vwan_route_table_spokes_id
  route_table_egress_id = var.vwan_route_table_egress_id
}
```

The three IDs are outputs of this project (`virtual_hub_id`, `route_table_spokes_id`, `route_table_egress_id`).

## 4. Inbound subnets keep direct egress

Subnets that receive traffic from the internet need a route table with `0.0.0.0/0 → Internet`; otherwise replies would go through the firewall (asymmetric routing) and inbound connections would break:

| Subnet | Reason |
|---|---|
| `public` | Inbound through public IP / load balancer |
| `appgw` | Application Gateway v2 requires `0.0.0.0/0 → Internet` |
| `apim` | Public APIM gateway: symmetric replies and management endpoints |

A UDR overrides the route learned from the hub. Consequently, **egress from resources in those subnets is not centralized**: it uses their own public IP or default outbound access. Centralizing it too would require inbound traffic to enter through the firewall (DNAT), which is a different design.

## 5. Subnets with their own route table

"Propagate gateway routes" must stay `true`; otherwise Virtual WAN cannot inject the `0.0.0.0/0` route and the subnet loses its egress.

## 6. Services to verify when deployed

| Service | Consideration |
|---|---|
| AKS | `outbound_type = userDefinedRouting` (egress follows the subnet route) instead of `loadBalancer`, which would create its own egress IP and bypass the hub. Check that AKS accepts the vWAN-learned route without an explicit UDR |
| Container Apps | The environment must use workload profiles to support UDR/custom routes |
| Function App (VNet integration) | With "route all" its egress goes through the hub; with the default option it does not |
| Private endpoints | Stay local to each spoke; they do not depend on the hub |

## 7. Unchanged

NSGs with explicit outbound allow, ASGs, the port contract and the per-subnet rules of `azure-virtual-network` stay as they are. The subnet NSG still evaluates outbound traffic before it reaches the hub.
