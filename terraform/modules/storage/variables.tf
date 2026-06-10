variable "name" {
  type        = string
  description = "Storage account name"
}

variable "resource_group_name" {
  type        = string
  description = "Resource group name"
}

variable "location" {
  type        = string
  description = "Azure region"
}

variable "container_name" {
  type        = string
  default     = "nutriai-documents"
  description = "Blob container name"
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to resources"
}
