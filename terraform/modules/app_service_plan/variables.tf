variable "name" {
  type        = string
  description = "App Service Plan name"
}

variable "resource_group_name" {
  type        = string
  description = "Resource group name"
}

variable "location" {
  type        = string
  description = "Azure region"
}

variable "sku_name" {
  type        = string
  default     = "B2"
  description = "App Service Plan SKU"
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to resources"
}
