output "client_id" {
  value       = azuread_application.this.client_id
  description = "Entra ID client ID"
}

output "client_secret" {
  value     = azuread_application_password.this.value
  sensitive = true
}

output "tenant_id" {
  value       = data.azuread_client_config.current.tenant_id
  description = "Entra ID tenant ID"
}
