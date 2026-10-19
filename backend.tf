# Mismo storage account de tfstate que el resto de la cuenta, key propio.
# use_azuread_auth = true: ese storage tiene shared_access_key_enabled = false.
terraform {
  backend "azurerm" {
    resource_group_name  = "jalcalaroot"
    storage_account_name = "sttfstatejalcalaroot"
    container_name       = "tfstate"
    key                  = "vwan-egress/terraform.tfstate"
    use_azuread_auth     = true
  }
}
