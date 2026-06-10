variable "name" {
  type        = string
  description = "Key Vault name"
}

variable "resource_group_name" {
  type        = string
  description = "Resource group name"
}

variable "location" {
  type        = string
  description = "Azure region"
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to resources"
}

variable "secrets" {
  type        = map(string)
  sensitive   = true
  description = "Map of secret names to values to store in Key Vault"
}

variable "app_service_principal_ids" {
  type        = list(string)
  default     = []
  description = "List of App Service managed identity principal IDs to grant Key Vault read access"
}
