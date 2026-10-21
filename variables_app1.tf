# Variables for the app1 application VNet: the same layers (subnets) as
# azure-virtual-network, with address space 10.1.0.0/16 so it does not overlap
# with any other VNet (see docs/spoke-contract.md).

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
  description = "CIDR block for the dedicated Application Gateway subnet (a single subnet, not one per zone)"
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
  description = "CIDR block for the dedicated AKS subnet (a single subnet, not one per zone - high availability comes from the node pool zones)"
  type        = string
  default     = "10.1.60.0/24"
}

variable "containerapps_subnet_cidr" {
  description = "CIDR block for the subnet delegated to Microsoft.App/environments (Container Apps)"
  type        = string
  default     = "10.1.70.0/23"
}

variable "aks_virtual_nodes_subnet_cidr" {
  description = "CIDR block for the subnet delegated to Microsoft.ContainerInstance/containerGroups (AKS virtual nodes)"
  type        = string
  default     = "10.1.72.0/24"
}

variable "func_subnet_cidr" {
  description = "CIDR block for the subnet delegated to Microsoft.App/environments (outbound VNet integration of Flex Consumption Function Apps)"
  type        = string
  default     = "10.1.73.0/24"
}

variable "apim_subnet_cidr" {
  description = "CIDR block for the API Management subnet in VNet External mode. No delegation (APIM forbids it). Minimum /29; a /24 leaves headroom."
  type        = string
  default     = "10.1.74.0/24"
}

# Private Endpoints subnet (single, not zonal - shared across the VNet)
variable "privatelink_subnet_cidr" {
  description = "CIDR block for the shared Private Endpoints subnet"
  type        = string
  default     = "10.1.30.0/24"
}
