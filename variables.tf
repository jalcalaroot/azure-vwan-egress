variable "subscription_id" {
  description = "Subscription ID de Azure. Sin default: pasarlo via TF_VAR_subscription_id o un .tfvars gitignoreado."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group existente donde se despliega (este proyecto no lo crea, igual que el resto de la cuenta)."
  type        = string
  default     = "jalcalaroot"
}

variable "location" {
  description = "Region de Azure. Debe ser la misma de los spokes (el trafico spoke-hub-egress no debe cruzar regiones) y soportar NAT Gateway StandardV2."
  type        = string
  default     = "eastus"
}

variable "owner" {
  description = "Tag Owner"
  type        = string
  default     = "johan"
}

variable "environment" {
  description = "Tag Environment"
  type        = string
  default     = "dev"
}

variable "tags" {
  description = "Tags extra a mergear con las base."
  type        = map(string)
  default     = {}
}

# --------------------------------------------------------------------------
# Plan de direccionamiento (IPAM). Los spokes NO pueden solaparse entre si ni
# con el hub: Virtual WAN no enruta prefijos duplicados. Hoy azure-virtual-network
# usa 10.0.0.0/16; cada VNet nueva toma el siguiente /16 (10.1, 10.2, ...).
# --------------------------------------------------------------------------

variable "hub_address_prefix" {
  description = "Prefijo del virtual hub (Microsoft lo gestiona). Minimo /24 y no puede solaparse con ningun spoke."
  type        = string
  default     = "10.250.0.0/23"
}

variable "egress_vnet_address_space" {
  description = "Address space de la VNet de salida (solo contiene AzureFirewallSubnet)."
  type        = string
  default     = "10.251.0.0/24"
}

variable "egress_firewall_subnet_cidr" {
  description = "CIDR de AzureFirewallSubnet. El nombre es obligatorio y el tamano minimo es /26."
  type        = string
  default     = "10.251.0.0/26"
}

variable "spoke_address_space" {
  description = "Rango agregado desde el que se aceptan origenes en el firewall. Debe cubrir todas las VNets de aplicacion (10.0.0.0/16, 10.1.0.0/16, ...)."
  type        = string
  default     = "10.0.0.0/13"
}

variable "block_private_destinations" {
  description = "true: el firewall niega destinos RFC1918 (los spokes solo salen a internet; defensa en profundidad sobre el aislamiento por rutas). Ponerlo en false cuando haya conectividad hibrida (VPN/ExpressRoute) que deba pasar por el firewall."
  type        = bool
  default     = true
}

variable "log_analytics_retention_days" {
  description = "Retencion de logs del firewall"
  type        = number
  default     = 30
}

variable "test_vm_size" {
  description = "Tamano de la VM de prueba en app1. B1s/B2s (x86) no estan disponibles en la suscripcion de la cuenta (NotAvailableForSubscription); D2as_v4 si, con cuota."
  type        = string
  default     = "Standard_D2as_v4"
}
