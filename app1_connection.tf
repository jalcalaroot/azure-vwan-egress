# Connects app1 to the hub: it associates with rt-spokes (learns the 0.0.0.0/0 route
# to the firewall) and propagates its prefix to rt-egress (so the firewall can
# return the replies). See modules/spoke-connection.
module "app1_connection" {
  source = "./modules/spoke-connection"

  name                  = "conn-app1"
  virtual_hub_id        = azurerm_virtual_hub.this.id
  virtual_network_id    = module.vnet.resource_id
  route_table_spokes_id = azurerm_virtual_hub_route_table.spokes.id
  route_table_egress_id = azurerm_virtual_hub_route_table.egress.id

  # The egress connection publishes the 0.0.0.0/0 route; app1 connects afterwards so it
  # learns it from the start.
  depends_on = [azurerm_virtual_hub_connection.egress]
}
