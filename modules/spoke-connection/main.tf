# Connects an application VNet to the hub using this project's routing model: it
# associates with rt-spokes (receives the 0.0.0.0/0 route and does NOT see other
# spokes) and propagates its prefix to rt-egress (so the firewall can return the
# replies). internet_security_enabled = true is what makes the VNet learn the
# 0.0.0.0/0 route.
resource "azurerm_virtual_hub_connection" "this" {
  name                      = var.name
  virtual_hub_id            = var.virtual_hub_id
  remote_virtual_network_id = var.virtual_network_id
  internet_security_enabled = true

  routing {
    associated_route_table_id = var.route_table_spokes_id

    propagated_route_table {
      route_table_ids = [var.route_table_egress_id]
      labels          = ["egress"]
    }
  }
}
