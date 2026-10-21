# ============================================================================
# VNet de egress: Azure Firewall (SNAT + politica) detras de NAT Gateway
# StandardV2 (IPs de salida estables, 64.512 puertos SNAT por IP).
#
# Alta disponibilidad: firewall en 3 zonas + NAT Gateway StandardV2
# (zona-redundante por diseno; el argumento zones debe omitirse).
# ============================================================================

resource "azurerm_virtual_network" "egress" {
  name                = "vnet-egress"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = [var.egress_vnet_address_space]

  tags = local.tags
}

resource "azurerm_subnet" "firewall" {
  name                 = "AzureFirewallSubnet" # nombre obligatorio
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.egress.name
  address_prefixes     = [var.egress_firewall_subnet_cidr]
}

# --- NAT Gateway StandardV2 (la salida real a internet) -----------------

resource "azurerm_public_ip" "nat" {
  name                = "pip-nat-egress"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  # La regla azurerm_public_ip_invalid_sku de tflint no conoce StandardV2.
  sku  = "StandardV2" # tflint-ignore: azurerm_public_ip_invalid_sku
  tags = local.tags
}

resource "azurerm_nat_gateway" "egress" {
  name                    = "nat-gw-egress"
  location                = var.location
  resource_group_name     = var.resource_group_name
  sku_name                = "StandardV2"
  idle_timeout_in_minutes = 4

  tags = local.tags
}

resource "azurerm_nat_gateway_public_ip_association" "egress" {
  nat_gateway_id       = azurerm_nat_gateway.egress.id
  public_ip_address_id = azurerm_public_ip.nat.id
}

resource "azurerm_subnet_nat_gateway_association" "firewall" {
  subnet_id      = azurerm_subnet.firewall.id
  nat_gateway_id = azurerm_nat_gateway.egress.id

  depends_on = [azurerm_nat_gateway_public_ip_association.egress]
}

# --- Azure Firewall -----------------------------------------------------

# IP propia del firewall (gestion / DNAT entrante). La salida a internet NO
# usa esta IP: con el NAT Gateway asociado a la subnet, el SNAT sale por el NAT.
resource "azurerm_public_ip" "firewall" {
  name                = "pip-fw-egress"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"]

  tags = local.tags
}

resource "azurerm_firewall_policy" "egress" {
  name                = "fwp-egress"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "Standard"

  # "Deny" = alerta y bloquea trafico hacia/desde IPs, dominios y URLs
  # maliciosos conocidos (feed de Microsoft). Recomendado por Microsoft; en
  # modo "Alert" una regla de red con destino 80/443 enmascara las alertas
  # (problema conocido). La salida sigue abierta para todo lo demas.
  threat_intelligence_mode = "Deny"

  # DNS proxy: el firewall escucha en el 53 y reenvia a Azure DNS. Solo surte
  # efecto en las VNets cuyo servidor DNS sea la IP privada del firewall (ver
  # var.app1_dns_via_firewall y docs/firewall-review.md).
  dns {
    proxy_enabled = true
  }

  # Policy Analytics: reglas poco usadas, flujos principales y analisis por
  # regla. Necesita el mismo workspace que el diagnostico del firewall, con
  # logs estructurados (tablas AZFW*) en el plan Analytics. Solo analiza lo
  # que ocurre despues de activarlo; los datos tardan ~60 min en aparecer.
  insights {
    enabled                            = true
    default_log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id
    retention_in_days                  = var.log_analytics_retention_days
  }

  tags = local.tags
}

# Salida ABIERTA (decision del propietario: "la salida debe estar abierta").
# Orden: primero se niegan destinos privados (los spokes solo salen a
# internet), luego se permite todo lo demas. Para filtrar por FQDN mas
# adelante basta con anadir reglas de aplicacion antes de la 200.
resource "azurerm_firewall_policy_rule_collection_group" "egress" {
  name               = "rcg-egress"
  firewall_policy_id = azurerm_firewall_policy.egress.id
  priority           = 100

  dynamic "network_rule_collection" {
    for_each = var.block_private_destinations ? [1] : []
    content {
      name     = "deny-private-destinations"
      priority = 100
      action   = "Deny"

      rule {
        name                  = "deny-rfc1918"
        protocols             = ["Any"]
        source_addresses      = [var.spoke_address_space]
        destination_addresses = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
        destination_ports     = ["*"]
      }
    }
  }

  network_rule_collection {
    name     = "allow-outbound-internet"
    priority = 200
    action   = "Allow"

    rule {
      name                  = "allow-all-outbound"
      protocols             = ["TCP", "UDP", "ICMP"]
      source_addresses      = [var.spoke_address_space]
      destination_addresses = ["*"]
      destination_ports     = ["*"]
    }
  }
}

resource "azurerm_firewall" "egress" {
  name                = "fw-egress"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku_name            = "AZFW_VNet"
  sku_tier            = "Standard"
  firewall_policy_id  = azurerm_firewall_policy.egress.id
  zones               = ["1", "2", "3"]

  ip_configuration {
    name                 = "ipconfig"
    subnet_id            = azurerm_subnet.firewall.id
    public_ip_address_id = azurerm_public_ip.firewall.id
  }

  tags = local.tags

  # El NAT debe estar en la subnet antes de que el firewall empiece a enrutar.
  depends_on = [azurerm_subnet_nat_gateway_association.firewall]
}

# --- Observabilidad -----------------------------------------------------

resource "azurerm_log_analytics_workspace" "this" {
  name                = "log-vwan-egress"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_analytics_retention_days

  tags = local.tags
}

resource "azurerm_monitor_diagnostic_setting" "firewall" {
  name                           = "diag-fw-egress"
  target_resource_id             = azurerm_firewall.egress.id
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.this.id
  log_analytics_destination_type = "Dedicated"

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}
