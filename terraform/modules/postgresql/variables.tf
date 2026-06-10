variable "name" {
  type        = string
  description = "PostgreSQL server name"
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
  default     = "B_Standard_B1ms"
  description = "PostgreSQL SKU"
}

variable "admin_password" {
  type        = string
  sensitive   = true
  description = "Administrator password"
}

variable "delegated_subnet_id" {
  type        = string
  description = "Delegated subnet ID for PostgreSQL"
}

variable "private_dns_zone_id" {
  type        = string
  description = "Private DNS zone ID"
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to resources"
}
