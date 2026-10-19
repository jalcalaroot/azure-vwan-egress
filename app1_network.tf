# VNet de aplicacion "app1": las MISMAS capas (10 subnets, NSG por subnet con
# salida abierta explicita, ASGs) que azure-virtual-network, con tres
# diferencias para usar la salida central de Virtual WAN:
#   1. No tiene NAT Gateway propio. Las subnets privadas (app, data, aks,
#      privatelink) mantienen default_outbound_access_enabled = false y salen
#      por la ruta 0.0.0.0/0 que aprenden del hub.
#   2. Las subnets por donde ENTRA trafico desde internet (public, appgw, apim)
#      llevan una route table 0.0.0.0/0 -> Internet para que la respuesta
#      salga simetrica por donde entro (y porque Application Gateway v2 lo exige).
#   3. Se conecta al hub con modules/spoke-connection (ver app1_connection.tf).
# Los recursos llevan el sufijo "app1" porque la cuenta usa un unico resource
# group compartido y los nombres no deben chocar con otras VNets.
#
# parent_id del modulo AVM quiere el ID del resource group, no el nombre.
data "azurerm_resource_group" "this" {
  name = var.resource_group_name
}

# Revision 2026-10-16 - segmentacion lateral: las reglas "Allow-VNet-Inbound"
# (origen VirtualNetwork = cualquier recurso de la VNet) se reemplazaron por
# origenes concretos. Se usan CIDR de subnet y no ASG porque cada subnet aloja
# un solo rol (el CIDR equivale al rol) y los llamadores principales (APIM,
# Function, Container Apps) no pueden pertenecer a un ASG. Si se quiere un
# modelo "tipo Security Group", el provider SI admite ASG en Private
# Endpoints y en los node pools de AKS (no en Container Apps, Function ni
# APIM). Los flujos permitidos son los previstos por el diseno; deben
# validarse al desplegar con los repos consumidores.
# ============================================================================
# Network Security Groups - una por subnet, mismas reglas que antes de esta
# migracion (nada cambia a nivel de seguridad real).
# ============================================================================

resource "azurerm_network_security_group" "public" {
  #checkov:skip=CKV_AZURE_160:80 se mantiene por diseño para el redirect HTTP->HTTPS que hace App Gateway - el trafico plano no llega a los backends, App Gateway lo redirige antes.
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
  # Salida abierta de forma explicita (decision del proyecto): equivale a la
  # regla de salida de una NACL; antes dependia de la regla por defecto 65001.
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
  #checkov:skip=CKV_AZURE_160:80 se mantiene por diseño para el redirect HTTP->HTTPS que hace App Gateway - mismo motivo que nsg-snet-public.
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
  # Salida abierta de forma explicita (decision del proyecto): equivale a la
  # regla de salida de una NACL; antes dependia de la regla por defecto 65001.
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
  # Antes: Allow-VNet-Inbound (toda la VNet). Ahora solo la propia subnet; los llamadores externos entran por Allow-From-Public-Subnets.
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
  # Salida abierta de forma explicita (decision del proyecto): equivale a la
  # regla de salida de una NACL; antes dependia de la regla por defecto 65001.
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
  # Salida abierta de forma explicita (decision del proyecto): equivale a la
  # regla de salida de una NACL; antes dependia de la regla por defecto 65001.
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
  # Antes: Allow-VNet-Inbound. Ahora: nodos, nodos virtuales (ACI) y App Gateway (AGIC).
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
  # Salida abierta de forma explicita (decision del proyecto): equivale a la
  # regla de salida de una NACL; antes dependia de la regla por defecto 65001.
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
  # Revision 2026-10-16: con las politicas de red de la subnet activadas este
  # NSG se aplica a la NIC de cada Private Endpoint. Una regla por servicio,
  # con el ASG del servicio como destino (443). Prioridades con saltos de 100.
  # La regla 100 de arriba (app y data hacia cualquier endpoint) se mantiene
  # como respaldo del nivel de aplicacion y de datos.
  # APIM llega solo a la Function App.
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
  # La Function llega a Cosmos DB.
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
  # La Function llega al storage (host y estado de Durable Functions).
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
  # La Function llega a AI Foundry (embeddings y chat).
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
  # La Function llega a Content Safety.
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
  # Container Apps y AKS llegan a Key Vault (certificados y secretos).
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
  # Salida abierta de forma explicita (decision del proyecto): equivale a la
  # regla de salida de una NACL; antes dependia de la regla por defecto 65001.
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

# containerapps/aks_virtual_nodes: hasta 2026-09-29 vivian como bolt-ons
# fuera de este modulo (en el repo consumidor), para no forzar un bump de
# version del modulo por una necesidad puntual de un solo proyecto. Al
# convertir este repo de "modulo versionado por git tag" a proyecto
# standalone (ver CLAUDE.md), esa razon dejo de aplicar - un cambio aca ya
# no tiene otros consumidores a los que romper, asi que se unificaron en el
# mismo mapa subnets de abajo, igual que public/appgw/app/data/aks/privatelink.
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
  # Container Apps Environment (azure-container-apps) es internal-only a
  # proposito - todo el trafico entrante real pasa por snet-appgw, nunca
  # directo a este subnet.
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
  # Antes: Allow-VNet-Inbound. App Gateway ya tiene su regla propia arriba.
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
  # Salida abierta de forma explicita (decision del proyecto): equivale a la
  # regla de salida de una NACL; antes dependia de la regla por defecto 65001.
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

  # Antes: Allow-VNet-Inbound. Ahora solo AKS y la propia subnet.
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
  # Salida abierta de forma explicita (decision del proyecto): equivale a la
  # regla de salida de una NACL; antes dependia de la regla por defecto 65001.
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

# Agregada 2026-09-30: ningun subnet existente hasta ahora tenia delegation
# a Microsoft.App/environments (corregido 2026-10-03, ver abajo) - gap real encontrado escribiendo
# azure-agent-platform (Function App Flex Consumption, VNet integration
# outbound), cada subnet solo admite UNA delegation asi que ni privatelink
# ni appgw sirven. Mismo patron minimo que aks_virtual_nodes (subnet
# delegada, sin trafico inbound iniciado desde afuera de la VNet).
resource "azurerm_network_security_group" "func" {
  name                = "nsg-app1-snet-func"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = local.tags

  # Antes: Allow-VNet-Inbound. La subnet es de integracion saliente: nadie de la VNet debe iniciar trafico hacia ella.
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
  # Salida abierta de forma explicita (decision del proyecto): equivale a la
  # regla de salida de una NACL; antes dependia de la regla por defecto 65001.
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

# Agregada 2026-10-03 para API Management (tier Developer) en modo VNet
# External (azure-agent-platform): el gateway queda publico y llega a los
# backends privados (Function App por Private Endpoint). La subnet de APIM
# NO puede tener delegation (doc de Microsoft: "shouldn't have any
# delegations enabled") y exige un NSG con estas reglas minimas de entrada.
# El outbound (Storage, SQL, Key Vault, Azure Monitor, Entra ID) lo cubre el
# allow-all por defecto de Azure, mismo criterio que el resto de NSGs de este
# archivo, que no definen reglas de salida.
#
# SIN Deny-All-Inbound a proposito (a diferencia del resto de NSGs de este
# archivo): un deny explicito en 4096 anula las reglas por defecto de Azure
# AllowVnetInBound/AllowAzureLoadBalancerInBound, que la plataforma de APIM
# necesita (health probes del load balancer interno, trafico entre nodos).
# Dos activaciones seguidas fallaron con ActivationFailed con ese deny
# puesto, aunque la doc dice que AzureLoadBalancer:6390 "no se requiere" en
# Developer. Internet sigue bloqueado por la regla por defecto
# DenyAllInbound (65500) salvo el 443 permitido arriba.
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
  # Salida abierta de forma explicita (decision del proyecto): equivale a la
  # regla de salida de una NACL; antes dependia de la regla por defecto 65001.
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
# Route tables - solo donde hace falta desviar del ruteo default de Azure.
# public/appgw/apim: salida directa a Internet (son las subnets de ENTRADA).
# data: sin internet (0/0 -> None). El resto no lleva UDR y aprende el 0/0
# del hub (Virtual WAN) con bgp_route_propagation_enabled = true.
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
  bgp_route_propagation_enabled = false # gateway publico de APIM: la respuesta debe salir por donde entro
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
# VNet + subnets via Azure Verified Module.
# ============================================================================

module "vnet" {
  #checkov:skip=CKV_TF_1:pinned por version semver del Terraform Registry (no un git tag movible) - Azure Verified Module oficial, publicado por Microsoft, versiones inmutables una vez publicadas en el registry.
  source  = "Azure/avm-res-network-virtualnetwork/azurerm"
  version = "0.22.2"

  name          = var.vnet_name
  location      = var.location
  parent_id     = data.azurerm_resource_group.this.id
  address_space = var.vnet_address_space
  tags          = local.tags

  enable_telemetry = false

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
      default_outbound_access_enabled = true # subnet de ENTRADA: salida directa a Internet via rt-app1-appgw
      network_security_group          = { id = azurerm_network_security_group.appgw.id }
      route_table                     = { id = azurerm_route_table.appgw.id }
    }
    app = {
      name                            = "snet-app"
      address_prefixes                = [var.app_subnet_cidr]
      default_outbound_access_enabled = false # privada: la salida a internet es SOLO la ruta 0.0.0.0/0 del hub de Virtual WAN
      network_security_group          = { id = azurerm_network_security_group.private.id }
      route_table                     = { id = azurerm_route_table.app.id }
    }
    data = {
      name                            = "snet-data"
      address_prefixes                = [var.data_subnet_cidr]
      default_outbound_access_enabled = false # privada: sin salida implicita, ademas de la ruta block-internet (defensa en profundidad)
      network_security_group          = { id = azurerm_network_security_group.data.id }
      route_table                     = { id = azurerm_route_table.data.id }
    }
    aks = {
      name                            = "snet-aks"
      address_prefixes                = [var.aks_subnet_cidr]
      default_outbound_access_enabled = false # privada: la salida a internet es SOLO la ruta 0.0.0.0/0 del hub de Virtual WAN
      network_security_group          = { id = azurerm_network_security_group.aks.id }
      route_table                     = { id = azurerm_route_table.aks.id }
    }
    privatelink = {
      name                              = "snet-privatelink"
      address_prefixes                  = [var.privatelink_subnet_cidr]
      default_outbound_access_enabled   = false # privada: solo aloja Private Endpoints, no necesita salida
      network_security_group            = { id = azurerm_network_security_group.privatelink.id }
      private_endpoint_network_policies = "NetworkSecurityGroupEnabled" # el NSG de la subnet se aplica a la NIC de cada Private Endpoint (con "Disabled" no se aplicaba)
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
