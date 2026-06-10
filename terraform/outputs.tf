# ============================================================
# Root Outputs
# ============================================================

output "resource_group_name" {
  value = module.resource_group.name
}

output "backend_url" {
  value       = module.app_service.default_hostname
  description = "Backend App Service hostname"
}

output "frontend_url" {
  value       = module.frontend_app_service.default_hostname
  description = "Frontend App Service hostname"
}

output "application_gateway_ip" {
  value       = module.application_gateway.public_ip
  description = "Application Gateway public IP"
}

output "application_gateway_fqdn" {
  value       = module.application_gateway.public_ip_fqdn
  description = "Application Gateway FQDN"
}

output "database_fqdn" {
  value     = module.postgresql.fqdn
  sensitive = true
}

output "storage_account_name" {
  value = module.storage.account_name
}

output "key_vault_name" {
  value = module.key_vault.name
}

output "container_registry_login_server" {
  value = module.container_registry.login_server
}

output "application_insights_connection_string" {
  value     = module.monitoring.appinsights_connection_string
  sensitive = true
}
