# ============================================================================
# VMs de prueba en snet-app (subnet privada: default_outbound_access = false,
# sin IP publica), UNA POR ZONA de disponibilidad (var.test_vm_zones). Las
# subnets de Azure abarcan todas las zonas, asi que ambas comparten subnet. Si puede salir a internet, lo hace SOLO por
# app1 -> hub -> firewall -> NAT Gateway. Se prueba sin SSH con
# `az vm run-command invoke` (ver README). La clave SSH es desechable: solo
# existe para cumplir el requisito de autenticacion de la VM; nadie la usa.
# ============================================================================

resource "tls_private_key" "test_vm" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "azurerm_network_interface" "test_vm" {
  for_each = toset(var.test_vm_zones)

  name                = "nic-vm-app1-test-z${each.key}"
  location            = var.location
  resource_group_name = var.resource_group_name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = module.vnet.subnets["app"].resource_id
    private_ip_address_allocation = "Dynamic"
  }

  tags = local.tags
}

resource "azurerm_linux_virtual_machine" "test" {
  #checkov:skip=CKV_AZURE_179:VM de prueba efimera (horas); el agente de extensiones no hace falta mas alla de run-command.
  #checkov:skip=CKV_AZURE_50:Se usa run-command (extension de plataforma) para probar la salida.
  for_each = toset(var.test_vm_zones)

  name                            = "vm-app1-test-z${each.key}"
  zone                            = each.key
  location                        = var.location
  resource_group_name             = var.resource_group_name
  size                            = var.test_vm_size
  admin_username                  = "azureuser"
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.test_vm[each.key].id]

  admin_ssh_key {
    username   = "azureuser"
    public_key = tls_private_key.test_vm.public_key_openssh
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  tags = local.tags

  # Sin la conexion al hub la subnet privada no tiene salida a internet.
  depends_on = [module.app1_connection]
}
