output "virtual_hub_id" {
  description = "ID of the virtual hub. Spokes use it to connect (modules/spoke-connection)."
  value       = azurerm_virtual_hub.this.id
}

output "route_table_spokes_id" {
  description = "Route table that spokes ASSOCIATE with (it carries the 0.0.0.0/0 route)."
  value       = azurerm_virtual_hub_route_table.spokes.id
}

output "route_table_egress_id" {
  description = "Route table that spokes PROPAGATE their prefixes to."
  value       = azurerm_virtual_hub_route_table.egress.id
}

output "egress_public_ip" {
  description = "Outbound public IP of every spoke (the NAT Gateway IP). Use it for third-party allow-lists."
  value       = azurerm_public_ip.nat.ip_address
}

output "firewall_private_ip" {
  description = "Private IP of the firewall (next hop of the 0.0.0.0/0 route)."
  value       = azurerm_firewall.egress.ip_configuration[0].private_ip_address
}

output "app1_vnet_id" {
  description = "ID of the app1 application VNet"
  value       = module.vnet.resource_id
}

output "test_vm_names" {
  description = "Test VMs in app1 (no public IP, one per zone). Check them with az vm run-command."
  value       = { for z, vm in azurerm_linux_virtual_machine.test : z => vm.name }
}
