output "id" {
  value       = azurerm_linux_web_app.this.id
  description = "Frontend App Service ID"
}

output "default_hostname" {
  value       = azurerm_linux_web_app.this.default_hostname
  description = "Frontend App Service default hostname"
}

output "principal_id" {
  value       = azurerm_linux_web_app.this.identity[0].principal_id
  description = "Managed identity principal ID"
}
