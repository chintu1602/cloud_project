output "login_server" {
  value       = azurerm_container_registry.this.login_server
  description = "ACR login server"
}

output "admin_username" {
  value       = azurerm_container_registry.this.admin_username
  description = "ACR admin username"
}

output "admin_password" {
  value     = azurerm_container_registry.this.admin_password
  sensitive = true
}

output "id" {
  value       = azurerm_container_registry.this.id
  description = "ACR ID"
}
