output "vnet_id" {
  value       = azurerm_virtual_network.this.id
  description = "Virtual network ID"
}

output "appgw_subnet_id" {
  value       = azurerm_subnet.appgw.id
  description = "Application Gateway subnet ID"
}

output "frontend_subnet_id" {
  value       = azurerm_subnet.frontend.id
  description = "Frontend App Service subnet ID"
}

output "backend_subnet_id" {
  value       = azurerm_subnet.backend.id
  description = "Backend App Service subnet ID"
}

output "db_subnet_id" {
  value       = azurerm_subnet.db.id
  description = "Database subnet ID"
}

output "endpoint_subnet_id" {
  value       = azurerm_subnet.endpoint.id
  description = "Private endpoint subnet ID"
}

output "postgres_dns_zone_id" {
  value       = azurerm_private_dns_zone.postgres.id
  description = "PostgreSQL private DNS zone ID"
}
