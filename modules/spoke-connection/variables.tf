variable "name" {
  description = "Name of the connection (conn-<vnet>)"
  type        = string
}

variable "virtual_hub_id" {
  description = "virtual_hub_id output of the vwan-egress project"
  type        = string
}

variable "virtual_network_id" {
  description = "ID of the application VNet to connect. Its address space must not overlap any other spoke or the hub."
  type        = string
}

variable "route_table_spokes_id" {
  description = "route_table_spokes_id output of the vwan-egress project"
  type        = string
}

variable "route_table_egress_id" {
  description = "route_table_egress_id output of the vwan-egress project"
  type        = string
}
