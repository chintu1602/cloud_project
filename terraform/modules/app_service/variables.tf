variable "name" {
  type        = string
  description = "App Service name"
}

variable "resource_group_name" {
  type        = string
  description = "Resource group name"
}

variable "location" {
  type        = string
  description = "Azure region"
}

variable "app_service_plan_id" {
  type        = string
  description = "App Service Plan ID"
}

variable "acr_login_server" {
  type        = string
  description = "ACR login server URL"
}

variable "acr_admin_username" {
  type        = string
  description = "ACR admin username"
}

variable "acr_admin_password" {
  type        = string
  sensitive   = true
  description = "ACR admin password"
}

variable "vnet_integration_subnet_id" {
  type        = string
  description = "Subnet ID for VNet integration"
}

variable "app_settings" {
  type        = map(string)
  sensitive   = true
  description = "App settings key-value pairs"
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to resources"
}
