output "virtual_hub_id" {
  description = "ID del virtual hub. Los spokes lo usan para conectarse (modulo modules/spoke-connection)."
  value       = azurerm_virtual_hub.this.id
}

output "route_table_spokes_id" {
  description = "Tabla de rutas a la que se ASOCIAN los spokes (recibe el 0.0.0.0/0)."
  value       = azurerm_virtual_hub_route_table.spokes.id
}

output "route_table_egress_id" {
  description = "Tabla de rutas hacia la que los spokes PROPAGAN sus prefijos."
  value       = azurerm_virtual_hub_route_table.egress.id
}

output "egress_public_ip" {
  description = "IP publica de salida de todos los spokes (la del NAT Gateway). Es la que se permite en listas de acceso de terceros."
  value       = azurerm_public_ip.nat.ip_address
}

output "firewall_private_ip" {
  description = "IP privada del firewall (siguiente salto del 0.0.0.0/0)."
  value       = azurerm_firewall.egress.ip_configuration[0].private_ip_address
}
