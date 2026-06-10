resource "azurerm_postgresql_flexible_server" "this" {
  name                          = var.name
  resource_group_name           = var.resource_group_name
  location                      = var.location
  version                       = "16"
  delegated_subnet_id           = var.delegated_subnet_id
  private_dns_zone_id           = var.private_dns_zone_id
  administrator_login           = "nutriai_admin"
  administrator_password        = var.admin_password
  sku_name                      = var.sku_name
  storage_mb                    = 32768
  backup_retention_days         = 7
  geo_redundant_backup_enabled  = false
  public_network_access_enabled = false
  tags                          = var.tags

  lifecycle { ignore_changes = [zone] }
}

resource "azurerm_postgresql_flexible_server_database" "nutriai" {
  name      = "nutriai"
  server_id = azurerm_postgresql_flexible_server.this.id
  collation = "en_US.utf8"
  charset   = "UTF8"
}

resource "azurerm_postgresql_flexible_server_configuration" "extensions" {
  server_id = azurerm_postgresql_flexible_server.this.id
  name      = "azure.extensions"
  value     = "UUID-OSSP"
}
