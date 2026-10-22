# ============================================================================
# VNet flow logs for app1 and the egress VNet, and diagnostic settings for the
# app1 NSGs, the egress VNet and the public IP addresses. The firewall already logs every flow it decides on (AZFW* tables);
# the flow logs add per-VNet and per-subnet history, including traffic that
# never reaches the firewall (inside app1 and towards private endpoints).
# ============================================================================

# The regional Network Watcher is created by Azure the first time it is needed.
data "azurerm_network_watcher" "this" {
  name                = "NetworkWatcher_${var.location}"
  resource_group_name = "NetworkWatcherRG"
}

module "storage_flowlogs" {
  #checkov:skip=CKV_TF_1:Pinned by semver from the Terraform Registry (not a movable git tag) - official Azure Verified Module published by Microsoft; versions are immutable once published.
  #checkov:skip=CKV_AZURE_33:This storage account does not expose the Queue service, so the check does not apply.
  #checkov:skip=CKV_AZURE_206:LRS on purpose - these are non-critical operational logs, not business data.
  #checkov:skip=CKV2_AZURE_33:Flow logs do not support a Private Endpoint as destination; access is restricted with network rules and the AzureServices bypass instead.
  #checkov:skip=CKV2_AZURE_40:Network Watcher writes flow logs with a shared key, so Shared Key access cannot be disabled on this account.
  #checkov:skip=CKV2_AZURE_41:Direct consequence of the previous skip - this check requires Shared Key access to be disabled.
  #checkov:skip=CKV2_AZURE_1:A customer-managed key would add Key Vault operation costs for operational log data.
  source  = "Azure/avm-res-storage-storageaccount/azurerm"
  version = "0.10.0"

  name      = var.flow_logs_storage_account_name
  location  = var.location
  parent_id = data.azurerm_resource_group.this.id
  tags      = local.tags

  enable_telemetry = false

  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  public_network_access_enabled   = false
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = true # Network Watcher writes flow logs with a key/SAS

  network_rules = {
    default_action = "Deny"
    bypass         = ["AzureServices"]
  }

  blob_properties = {
    delete_retention_policy           = { days = 7 }
    container_delete_retention_policy = { days = 7 }
  }

  sas_policy = {
    expiration_period = "01.00:00:00"
    expiration_action = "Log"
  }
}

locals {
  flow_log_targets = {
    app1   = module.vnet.resource_id
    egress = azurerm_virtual_network.egress.id
  }
}

resource "azurerm_network_watcher_flow_log" "this" {
  #checkov:skip=CKV_AZURE_12:Retention defaults to 30 days, not more than 90 - cost-conscious default (more retention means more storage); raise it through var.flow_log_retention_days if needed.
  for_each = local.flow_log_targets

  name                 = "flowlog-vnet-${each.key}"
  network_watcher_name = data.azurerm_network_watcher.this.name
  resource_group_name  = data.azurerm_network_watcher.this.resource_group_name
  target_resource_id   = each.value
  storage_account_id   = module.storage_flowlogs.resource_id
  enabled              = true
  version              = 2

  retention_policy {
    enabled = true
    days    = var.flow_log_retention_days
  }

  traffic_analytics {
    enabled               = var.enable_traffic_analytics
    workspace_id          = azurerm_log_analytics_workspace.this.workspace_id
    workspace_region      = azurerm_log_analytics_workspace.this.location
    workspace_resource_id = azurerm_log_analytics_workspace.this.id
    interval_in_minutes   = 10
  }

  tags = local.tags
}

locals {
  app1_nsgs = {
    public           = azurerm_network_security_group.public.id
    appgw            = azurerm_network_security_group.appgw.id
    app              = azurerm_network_security_group.private.id
    data             = azurerm_network_security_group.data.id
    aks              = azurerm_network_security_group.aks.id
    privatelink      = azurerm_network_security_group.privatelink.id
    containerapps    = azurerm_network_security_group.containerapps.id
    aks_virtual_node = azurerm_network_security_group.aks_virtual_nodes.id
    func             = azurerm_network_security_group.func.id
    apim             = azurerm_network_security_group.apim.id
  }
}

resource "azurerm_monitor_diagnostic_setting" "app1_nsg" {
  for_each = local.app1_nsgs

  name                       = "diag-${each.key}"
  target_resource_id         = each.value
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category_group = "allLogs"
  }
}

# Egress VNet and public IP addresses (NAT Gateway and firewall). Their log and
# metric categories are exportable to Log Analytics (StandardV2 public IPs
# expose the same categories as Standard ones). NAT Gateway metrics, virtual
# hub metrics and private endpoint metrics are NOT exportable through
# diagnostic settings; they are available in Azure Monitor without configuration.
locals {
  network_diagnostics = {
    vnet-egress    = azurerm_virtual_network.egress.id
    pip-nat-egress = azurerm_public_ip.nat.id
    pip-fw-egress  = azurerm_public_ip.firewall.id
  }
}

resource "azurerm_monitor_diagnostic_setting" "network" {
  for_each = local.network_diagnostics

  name                       = "diag-${each.key}"
  target_resource_id         = each.value
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}
