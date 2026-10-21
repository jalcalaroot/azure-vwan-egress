# ============================================================================
# Test VMs in snet-app (private subnet: default_outbound_access = false, no
# public IP), ONE PER availability zone (var.test_vm_zones). Azure subnets span
# every zone, so all VMs share the subnet. Their internet access can only go
# through app1 -> hub -> firewall -> NAT Gateway. They are checked without SSH
# through `az vm run-command invoke` (see README). The SSH key is disposable:
# it exists only to satisfy the VM authentication requirement; nobody uses it.
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
  #checkov:skip=CKV_AZURE_179:Short-lived test VMs; the extension agent is only needed for run-command.
  #checkov:skip=CKV_AZURE_50:run-command (a platform extension) is used to test the egress.
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

  # Without the hub connection the private subnet has no internet access.
  depends_on = [module.app1_connection]
}
