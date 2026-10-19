variable "name" {
  description = "Nombre de la conexion (conn-<vnet>)"
  type        = string
}

variable "virtual_hub_id" {
  description = "Output virtual_hub_id del proyecto vwan-egress"
  type        = string
}

variable "virtual_network_id" {
  description = "ID de la VNet de aplicacion a conectar. Su address space no debe solaparse con ningun otro spoke ni con el hub."
  type        = string
}

variable "route_table_spokes_id" {
  description = "Output route_table_spokes_id"
  type        = string
}

variable "route_table_egress_id" {
  description = "Output route_table_egress_id"
  type        = string
}
