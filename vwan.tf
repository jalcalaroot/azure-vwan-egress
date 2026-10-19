# ============================================================================
# Virtual WAN + hub + tablas de rutas
#
# Modelo de enrutamiento (estatico, SIN routing intent):
#
#   rt-spokes  - asociada a TODAS las VNets de aplicacion. Contiene la ruta
#                0.0.0.0/0 -> firewall (la inyecta la conexion de egress) y el
#                prefijo de la VNet de egress. NO contiene los prefijos de los
#                otros spokes: los spokes no se ven entre si (aislados).
#   rt-egress  - asociada a la conexion de la VNet de egress. Recibe los
#                prefijos de TODOS los spokes (para que el firewall sepa
#                devolver las respuestas).
#
# Por que no routing intent / secured hub: el NAT Gateway NO esta soportado en
# el hub de Virtual WAN (ni en AzureFirewallSubnet de un secured hub). Para
# tener NAT Gateway la salida vive en una VNet "de egress" conectada al hub y
# el 0.0.0.0/0 se publica como ruta estatica en esa conexion. Ver
# docs/design.md.
# ============================================================================

resource "azurerm_virtual_wan" "this" {
  name                = "vwan-jalcalaroot"
  location            = var.location
  resource_group_name = var.resource_group_name
  type                = "Standard"

  # Spoke-a-spoke y rama-a-VNet los gobiernan las tablas de rutas de arriba,
  # no el flag global: se deja el comportamiento por defecto de Standard.
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

# Conexion de la VNet de egress al hub. Es la que publica el 0.0.0.0/0.
#   - internet_security_enabled = false: segun Microsoft, la conexion que
#     ANUNCIA el 0.0.0.0/0 no debe recibirlo (evita bucles de ruteo).
#   - associated = rt-egress; propaga hacia rt-spokes (el 0/0 estatico y el
#     prefijo de la VNet de egress).
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
