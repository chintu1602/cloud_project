# ============================================================
# NutriAI - Prod Environment
# Usage: terraform plan -var-file=environments/prod.tfvars
# ============================================================

environment     = "prod"
app_service_sku = "P1v2"
postgres_sku    = "GP_Standard_D2s_v3"
appgw_capacity  = 2

admin_email = "admin@nutriai-health.com"

tags = {
  Project     = "NutriAI"
  ManagedBy   = "Terraform"
  Application = "NutriAI Health Portal"
  Environment = "prod"
}
