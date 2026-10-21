# Application VNet "app1": the same ten layers (subnets, one NSG per subnet with an
# explicit outbound allow, ASGs) as azure-virtual-network, adapted to the central
# Virtual WAN egress:
#   1. No NAT Gateway of its own. The private subnets (app, data, aks,
#      privatelink) keep default_outbound_access_enabled = false and leave
#      through the 0.0.0.0/0 route learned from the hub.
#   2. The subnets that receive internet traffic (public, appgw, apim) use a
#      0.0.0.0/0 -> Internet route table, so replies leave symmetrically
#      (Application Gateway v2 also requires it).
#   3. The VNet connects to the hub through modules/spoke-connection
#      (see app1_connection.tf).
# Resource names carry the "app1" suffix because the account uses a single
# shared resource group and names must not collide with other VNets.
#
# The AVM module's parent_id takes the resource group ID, not its name.
data "azurerm_resource_group" "this" {
  name = var.resource_group_name
}

# ============================================================================
# Network Security Groups - one per subnet. Lateral rules use subnet CIDRs
# (each subnet hosts a single role) rather than ASGs, because the main callers
# (APIM, Function, Container Apps) cannot be ASG members. The provider does
# support ASGs on Private Endpoints and AKS node pools, used below.
# ============================================================================

resource "azurerm_network_security_group" "public" {
  #checkov:skip=CKV_AZURE_160:Port 80 is kept by design for the HTTP->HTTPS redirect done by Application Gateway - plain traffic never reaches the backends.
  name                = "nsg-app1-snet-public"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = local.tags

  security_rule {
    name                       = "Allow-HTTPS-Inbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "Internet"
    destination_address_prefix = "VirtualNetwork"
  }
  security_rule {
    name                       = "Allow-HTTP-Inbound"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "Internet"
    destination_address_prefix = "VirtualNetwork"
  }
  security_rule {
    name                       = "Deny-All-Inbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  # Explicit outbound allow, equivalent to an NACL egress rule (without it only the default rule 65001 applies).
  security_rule {
    name                       = "Allow-All-Outbound"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_security_group" "appgw" {
  #checkov:skip=CKV_AZURE_160:Port 80 is kept by design for the Application Gateway HTTP->HTTPS redirect - same reason as nsg-app1-snet-public.
  name                = "nsg-app1-snet-appgw"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = local.tags

  security_rule {
    name                       = "Allow-GatewayManager"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "65200-65535"
    source_address_prefix      = "GatewayManager"
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "Allow-Internet-HTTP"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "Allow-Internet-HTTPS"
    priority                   = 300
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "Allow-AzureLoadBalancer"
    priority                   = 400
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "Deny-All-Inbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  # Explicit outbound allow, equivalent to an NACL egress rule (without it only the default rule 65001 applies).
  security_rule {
    name                       = "Allow-All-Outbound"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_security_group" "private" {
  name                = "nsg-app1-snet-app"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = local.tags

  security_rule {
    name                       = "Allow-From-Public-Subnets"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["80", "443", "8080"]
    source_address_prefixes    = [var.public_subnet_cidr, var.appgw_subnet_cidr]
    destination_address_prefix = "VirtualNetwork"
  }
  # Only the subnet itself; external callers enter through Allow-From-Public-Subnets.
  security_rule {
    name                       = "Allow-Intra-Subnet"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefixes    = [var.app_subnet_cidr]
    destination_address_prefix = "VirtualNetwork"
  }
  security_rule {
    name                       = "Deny-All-Inbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  # Explicit outbound allow, equivalent to an NACL egress rule (without it only the default rule 65001 applies).
  security_rule {
    name                       = "Allow-All-Outbound"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_security_group" "data" {
  name                = "nsg-app1-snet-data"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = local.tags

  security_rule {
    name                       = "Allow-From-App-Subnets"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["3306", "5432", "1433", "6379", "27017", "9092", "9093", "9200", "9042"]
    source_address_prefixes    = [var.app_subnet_cidr]
    destination_address_prefix = "VirtualNetwork"
  }
  security_rule {
    name                       = "Allow-VNet-Replication"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["3306", "5432", "1433", "6379", "27017", "9092", "9093", "9200", "9042"]
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }
  security_rule {
    name                       = "Deny-All-Inbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  # Explicit outbound allow, equivalent to an NACL egress rule (without it only the default rule 65001 applies).
  security_rule {
    name                       = "Allow-All-Outbound"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_security_group" "aks" {
  name                = "nsg-app1-snet-aks"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = local.tags

  security_rule {
    name                       = "Allow-AzureLoadBalancer"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }
  # Nodes, virtual nodes (ACI) and Application Gateway (AGIC).
  security_rule {
    name                       = "Allow-AKS-Internal-And-AppGateway"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefixes    = [var.aks_subnet_cidr, var.aks_virtual_nodes_subnet_cidr, var.appgw_subnet_cidr]
    destination_address_prefix = "VirtualNetwork"
  }
  security_rule {
    name                       = "Deny-All-Inbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  # Explicit outbound allow, equivalent to an NACL egress rule (without it only the default rule 65001 applies).
  security_rule {
    name                       = "Allow-All-Outbound"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_security_group" "privatelink" {
  name                = "nsg-app1-snet-privatelink"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = local.tags

  security_rule {
    name                       = "Allow-From-App-And-Data-Subnets"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["443", "1433", "5432"]
    source_address_prefixes    = [var.app_subnet_cidr, var.data_subnet_cidr]
    destination_address_prefix = "VirtualNetwork"
  }
  # With subnet network policies enabled, this NSG applies to each Private Endpoint NIC.
  # One rule per service, with the service ASG as destination (443); priorities in
  # steps of 100. Rule 100 above (app and data to any endpoint) is the baseline for
  # the application and data tiers. APIM reaches only the Function App.
  security_rule {
    name                                       = "Allow-Apim-To-Function"
    priority                                   = 200
    direction                                  = "Inbound"
    access                                     = "Allow"
    protocol                                   = "Tcp"
    source_port_range                          = "*"
    destination_port_range                     = "443"
    source_address_prefixes                    = [var.apim_subnet_cidr]
    destination_application_security_group_ids = [azurerm_application_security_group.this["function"].id]
  }
  # The Function reaches Cosmos DB.
  security_rule {
    name                                       = "Allow-Func-To-Cosmos"
    priority                                   = 300
    direction                                  = "Inbound"
    access                                     = "Allow"
    protocol                                   = "Tcp"
    source_port_range                          = "*"
    destination_port_range                     = "443"
    source_address_prefixes                    = [var.func_subnet_cidr]
    destination_application_security_group_ids = [azurerm_application_security_group.this["cosmos"].id]
  }
  # The Function reaches storage (host and Durable Functions state).
  security_rule {
    name                                       = "Allow-Func-To-Storage"
    priority                                   = 400
    direction                                  = "Inbound"
    access                                     = "Allow"
    protocol                                   = "Tcp"
    source_port_range                          = "*"
    destination_port_range                     = "443"
    source_address_prefixes                    = [var.func_subnet_cidr]
    destination_application_security_group_ids = [azurerm_application_security_group.this["storage"].id]
  }
  # The Function reaches AI Foundry (embeddings and chat).
  security_rule {
    name                                       = "Allow-Func-To-AIFoundry"
    priority                                   = 500
    direction                                  = "Inbound"
    access                                     = "Allow"
    protocol                                   = "Tcp"
    source_port_range                          = "*"
    destination_port_range                     = "443"
    source_address_prefixes                    = [var.func_subnet_cidr]
    destination_application_security_group_ids = [azurerm_application_security_group.this["ai-foundry"].id]
  }
  # The Function reaches Content Safety.
  security_rule {
    name                                       = "Allow-Func-To-ContentSafety"
    priority                                   = 600
    direction                                  = "Inbound"
    access                                     = "Allow"
    protocol                                   = "Tcp"
    source_port_range                          = "*"
    destination_port_range                     = "443"
    source_address_prefixes                    = [var.func_subnet_cidr]
    destination_application_security_group_ids = [azurerm_application_security_group.this["content-safety"].id]
  }
  # Container Apps and AKS reach Key Vault (certificates and secrets).
  security_rule {
    name                                       = "Allow-Apps-To-KeyVault"
    priority                                   = 700
    direction                                  = "Inbound"
    access                                     = "Allow"
    protocol                                   = "Tcp"
    source_port_range                          = "*"
    destination_port_range                     = "443"
    source_address_prefixes                    = [var.containerapps_subnet_cidr, var.aks_subnet_cidr]
    destination_application_security_group_ids = [azurerm_application_security_group.this["keyvault"].id]
  }
  security_rule {
    name                       = "Deny-All-Inbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  # Explicit outbound allow, equivalent to an NACL egress rule (without it only the default rule 65001 applies).
  security_rule {
    name                       = "Allow-All-Outbound"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# The containerapps and aks_virtual_nodes subnets are managed together with the other layers.
resource "azurerm_network_security_group" "containerapps" {
  name                = "nsg-app1-snet-containerapps"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = local.tags

  security_rule {
    name                       = "Allow-AzureLoadBalancer"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }
  # The Container Apps Environment is internal-only: all real inbound traffic goes through
  # snet-appgw, never directly to this subnet.
  security_rule {
    name                       = "Allow-AppGateway-To-Edge-Proxy"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["80", "443", "31080", "31443"]
    source_address_prefix      = var.appgw_subnet_cidr
    destination_address_prefix = "*"
  }
  # Application Gateway has its own rule above.
  security_rule {
    name                       = "Allow-Intra-Subnet"
    priority                   = 300
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefixes    = [var.containerapps_subnet_cidr]
    destination_address_prefix = "VirtualNetwork"
  }
  security_rule {
    name                       = "Deny-All-Inbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  # Explicit outbound allow, equivalent to an NACL egress rule (without it only the default rule 65001 applies).
  security_rule {
    name                       = "Allow-All-Outbound"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_security_group" "aks_virtual_nodes" {
  name                = "nsg-app1-snet-aks-virtual-nodes"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = local.tags

  # Only AKS and the subnet itself.
  security_rule {
    name                       = "Allow-AKS-And-Intra-Subnet"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefixes    = [var.aks_subnet_cidr, var.aks_virtual_nodes_subnet_cidr]
    destination_address_prefix = "VirtualNetwork"
  }
  security_rule {
    name                       = "Deny-All-Inbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  # Explicit outbound allow, equivalent to an NACL egress rule (without it only the default rule 65001 applies).
  security_rule {
    name                       = "Allow-All-Outbound"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Outbound VNet-integration subnet for the Function App (Flex Consumption). A subnet
# admits a single delegation, so it cannot be shared with privatelink or appgw. Same
# minimal pattern as aks_virtual_nodes: a delegated subnet with no inbound traffic
# initiated from outside the VNet.
resource "azurerm_network_security_group" "func" {
  name                = "nsg-app1-snet-func"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = local.tags

  # Outbound-integration subnet: nothing in the VNet should initiate traffic to it.
  security_rule {
    name                       = "Allow-Intra-Subnet"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefixes    = [var.func_subnet_cidr]
    destination_address_prefix = "VirtualNetwork"
  }
  security_rule {
    name                       = "Deny-All-Inbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  # Explicit outbound allow, equivalent to an NACL egress rule (without it only the default rule 65001 applies).
  security_rule {
    name                       = "Allow-All-Outbound"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# API Management (Developer tier) in VNet External mode: the gateway is public and
# reaches the private backends (Function App through a Private Endpoint). The APIM
# subnet cannot have a delegation (Microsoft docs: "shouldn't have any delegations
# enabled") and requires an NSG with these minimum inbound rules. Outbound (Storage,
# SQL, Key Vault, Azure Monitor, Entra ID) is covered by the explicit allow below.
#
# No Deny-All-Inbound on purpose (unlike the other NSGs in this file): an explicit
# deny at 4096 overrides Azure's default AllowVnetInBound / AllowAzureLoadBalancerInBound
# rules, which the APIM platform needs (internal load balancer health probes and
# node-to-node traffic); activation failed with the deny in place. Internet stays
# blocked by the default DenyAllInbound (65500) except for 443, allowed above.
resource "azurerm_network_security_group" "apim" {
  name                = "nsg-app1-snet-apim"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = local.tags

  security_rule {
    name                       = "Allow-Internet-HTTPS"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "Internet"
    destination_address_prefix = "VirtualNetwork"
  }
  security_rule {
    name                       = "Allow-ApiManagement-Management"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3443"
    source_address_prefix      = "ApiManagement"
    destination_address_prefix = "VirtualNetwork"
  }
  # Explicit outbound allow, equivalent to an NACL egress rule (without it only the default rule 65001 applies).
  security_rule {
    name                       = "Allow-All-Outbound"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# ============================================================================
# Route tables - only where the default Azure routing must be overridden.
# public/appgw/apim: direct internet (these are the INBOUND subnets).
# data: no internet (0/0 -> None). The rest have no UDR and learn the 0/0 route
# from the Virtual WAN hub (bgp_route_propagation_enabled = true).
# ============================================================================

resource "azurerm_route_table" "public" {
  name                          = "rt-app1-public"
  location                      = var.location
  resource_group_name           = var.resource_group_name
  bgp_route_propagation_enabled = true
  tags                          = local.tags

  route {
    name           = "to-internet"
    address_prefix = "0.0.0.0/0"
    next_hop_type  = "Internet"
  }
}

resource "azurerm_route_table" "appgw" {
  name                          = "rt-app1-appgw"
  location                      = var.location
  resource_group_name           = var.resource_group_name
  bgp_route_propagation_enabled = false # Application Gateway v2 exige 0.0.0.0/0 -> Internet y no admite rutas de gateway
  tags                          = local.tags

  route {
    name           = "to-internet"
    address_prefix = "0.0.0.0/0"
    next_hop_type  = "Internet"
  }
}

resource "azurerm_route_table" "apim" {
  name                          = "rt-app1-apim"
  location                      = var.location
  resource_group_name           = var.resource_group_name
  bgp_route_propagation_enabled = false # public APIM gateway: the reply must leave where the request entered
  tags                          = local.tags

  route {
    name           = "to-internet"
    address_prefix = "0.0.0.0/0"
    next_hop_type  = "Internet"
  }
}

resource "azurerm_route_table" "app" {
  name                          = "rt-app1-app"
  location                      = var.location
  resource_group_name           = var.resource_group_name
  bgp_route_propagation_enabled = true
  tags                          = local.tags
}

resource "azurerm_route_table" "data" {
  name                          = "rt-app1-data"
  location                      = var.location
  resource_group_name           = var.resource_group_name
  bgp_route_propagation_enabled = false
  tags                          = local.tags

  route {
    name           = "block-internet"
    address_prefix = "0.0.0.0/0"
    next_hop_type  = "None"
  }
}

resource "azurerm_route_table" "aks" {
  name                          = "rt-app1-aks"
  location                      = var.location
  resource_group_name           = var.resource_group_name
  bgp_route_propagation_enabled = true
  tags                          = local.tags
}

resource "azurerm_route_table" "containerapps" {
  name                          = "rt-app1-containerapps"
  location                      = var.location
  resource_group_name           = var.resource_group_name
  bgp_route_propagation_enabled = true
  tags                          = local.tags
}

# ============================================================================
# VNet + subnets via Azure Verified Module
# ============================================================================

module "vnet" {
  #checkov:skip=CKV_TF_1:Pinned by semver from the Terraform Registry (not a movable git tag) - official Azure Verified Module published by Microsoft; versions are immutable once published.
  source  = "Azure/avm-res-network-virtualnetwork/azurerm"
  version = "0.22.2"

  name          = var.vnet_name
  location      = var.location
  parent_id     = data.azurerm_resource_group.this.id
  address_space = var.vnet_address_space
  tags          = local.tags

  enable_telemetry = false

  dns_servers = var.app1_dns_via_firewall ? { dns_servers = [azurerm_firewall.egress.ip_configuration[0].private_ip_address] } : null

  diagnostic_settings = {
    sendToLogAnalytics = {
      workspace_resource_id = azurerm_log_analytics_workspace.this.id
    }
  }

  subnets = {
    public = {
      name                            = "snet-public"
      address_prefixes                = [var.public_subnet_cidr]
      default_outbound_access_enabled = true # ya tiene ruta explicita a Internet via rt-public
      network_security_group          = { id = azurerm_network_security_group.public.id }
      route_table                     = { id = azurerm_route_table.public.id }
    }
    appgw = {
      name                            = "snet-appgw"
      address_prefixes                = [var.appgw_subnet_cidr]
      default_outbound_access_enabled = true # INBOUND subnet: direct internet egress through rt-app1-appgw
      network_security_group          = { id = azurerm_network_security_group.appgw.id }
      route_table                     = { id = azurerm_route_table.appgw.id }
    }
    app = {
      name                            = "snet-app"
      address_prefixes                = [var.app_subnet_cidr]
      default_outbound_access_enabled = false # private: internet egress is ONLY the 0.0.0.0/0 route from the Virtual WAN hub
      network_security_group          = { id = azurerm_network_security_group.private.id }
      route_table                     = { id = azurerm_route_table.app.id }
    }
    data = {
      name                            = "snet-data"
      address_prefixes                = [var.data_subnet_cidr]
      default_outbound_access_enabled = false # private: no implicit egress, in addition to the block-internet route (defense in depth)
      network_security_group          = { id = azurerm_network_security_group.data.id }
      route_table                     = { id = azurerm_route_table.data.id }
    }
    aks = {
      name                            = "snet-aks"
      address_prefixes                = [var.aks_subnet_cidr]
      default_outbound_access_enabled = false # private: internet egress is ONLY the 0.0.0.0/0 route from the Virtual WAN hub
      network_security_group          = { id = azurerm_network_security_group.aks.id }
      route_table                     = { id = azurerm_route_table.aks.id }
    }
    privatelink = {
      name                              = "snet-privatelink"
      address_prefixes                  = [var.privatelink_subnet_cidr]
      default_outbound_access_enabled   = false # private: only hosts Private Endpoints, needs no egress
      network_security_group            = { id = azurerm_network_security_group.privatelink.id }
      private_endpoint_network_policies = "NetworkSecurityGroupEnabled" # the subnet NSG applies to the NIC of each Private Endpoint (it would not with "Disabled")
    }
    containerapps = {
      name                            = "snet-containerapps"
      address_prefixes                = [var.containerapps_subnet_cidr]
      default_outbound_access_enabled = true
      network_security_group          = { id = azurerm_network_security_group.containerapps.id }
      route_table                     = { id = azurerm_route_table.containerapps.id }
      delegations = [{
        name = "containerapps-delegation"
        service_delegation = {
          name = "Microsoft.App/environments"
        }
      }]
    }
    aks_virtual_nodes = {
      name                            = "snet-aks-virtual-nodes"
      address_prefixes                = [var.aks_virtual_nodes_subnet_cidr]
      default_outbound_access_enabled = true
      network_security_group          = { id = azurerm_network_security_group.aks_virtual_nodes.id }
      delegations = [{
        name = "aciDelegation"
        service_delegation = {
          name = "Microsoft.ContainerInstance/containerGroups"
        }
      }]
    }
    func = {
      name                            = "snet-func"
      address_prefixes                = [var.func_subnet_cidr]
      default_outbound_access_enabled = true
      network_security_group          = { id = azurerm_network_security_group.func.id }
      delegations = [{
        name = "funcDelegation"
        service_delegation = {
          name = "Microsoft.App/environments"
        }
      }]
    }
    apim = {
      name                            = "snet-apim"
      address_prefixes                = [var.apim_subnet_cidr]
      default_outbound_access_enabled = true
      network_security_group          = { id = azurerm_network_security_group.apim.id }
      route_table                     = { id = azurerm_route_table.apim.id }
    }
  }
}
