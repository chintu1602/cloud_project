# ============================================================
# Module Composition — Wires all modules together
# ============================================================

locals {
  name_prefix = "${var.project_name}-${var.environment}"
  common_tags = merge(var.tags, {
    Environment = var.environment
  })
}

# ────────────────────────────────────────────────────────────
# 1. Resource Group
# ────────────────────────────────────────────────────────────

module "resource_group" {
  source   = "./modules/resource_group"
  name     = "${local.name_prefix}-rg"
  location = var.location
  tags     = local.common_tags
}

# ────────────────────────────────────────────────────────────
# 2. Virtual Network
# ────────────────────────────────────────────────────────────

module "vnet" {
  source              = "./modules/vnet"
  name                = "${local.name_prefix}-vnet"
  resource_group_name = module.resource_group.name
  location            = var.location
  tags                = local.common_tags
}

# ────────────────────────────────────────────────────────────
# 3. Key Vault
# ────────────────────────────────────────────────────────────

module "key_vault" {
  source              = "./modules/key_vault"
  name                = "${var.project_name}${var.environment}kv"
  resource_group_name = module.resource_group.name
  location            = var.location
  tags                = local.common_tags
  secrets = {
    "jwt-secret-key"      = random_password.jwt_secret.result
    "db-password"         = random_password.db_password.result
    "entra-client-secret" = var.entra_client_secret
    "smtp-password"       = var.smtp_password
  }
}

# ────────────────────────────────────────────────────────────
# 4. PostgreSQL Flexible Server
# ────────────────────────────────────────────────────────────

module "postgresql" {
  source              = "./modules/postgresql"
  name                = "${local.name_prefix}-pgdb"
  resource_group_name = module.resource_group.name
  location            = var.location
  sku_name            = var.postgres_sku
  admin_password      = random_password.db_password.result
  delegated_subnet_id = module.vnet.db_subnet_id
  private_dns_zone_id = module.vnet.postgres_dns_zone_id
  tags                = local.common_tags
}

# ────────────────────────────────────────────────────────────
# 5. Storage Account (Blob)
# ────────────────────────────────────────────────────────────

module "storage" {
  source              = "./modules/storage"
  name                = "${var.project_name}${var.environment}sa"
  resource_group_name = module.resource_group.name
  location            = var.location
  container_name      = "nutriai-documents"
  tags                = local.common_tags
}

# ────────────────────────────────────────────────────────────
# 6. Container Registry
# ────────────────────────────────────────────────────────────

module "container_registry" {
  source              = "./modules/container_registry"
  name                = "${var.project_name}${var.environment}acr"
  resource_group_name = module.resource_group.name
  location            = var.location
  tags                = local.common_tags
}

# ────────────────────────────────────────────────────────────
# 7. App Service Plan (shared by frontend + backend)
# ────────────────────────────────────────────────────────────

module "app_service_plan" {
  source              = "./modules/app_service_plan"
  name                = "${local.name_prefix}-asp"
  resource_group_name = module.resource_group.name
  location            = var.location
  sku_name            = var.app_service_sku
  tags                = local.common_tags
}

# ────────────────────────────────────────────────────────────
# 8. Backend App Service
# ────────────────────────────────────────────────────────────

module "app_service" {
  source                     = "./modules/app_service"
  name                       = "${local.name_prefix}-backend"
  resource_group_name        = module.resource_group.name
  location                   = var.location
  app_service_plan_id        = module.app_service_plan.id
  acr_login_server           = module.container_registry.login_server
  acr_admin_username         = module.container_registry.admin_username
  acr_admin_password         = module.container_registry.admin_password
  vnet_integration_subnet_id = module.vnet.backend_subnet_id
  tags                       = local.common_tags
  app_settings = {
    DATABASE_URL                          = module.postgresql.connection_string
    JWT_SECRET_KEY                        = random_password.jwt_secret.result
    AZURE_STORAGE_CONNECTION_STRING       = module.storage.connection_string
    AZURE_STORAGE_CONTAINER_NAME          = "nutriai-documents"
    AZURE_OPENAI_ENDPOINT                 = module.openai.endpoint
    AZURE_OPENAI_KEY                      = module.openai.key
    AZURE_OPENAI_DEPLOYMENT_NAME          = var.openai_model_deployment
    AZURE_SERVICE_BUS_CONNECTION_STRING    = module.service_bus.connection_string
    AZURE_SERVICE_BUS_TOPIC_NAME          = "meal-reminders"
    AZURE_DOCUMENT_INTELLIGENCE_ENDPOINT  = var.document_intelligence_endpoint
    AZURE_DOCUMENT_INTELLIGENCE_KEY       = var.document_intelligence_key
    ENTRA_CLIENT_ID                       = var.entra_client_id
    ENTRA_CLIENT_SECRET                   = var.entra_client_secret
    ENTRA_TENANT_ID                       = var.entra_tenant_id
    APPLICATIONINSIGHTS_CONNECTION_STRING = module.monitoring.appinsights_connection_string
    SMTP_HOST                             = var.smtp_host
    SMTP_PORT                             = tostring(var.smtp_port)
    SMTP_USERNAME                         = var.smtp_username
    SMTP_PASSWORD                         = var.smtp_password
    APP_URL                               = "https://${local.name_prefix}-frontend.azurewebsites.net"
  }
}

# ────────────────────────────────────────────────────────────
# 9. Frontend App Service (Nginx)
# ────────────────────────────────────────────────────────────

module "frontend_app_service" {
  source                     = "./modules/frontend_app_service"
  name                       = "${local.name_prefix}-frontend"
  resource_group_name        = module.resource_group.name
  location                   = var.location
  app_service_plan_id        = module.app_service_plan.id
  acr_login_server           = module.container_registry.login_server
  acr_admin_username         = module.container_registry.admin_username
  acr_admin_password         = module.container_registry.admin_password
  vnet_integration_subnet_id = module.vnet.frontend_subnet_id
  backend_url                = "https://${module.app_service.default_hostname}"
  tags                       = local.common_tags
}

# ────────────────────────────────────────────────────────────
# 10. Application Gateway (path-based routing)
# ────────────────────────────────────────────────────────────

module "application_gateway" {
  source              = "./modules/application_gateway"
  name                = "${local.name_prefix}-appgw"
  resource_group_name = module.resource_group.name
  location            = var.location
  subnet_id           = module.vnet.appgw_subnet_id
  backend_fqdn        = module.app_service.default_hostname
  frontend_fqdn       = module.frontend_app_service.default_hostname
  sku_name            = var.appgw_sku_name
  sku_tier            = var.appgw_sku_tier
  capacity            = var.appgw_capacity
  tags                = local.common_tags
}

# ────────────────────────────────────────────────────────────
# 11. Azure OpenAI
# ────────────────────────────────────────────────────────────

module "openai" {
  source              = "./modules/openai"
  name                = "${local.name_prefix}-openai"
  resource_group_name = module.resource_group.name
  location            = var.location
  deployment_name     = var.openai_model_deployment
  tags                = local.common_tags
}

# ────────────────────────────────────────────────────────────
# 12. Service Bus
# ────────────────────────────────────────────────────────────

module "service_bus" {
  source              = "./modules/service_bus"
  name                = "${local.name_prefix}-sb"
  resource_group_name = module.resource_group.name
  location            = var.location
  topic_name          = "meal-reminders"
  subscription_name   = "email-sender"
  tags                = local.common_tags
}

# ────────────────────────────────────────────────────────────
# 13. Monitoring (Application Insights + Log Analytics)
# ────────────────────────────────────────────────────────────

module "monitoring" {
  source              = "./modules/monitoring"
  name                = "${local.name_prefix}-monitor"
  resource_group_name = module.resource_group.name
  location            = var.location
  tags                = local.common_tags
}

# ────────────────────────────────────────────────────────────
# 14. Alerts
# ────────────────────────────────────────────────────────────

module "alerts" {
  source              = "./modules/alerts"
  name                = "${local.name_prefix}-alerts"
  resource_group_name = module.resource_group.name
  app_service_id      = module.app_service.id
  appinsights_id      = module.monitoring.appinsights_id
  action_group_email  = var.admin_email
  tags                = local.common_tags
}

# ────────────────────────────────────────────────────────────
# 15. Entra ID (App Registration)
# ────────────────────────────────────────────────────────────

module "entra_id" {
  source       = "./modules/entra_id"
  display_name = "NutriAI Health Portal (${var.environment})"
  redirect_uri = "https://${module.app_service.default_hostname}/auth/microsoft/callback"
}

# ============================================================
# Random Passwords
# ============================================================

resource "random_password" "jwt_secret" {
  length  = 64
  special = true
}

resource "random_password" "db_password" {
  length  = 32
  special = false
}
