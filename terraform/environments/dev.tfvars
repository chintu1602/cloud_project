# ============================================================
# NutriAI - Dev Environment
# Usage: terraform plan -var-file=environments/dev.tfvars
# ============================================================

environment     = "dev"
app_service_sku = "B1"
postgres_sku    = "B_Standard_B1ms"
appgw_capacity  = 1


tags = {
  Project     = "NutriAI"
  ManagedBy   = "Terraform"
  Application = "NutriAI Health Portal"
  Environment = "dev"
}
