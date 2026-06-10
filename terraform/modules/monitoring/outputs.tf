output "appinsights_connection_string" {
  value     = azurerm_application_insights.this.connection_string
  sensitive = true
}

output "appinsights_id" {
  value       = azurerm_application_insights.this.id
  description = "Application Insights ID"
}

output "instrumentation_key" {
  value     = azurerm_application_insights.this.instrumentation_key
  sensitive = true
}

output "law_id" {
  value       = azurerm_log_analytics_workspace.this.id
  description = "Log Analytics Workspace ID"
}
