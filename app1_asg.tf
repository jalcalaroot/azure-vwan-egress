# Application Security Groups, one per service (named asg-app1-<service>).
#
# An ASG groups the NICs of one service so NSG rules talk about roles instead of
# IP ranges. They are used as DESTINATION: the main callers (APIM, Function,
# Container Apps) cannot be ASG members, so the SOURCE of those rules remains the
# CIDR of their subnet.
#
# A resource that is NOT associated with its ASG is not reached by the rules that
# target that ASG, and its traffic is silently blocked. Consumers must associate
# their Private Endpoints / node pools with the IDs of the
# `application_security_group_ids` output.
#
# Without ASG (they cannot belong to one): API Management, Function App outbound
# integration, Container Apps, Application Gateway, NAT Gateway and Application
# Insights.

locals {
  application_security_groups = {
    keyvault       = "Private Endpoint de Key Vault"
    cosmos         = "Private Endpoint de Cosmos DB"
    storage        = "Private Endpoints de storage (blob, dfs, cola, tabla)"
    function       = "Private Endpoint de la Function App"
    ai-foundry     = "Private Endpoint de AI Foundry"
    content-safety = "Private Endpoint de Content Safety"
    aks            = "Nodos de AKS (definido; sin reglas por ahora: un solo node pool)"
  }
}

resource "azurerm_application_security_group" "this" {
  for_each = local.application_security_groups

  name                = "asg-app1-${each.key}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = merge(local.tags, { Purpose = each.value })
}
