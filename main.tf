locals {
  tags = merge(
    {
      Project     = "vwan-egress"
      Environment = var.environment
      Owner       = var.owner
      ManagedBy   = "terraform"
    },
    var.tags,
  )
}
