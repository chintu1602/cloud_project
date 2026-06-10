variable "name" {
  type        = string
  description = "Application Gateway name"
}

variable "resource_group_name" {
  type        = string
  description = "Resource group name"
}

variable "location" {
  type        = string
  description = "Azure region"
}

variable "subnet_id" {
  type        = string
  description = "Application Gateway subnet ID"
}

variable "backend_fqdn" {
  type        = string
  description = "Backend App Service FQDN"
}

variable "frontend_fqdn" {
  type        = string
  description = "Frontend App Service FQDN"
}

variable "sku_name" {
  type        = string
  default     = "Standard_v2"
  description = "Application Gateway SKU name"
}

variable "sku_tier" {
  type        = string
  default     = "Standard_v2"
  description = "Application Gateway SKU tier"
}

variable "capacity" {
  type        = number
  default     = 2
  description = "Application Gateway instance count"
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to resources"
}
