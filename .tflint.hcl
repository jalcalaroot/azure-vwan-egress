plugin "azurerm" {
  enabled = true
  version = "0.32.0" # verificar/actualizar contra la última release de tflint-ruleset-azurerm
  source  = "github.com/terraform-linters/tflint-ruleset-azurerm"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

# lifecycle { prevent_destroy } es una decisión del consumidor del módulo, no
# del módulo en sí - no acepta variables, así que fijarlo acá forzaría la
# protección incluso en entornos descartables (dev/test). Cada proyecto
# consumidor decide esto a nivel de su propio código.
rule "azurerm_resources_missing_prevent_destroy" {
  enabled = false
}
