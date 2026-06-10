variable "name" {
  type        = string
  description = "OpenAI cognitive account name"
}

variable "resource_group_name" {
  type        = string
  description = "Resource group name"
}

variable "location" {
  type        = string
  description = "Azure region"
}

variable "deployment_name" {
  type        = string
  default     = "gpt-4"
  description = "Model deployment name"
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to resources"
}
