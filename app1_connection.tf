# Conecta app1 al hub: se asocia a rt-spokes (aprende el 0.0.0.0/0 hacia el
# firewall) y propaga su prefijo a rt-egress (para que el firewall devuelva
# las respuestas). Ver modules/spoke-connection.
module "app1_connection" {
  source = "./modules/spoke-connection"

  name                  = "conn-app1"
  virtual_hub_id        = azurerm_virtual_hub.this.id
  virtual_network_id    = module.vnet.resource_id
  route_table_spokes_id = azurerm_virtual_hub_route_table.spokes.id
  route_table_egress_id = azurerm_virtual_hub_route_table.egress.id

  # La conexion del egress publica el 0.0.0.0/0; app1 debe conectarse despues
  # para aprenderlo desde el primer momento.
  depends_on = [azurerm_virtual_hub_connection.egress]
}
