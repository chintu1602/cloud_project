variable "name" { type = string }
variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "app_service_plan_id" { type = string }
variable "storage_account_name" { type = string }
variable "storage_account_key" { type = string; sensitive = true }
variable "app_settings" { type = map(string); sensitive = true }
variable "tags" { type = map(string) }

resource "azurerm_linux_function_app" "this" {
  name                       = var.name
  resource_group_name        = var.resource_group_name
  location                   = var.location
  service_plan_id            = var.app_service_plan_id
  storage_account_name       = var.storage_account_name
  storage_account_access_key = var.storage_account_key
  tags                       = var.tags

  site_config {
    always_on = true
    application_stack {
      node_version = "20"
    }
  }

  app_settings = merge(var.app_settings, {
    FUNCTIONS_WORKER_RUNTIME = "node"
    AzureWebJobsFeatureFlags = "EnableWorkerIndexing"
  })

  identity { type = "SystemAssigned" }
}

output "default_hostname" { value = azurerm_linux_function_app.this.default_hostname }
output "default_key" { value = azurerm_linux_function_app.this.site_credential[0].password; sensitive = true }
output "id" { value = azurerm_linux_function_app.this.id }
