output "endpoint" {
  value       = azurerm_cognitive_account.this.endpoint
  description = "OpenAI endpoint"
}

output "key" {
  value     = azurerm_cognitive_account.this.primary_access_key
  sensitive = true
}

output "id" {
  value       = azurerm_cognitive_account.this.id
  description = "OpenAI account ID"
}
