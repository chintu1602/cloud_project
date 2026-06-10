variable "name" {
  type        = string
  description = "Alert resource name prefix"
}

variable "resource_group_name" {
  type        = string
  description = "Resource group name"
}

variable "app_service_id" {
  type        = string
  description = "Backend App Service ID to monitor"
}

variable "appinsights_id" {
  type        = string
  description = "Application Insights ID"
}

variable "action_group_email" {
  type        = string
  description = "Email address for alert notifications"
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to resources"
}
