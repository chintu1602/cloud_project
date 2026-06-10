# ============================================================
# Root Variables
# ============================================================

# ── General ─────────────────────────────────────────────────

variable "project_name" {
  type        = string
  default     = "nutriai"
  description = "Project name prefix for all resources"
}

variable "environment" {
  type        = string
  default     = "dev"
  description = "Environment name (dev, prod)"
  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "Environment must be dev or prod."
  }
}

variable "location" {
  type        = string
  default     = "eastus"
  description = "Azure region for all resources"
}

variable "admin_email" {
  type        = string
  description = "Admin email for alerts and notifications"
}

# ── Microsoft Entra ID ──────────────────────────────────────

variable "entra_client_id" {
  type        = string
  description = "Microsoft Entra ID client ID"
  default     = ""
}

variable "entra_client_secret" {
  type        = string
  description = "Microsoft Entra ID client secret"
  sensitive   = true
  default     = ""
}

variable "entra_tenant_id" {
  type        = string
  description = "Microsoft Entra ID tenant ID"
  default     = ""
}

# ── Azure OpenAI ────────────────────────────────────────────

variable "openai_model_deployment" {
  type        = string
  default     = "gpt-4"
  description = "Azure OpenAI model deployment name"
}

# ── Azure Document Intelligence ─────────────────────────────

variable "document_intelligence_endpoint" {
  type        = string
  default     = ""
  description = "Azure Document Intelligence endpoint"
}

variable "document_intelligence_key" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Azure Document Intelligence key"
}

# ── Email (SMTP) ────────────────────────────────────────────

variable "smtp_host" {
  type    = string
  default = "smtp.gmail.com"
}

variable "smtp_port" {
  type    = number
  default = 587
}

variable "smtp_username" {
  type      = string
  default   = ""
  sensitive = true
}

variable "smtp_password" {
  type      = string
  default   = ""
  sensitive = true
}

# ── SKUs ────────────────────────────────────────────────────

variable "app_service_sku" {
  type        = string
  default     = "B2"
  description = "App Service Plan SKU (shared by frontend + backend)"
}

variable "postgres_sku" {
  type        = string
  default     = "B_Standard_B1ms"
  description = "PostgreSQL Flexible Server SKU"
}

# ── Application Gateway ────────────────────────────────────

variable "appgw_sku_name" {
  type        = string
  default     = "Standard_v2"
  description = "Application Gateway SKU name"
}

variable "appgw_sku_tier" {
  type        = string
  default     = "Standard_v2"
  description = "Application Gateway SKU tier"
}

variable "appgw_capacity" {
  type        = number
  default     = 2
  description = "Application Gateway instance count"
}

# ── Tags ────────────────────────────────────────────────────

variable "tags" {
  type = map(string)
  default = {
    Project     = "NutriAI"
    ManagedBy   = "Terraform"
    Application = "NutriAI Health Portal"
  }
}
