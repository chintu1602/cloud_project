output "fqdn" {
  value       = azurerm_postgresql_flexible_server.this.fqdn
  description = "PostgreSQL server FQDN"
}

output "connection_string" {
  value     = "postgresql://nutriai_admin:${var.admin_password}@${azurerm_postgresql_flexible_server.this.fqdn}:5432/nutriai?sslmode=require"
  sensitive = true
}

output "id" {
  value       = azurerm_postgresql_flexible_server.this.id
  description = "PostgreSQL server ID"
}
