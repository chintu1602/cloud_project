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
  type        = map(string)
  default     = {}
  description = "Map of logical name to App Service managed identity principal ID, granting Key Vault read access. Use static string keys (e.g. 'backend', 'frontend') so Terraform can resolve for_each at plan time."
}
