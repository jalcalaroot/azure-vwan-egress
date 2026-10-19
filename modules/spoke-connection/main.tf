# Conecta una VNet de aplicacion al hub con el modelo de rutas de este
# proyecto: se asocia a rt-spokes (recibe el 0.0.0.0/0 y NO ve a otros
# spokes) y propaga su prefijo a rt-egress (para que el firewall devuelva las
# respuestas). internet_security_enabled = true es lo que hace que la VNet
# "aprenda" el 0.0.0.0/0.
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
