# Application Security Groups, uno por servicio (nombre: asg-<servicio>).
#
# Revision 2026-10-16. Un ASG agrupa las NIC de un mismo servicio para que las
# reglas de un NSG hablen de roles y no de rangos de IP. Se usan como DESTINO:
# los llamadores principales (APIM, Function, Container Apps) no pueden ser
# miembros de un ASG, asi que el ORIGEN de esas reglas sigue siendo el CIDR de
# su subnet.
#
# Si un recurso NO se asocia a su ASG, las reglas que apuntan a ese ASG no le
# llegan y su trafico queda bloqueado en silencio. Los repos consumidores deben
# asociar sus Private Endpoints / node pools con los IDs del output
# `application_security_group_ids`.
#
# Sin ASG (no pueden pertenecer a uno): API Management, integracion de salida
# de la Function App, Container Apps, Application Gateway, NAT Gateway y
# Application Insights.

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
