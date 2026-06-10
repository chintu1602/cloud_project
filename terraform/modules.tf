# ============================================================
# Module Composition — Wires all modules together
# ============================================================

locals {
  name_prefix = "${var.project_name}-${var.environment}"
  common_tags = merge(var.tags, {
    Environment = var.environment
  })

  # Key Vault reference helper — produces the App Service KV reference syntax
  kv_name = "${var.project_name}${var.environment}kv"
  kv_ref  = "kv_ref"
}

# Shorthand function for Key Vault references
# App Service reads secret at runtime via Managed Identity — never stored in plain text
locals {
  kv = {
    jwt_secret_key                 = "@Microsoft.KeyVault(VaultName=${local.kv_name};SecretName=jwt-secret-key)"
    db_password                    = "@Microsoft.KeyVault(VaultName=${local.kv_name};SecretName=db-password)"
    database_url                   = "@Microsoft.KeyVault(VaultName=${local.kv_name};SecretName=database-url)"
    storage_connection_string      = "@Microsoft.KeyVault(VaultName=${local.kv_name};SecretName=storage-connection-string)"
    openai_endpoint                = "@Microsoft.KeyVault(VaultName=${local.kv_name};SecretName=openai-endpoint)"
    openai_key                     = "@Microsoft.KeyVault(VaultName=${local.kv_name};SecretName=openai-key)"
    doc_intelligence_endpoint      = "@Microsoft.KeyVault(VaultName=${local.kv_name};SecretName=doc-intelligence-endpoint)"
    doc_intelligence_key           = "@Microsoft.KeyVault(VaultName=${local.kv_name};SecretName=doc-intelligence-key)"
    service_bus_connection_string  = "@Microsoft.KeyVault(VaultName=${local.kv_name};SecretName=service-bus-connection-string)"
    entra_client_id                = "@Microsoft.KeyVault(VaultName=${local.kv_name};SecretName=entra-client-id)"
    entra_client_secret            = "@Microsoft.KeyVault(VaultName=${local.kv_name};SecretName=entra-client-secret)"
    entra_tenant_id                = "@Microsoft.KeyVault(VaultName=${local.kv_name};SecretName=entra-tenant-id)"
    smtp_username                  = "@Microsoft.KeyVault(VaultName=${local.kv_name};SecretName=smtp-username)"
    smtp_password                  = "@Microsoft.KeyVault(VaultName=${local.kv_name};SecretName=smtp-password)"
  }
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
# 3. Container Registry
# ────────────────────────────────────────────────────────────

module "container_registry" {
  source              = "./modules/container_registry"
  name                = "${var.project_name}${var.environment}acr"
  resource_group_name = module.resource_group.name
  location            = var.location
  tags                = local.common_tags
}

# ────────────────────────────────────────────────────────────
# 4. App Service Plan (shared by frontend + backend)
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
# 5. Backend App Service
# NOTE: app_settings use Key Vault references — no plain text secrets
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
    # ── All secrets resolved from Key Vault at runtime ──────
    DATABASE_URL                          = local.kv.database_url
    JWT_SECRET_KEY                        = local.kv.jwt_secret_key
    AZURE_STORAGE_CONNECTION_STRING       = local.kv.storage_connection_string
    AZURE_STORAGE_CONTAINER_NAME          = "nutriai-documents"
    AZURE_OPENAI_ENDPOINT                 = local.kv.openai_endpoint
    AZURE_OPENAI_KEY                      = local.kv.openai_key
    AZURE_OPENAI_DEPLOYMENT_NAME          = var.openai_model_deployment
    AZURE_SERVICE_BUS_CONNECTION_STRING   = local.kv.service_bus_connection_string
    AZURE_SERVICE_BUS_TOPIC_NAME          = "meal-reminders"
    AZURE_DOCUMENT_INTELLIGENCE_ENDPOINT  = local.kv.doc_intelligence_endpoint
    AZURE_DOCUMENT_INTELLIGENCE_KEY       = local.kv.doc_intelligence_key
    ENTRA_CLIENT_ID                       = local.kv.entra_client_id
    ENTRA_CLIENT_SECRET                   = local.kv.entra_client_secret
    ENTRA_TENANT_ID                       = local.kv.entra_tenant_id
    SMTP_HOST                             = var.smtp_host
    SMTP_PORT                             = tostring(var.smtp_port)
    SMTP_USERNAME                         = local.kv.smtp_username
    SMTP_PASSWORD                         = local.kv.smtp_password
    APP_URL                               = "https://${local.name_prefix}-frontend.azurewebsites.net"
  }
}

# ────────────────────────────────────────────────────────────
# 6. Frontend App Service (Nginx)
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
# 7. Application Gateway (path-based routing)
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
# 8. PostgreSQL Flexible Server
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
# 9. Storage Account (Blob)
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
# 10. Azure OpenAI
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
# 11. Service Bus
# ────────────────────────────────────────────────────────────

module "service_bus" {
  source              = "./modules/service_bus"
  name                = "${local.name_prefix}-bus"
  resource_group_name = module.resource_group.name
  location            = var.location
  topic_name          = "meal-reminders"
  subscription_name   = "email-sender"
  tags                = local.common_tags
}


# ────────────────────────────────────────────────────────────
# 13. Key Vault — stores ALL secrets + connection strings
#     App Services access via Managed Identity (no plain text)
# ────────────────────────────────────────────────────────────

module "key_vault" {
  source              = "./modules/key_vault"
  name                = local.kv_name
  resource_group_name = module.resource_group.name
  location            = var.location
  tags                = local.common_tags

  # Grant both App Service managed identities read access
  # Keys must be static strings so Terraform can resolve for_each at plan time;
  # values (principal IDs) are allowed to be apply-time unknowns.
  app_service_principal_ids = {
    backend  = module.app_service.principal_id
    frontend = module.frontend_app_service.principal_id
  }

  secrets = {
    # ── Auth & JWT ───────────────────────────────────────────
    "jwt-secret-key"     = random_password.jwt_secret.result

    # ── Database ─────────────────────────────────────────────
    "db-password"        = random_password.db_password.result
    "database-url"       = module.postgresql.connection_string

    # ── Storage ──────────────────────────────────────────────
    "storage-connection-string" = module.storage.connection_string

    # ── Azure OpenAI ─────────────────────────────────────────
    "openai-endpoint"    = module.openai.endpoint
    "openai-key"         = module.openai.key

    # ── Document Intelligence ────────────────────────────────
    "doc-intelligence-endpoint" = var.document_intelligence_endpoint
    "doc-intelligence-key"      = var.document_intelligence_key

    # ── Service Bus ──────────────────────────────────────────
    "service-bus-connection-string" = module.service_bus.connection_string

    # ── Microsoft Entra ID ───────────────────────────────────
    "entra-client-id"     = var.entra_client_id
    "entra-client-secret" = var.entra_client_secret
    "entra-tenant-id"     = var.entra_tenant_id

    # ── Email (SMTP) ─────────────────────────────────────────
    "smtp-username"      = var.smtp_username
    "smtp-password"      = var.smtp_password
  }
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
# Random Passwords (generated by Terraform, stored in Key Vault)
# ============================================================

resource "random_password" "jwt_secret" {
  length  = 64
  special = true
}

resource "random_password" "db_password" {
  length  = 32
  special = false
}
