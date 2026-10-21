variable "subscription_id" {
  description = "Azure subscription ID. No default: pass it through TF_VAR_subscription_id or a git-ignored .tfvars file."
  type        = string
}

variable "resource_group_name" {
  description = "Existing resource group to deploy into (this project does not create it)."
  type        = string
  default     = "jalcalaroot"
}

variable "location" {
  description = "Azure region. Must match the spokes (spoke-hub-egress traffic must not cross regions) and support NAT Gateway StandardV2."
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
  description = "Extra tags merged with the base tags."
  type        = map(string)
  default     = {}
}

# --------------------------------------------------------------------------
# Address plan (IPAM). Spokes must not overlap each other or the hub: Virtual
# WAN does not route duplicate prefixes. Each application VNet takes the next
# /16 (10.1.0.0/16 for app1, 10.2.0.0/16 for the next one, ...).
# --------------------------------------------------------------------------

variable "hub_address_prefix" {
  description = "Address prefix of the virtual hub (managed by Microsoft). Minimum /24; must not overlap any spoke."
  type        = string
  default     = "10.250.0.0/23"
}

variable "egress_vnet_address_space" {
  description = "Address space of the egress VNet (it only contains AzureFirewallSubnet)."
  type        = string
  default     = "10.251.0.0/24"
}

variable "egress_firewall_subnet_cidr" {
  description = "CIDR block of AzureFirewallSubnet. The subnet name is mandatory and the minimum size is /26."
  type        = string
  default     = "10.251.0.0/26"
}

variable "spoke_address_space" {
  description = "Aggregate range accepted as source by the firewall rules. Must cover every application VNet (10.0.0.0/16, 10.1.0.0/16, ...)."
  type        = string
  default     = "10.0.0.0/13"
}

variable "block_private_destinations" {
  description = "true: the firewall denies RFC1918 destinations (spokes only reach the internet; defense in depth on top of route-based isolation). Set to false when hybrid connectivity (VPN/ExpressRoute) must pass through the firewall."
  type        = bool
  default     = true
}

variable "log_analytics_retention_days" {
  description = "Retention of the firewall logs, in days"
  type        = number
  default     = 30
}

variable "probe_vm_size" {
  description = "Size of the probe VMs in app1."
  type        = string
  default     = "Standard_D2as_v4"
}

variable "probe_vm_zones" {
  description = "Availability zones that get a probe VM in app1 (one VM per zone)."
  type        = list(string)
  default     = ["1", "2"]
}

variable "app1_dns_via_firewall" {
  description = "true: app1 uses the private IP of the firewall as DNS server (DNS proxy), so the firewall logs every DNS query. false: app1 keeps Azure DNS. Takes effect only when set at VNet creation: the VNet module (azapi) does not detect a change from no DNS servers to a value on an existing VNet. Note: Azure Firewall forwards to Azure DNS from vnet-egress, so Private DNS zones (privatelink.*) must also be linked to vnet-egress, or resolved through Azure DNS Private Resolver."
  type        = bool
  default     = false
}

variable "denied_web_categories" {
  description = "Web categories the firewall denies (HTTP/HTTPS); categorization is FQDN-based on the Standard tier. Empty = none. Names as listed by the Microsoft.Network/azureWebCategories API."
  type        = list(string)
  default     = ["ChildAbuseImages", "CriminalActivity", "IllegalSoftware"]
}
