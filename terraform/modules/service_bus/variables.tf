variable "name" {
  type        = string
  description = "Service Bus namespace name"
}

variable "resource_group_name" {
  type        = string
  description = "Resource group name"
}

variable "location" {
  type        = string
  description = "Azure region"
}

variable "topic_name" {
  type        = string
  default     = "meal-reminders"
  description = "Service Bus topic name"
}

variable "subscription_name" {
  type        = string
  default     = "email-sender"
  description = "Service Bus subscription name"
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to resources"
}
