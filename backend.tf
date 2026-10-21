# Shared tfstate storage account of the subscription, with its own key (kept as
# "vwan-egress" from the original project name to preserve the existing state).
# use_azuread_auth = true: that storage account has shared_access_key_enabled = false.
terraform {
  backend "azurerm" {
    resource_group_name  = "jalcalaroot"
    storage_account_name = "sttfstatejalcalaroot"
    container_name       = "tfstate"
    key                  = "vwan-egress/terraform.tfstate"
    use_azuread_auth     = true
  }
}
