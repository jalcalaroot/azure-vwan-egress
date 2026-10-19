# Variables de la VNet de aplicacion app1: mismas capas (subnets) que la VNet
# conocida de azure-virtual-network, con address space 10.1.0.0/16 para no
# solaparse con ninguna otra (ver docs/spoke-contract.md).

variable "vnet_name" {
  description = "Name of the Virtual Network"
  type        = string
  default     = "vnet-app1"
}

variable "vnet_address_space" {
  description = "Address space for the VNet"
  type        = list(string)
  default     = ["10.1.0.0/16"]
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.1.0.0/22"
}

variable "appgw_subnet_cidr" {
  description = "CIDR para la subnet dedicada de Application Gateway (unica, no una por AZ)"
  type        = string
  default     = "10.1.40.0/24"
}

variable "app_subnet_cidr" {
  description = "CIDR block for the app subnet"
  type        = string
  default     = "10.1.8.0/22"
}

variable "data_subnet_cidr" {
  description = "CIDR block for the data subnet"
  type        = string
  default     = "10.1.20.0/22"
}

variable "aks_subnet_cidr" {
  description = "CIDR para la subnet dedicada de AKS (unica, no una por AZ - HA se maneja via zones del node pool)"
  type        = string
  default     = "10.1.60.0/24"
}

variable "containerapps_subnet_cidr" {
  description = "CIDR para la subnet delegada a Microsoft.App/environments (azure-container-apps)"
  type        = string
  default     = "10.1.70.0/23"
}

variable "aks_virtual_nodes_subnet_cidr" {
  description = "CIDR para la subnet delegada a Microsoft.ContainerInstance/containerGroups (AKS Virtual Nodes, azure-aks-cluster)"
  type        = string
  default     = "10.1.72.0/24"
}

variable "func_subnet_cidr" {
  description = "CIDR para la subnet delegada a Microsoft.App/environments (VNet integration outbound de Function Apps en plan Flex Consumption - azure-agent-platform)"
  type        = string
  default     = "10.1.73.0/24"
}

variable "apim_subnet_cidr" {
  description = "CIDR para la subnet de API Management en modo VNet External (azure-agent-platform). Sin delegation - APIM la prohibe. Minimo /29, un /24 deja margen."
  type        = string
  default     = "10.1.74.0/24"
}

# Private Endpoints subnet (single, not zonal - shared across the VNet)
variable "privatelink_subnet_cidr" {
  description = "CIDR block for the shared Private Endpoints subnet"
  type        = string
  default     = "10.1.30.0/24"
}
