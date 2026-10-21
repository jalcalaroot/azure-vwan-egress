plugin "azurerm" {
  enabled = true
  version = "0.32.0" # check/update against the latest tflint-ruleset-azurerm release
  source  = "github.com/terraform-linters/tflint-ruleset-azurerm"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

# lifecycle { prevent_destroy } is a decision of the consumer, not of the module
# itself - it does not accept variables, so setting it here would force the
# protection even in disposable environments (dev/test). Each consuming project
# decides this in its own code.
rule "azurerm_resources_missing_prevent_destroy" {
  enabled = false
}
