# ============================================================================
# Virtual WAN + hub + route tables
#
# Routing model (static, WITHOUT routing intent):
#
#   rt-spokes  - associated with EVERY application VNet. Holds the 0.0.0.0/0 ->
#                firewall route (injected by the egress connection) and the egress
#                VNet prefix. It does NOT hold the prefixes of other spokes: spokes
#                cannot see each other (isolated).
#   rt-egress  - associated with the egress VNet connection. Receives the prefixes
#                of ALL spokes (so the firewall can return the replies).
#
# Why not routing intent / secured hub: NAT Gateway is NOT supported in a Virtual
# WAN hub (nor in the AzureFirewallSubnet of a secured hub). To use a NAT Gateway
# the egress lives in an "egress" VNet connected to the hub, and the 0.0.0.0/0
# route is published as a static route on that connection. See docs/design.md.
# ============================================================================

resource "azurerm_virtual_wan" "this" {
  name                = "vwan-jalcalaroot"
  location            = var.location
  resource_group_name = var.resource_group_name
  type                = "Standard"

  # Spoke-to-spoke and branch-to-VNet traffic is governed by the route tables above,
  # not by the global flag: the Standard default behavior is kept.
  allow_branch_to_branch_traffic = true

  tags = local.tags
}

resource "azurerm_virtual_hub" "this" {
  name                = "vhub-${var.location}"
  location            = var.location
  resource_group_name = var.resource_group_name
  virtual_wan_id      = azurerm_virtual_wan.this.id
  sku                 = "Standard"
  address_prefix      = var.hub_address_prefix

  tags = local.tags
}

resource "azurerm_virtual_hub_route_table" "spokes" {
  name           = "rt-spokes"
  virtual_hub_id = azurerm_virtual_hub.this.id
  labels         = ["spokes"]
}

resource "azurerm_virtual_hub_route_table" "egress" {
  name           = "rt-egress"
  virtual_hub_id = azurerm_virtual_hub.this.id
  labels         = ["egress"]
}

# Connection of the egress VNet to the hub. It publishes the 0.0.0.0/0 route.
#   - internet_security_enabled = false: per Microsoft, the connection that
#     ADVERTISES 0.0.0.0/0 must not receive it (avoids routing loops).
#   - associated = rt-egress; propagates to rt-spokes (the static 0/0 route and
#     the egress VNet prefix).
resource "azurerm_virtual_hub_connection" "egress" {
  name                      = "conn-egress"
  virtual_hub_id            = azurerm_virtual_hub.this.id
  remote_virtual_network_id = azurerm_virtual_network.egress.id
  internet_security_enabled = false

  routing {
    associated_route_table_id = azurerm_virtual_hub_route_table.egress.id

    propagated_route_table {
      route_table_ids = [azurerm_virtual_hub_route_table.spokes.id]
      labels          = ["spokes"]
    }

    static_vnet_route {
      name                = "default-to-firewall"
      address_prefixes    = ["0.0.0.0/0"]
      next_hop_ip_address = azurerm_firewall.egress.ip_configuration[0].private_ip_address
    }

    static_vnet_propagate_static_routes_enabled = true
  }
}
