# ============================================================================
# Egress VNet: Azure Firewall (SNAT + policy) behind a StandardV2 NAT Gateway
# (stable outbound IPs, 64,512 SNAT ports per IP).
#
# High availability: firewall in 3 zones + StandardV2 NAT Gateway
# (zone-redundant by design; the zones argument must be omitted).
# ============================================================================

resource "azurerm_virtual_network" "egress" {
  name                = "vnet-egress"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = [var.egress_vnet_address_space]

  tags = local.tags
}

resource "azurerm_subnet" "firewall" {
  name                 = "AzureFirewallSubnet" # mandatory name
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.egress.name
  address_prefixes     = [var.egress_firewall_subnet_cidr]
}

# --- NAT Gateway StandardV2 (the actual internet egress) ----------------

resource "azurerm_public_ip" "nat" {
  name                = "pip-nat-egress"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  # The tflint rule azurerm_public_ip_invalid_sku does not know StandardV2.
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

# The firewall's own public IP (management / inbound DNAT). Internet egress does NOT
# use this IP: with the NAT Gateway on the subnet, SNAT leaves through the NAT.
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

  # "Deny" = alert and block traffic to/from known malicious IPs, domains and URLs
  # (Microsoft feed). Recommended by Microsoft; in "Alert" mode a network rule with
  # destination 80/443 masks the alerts (known issue). All other egress stays open.
  threat_intelligence_mode = "Deny"

  # DNS proxy: the firewall listens on port 53 and forwards to Azure DNS. It only
  # takes effect in VNets whose DNS server is the private IP of the firewall (see
  # var.app1_dns_via_firewall and docs/firewall.md).
  dns {
    proxy_enabled = true
  }

  # Policy Analytics: rarely used rules, top flows and per-rule analysis. Needs the
  # same workspace as the firewall diagnostics, with structured logs (AZFW* tables)
  # on the Analytics plan. It only analyzes what happens after it is enabled; data
  # takes ~60 minutes to appear.
  insights {
    enabled                            = true
    default_log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id
    retention_in_days                  = var.log_analytics_retention_days
  }

  tags = local.tags
}

# Egress rules. Evaluation order (Microsoft: network rules run BEFORE application
# rules and are terminating):
#   1. Network 100  deny RFC1918: spokes only reach the internet.
#   2. Network 200  allow every other port/protocol EXCEPT TCP 80/443 and UDP 443
#      (QUIC), so web traffic falls into the application rules, which log it by
#      DOMAIN (AZFWApplicationRule table). QUIC clients fall back to TCP 443.
#   3. Application 250 (optional) deny web categories: var.denied_web_categories.
#   4. Application 300 allow HTTP/HTTPS to any domain.
# If a network rule allowed 80/443, the application rules would never be evaluated.
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
    name     = "allow-outbound-non-web"
    priority = 200
    action   = "Allow"

    rule {
      name                  = "allow-tcp-non-web"
      protocols             = ["TCP"]
      source_addresses      = [var.spoke_address_space]
      destination_addresses = ["*"]
      destination_ports     = ["1-79", "81-442", "444-65535"]
    }

    rule {
      name                  = "allow-udp-non-quic"
      protocols             = ["UDP"]
      source_addresses      = [var.spoke_address_space]
      destination_addresses = ["*"]
      destination_ports     = ["1-442", "444-65535"]
    }

    rule {
      name                  = "allow-icmp"
      protocols             = ["ICMP"]
      source_addresses      = [var.spoke_address_space]
      destination_addresses = ["*"]
      destination_ports     = ["*"]
    }
  }

  # Web categories are FQDN-based on the Standard tier (verified); full-URL
  # categorization requires Premium.
  dynamic "application_rule_collection" {
    for_each = length(var.denied_web_categories) > 0 ? [1] : []
    content {
      name     = "deny-web-categories"
      priority = 250
      action   = "Deny"

      rule {
        name              = "deny-categories"
        source_addresses  = [var.spoke_address_space]
        web_categories    = var.denied_web_categories
        destination_fqdns = []

        protocols {
          type = "Http"
          port = 80
        }
        protocols {
          type = "Https"
          port = 443
        }
      }
    }
  }

  application_rule_collection {
    name     = "allow-web"
    priority = 300
    action   = "Allow"

    rule {
      name              = "allow-all-web"
      source_addresses  = [var.spoke_address_space]
      destination_fqdns = ["*"]

      protocols {
        type = "Http"
        port = 80
      }
      protocols {
        type = "Https"
        port = 443
      }
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

  # The NAT Gateway must be on the subnet before the firewall starts routing.
  depends_on = [azurerm_subnet_nat_gateway_association.firewall]
}

# --- Observability ------------------------------------------------------

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
