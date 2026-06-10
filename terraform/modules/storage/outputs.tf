output "account_name" {
  value       = azurerm_storage_account.this.name
  description = "Storage account name"
}

output "primary_access_key" {
  value     = azurerm_storage_account.this.primary_access_key
  sensitive = true
}

output "connection_string" {
  value     = azurerm_storage_account.this.primary_connection_string
  sensitive = true
}

output "id" {
  value       = azurerm_storage_account.this.id
  description = "Storage account ID"
}
