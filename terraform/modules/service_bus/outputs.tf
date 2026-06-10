output "connection_string" {
  value     = azurerm_servicebus_namespace_authorization_rule.app.primary_connection_string
  sensitive = true
}

output "id" {
  value       = azurerm_servicebus_namespace.this.id
  description = "Service Bus namespace ID"
}
