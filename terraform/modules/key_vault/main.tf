data "azurerm_client_config" "current" {}

# ── Key Vault ────────────────────────────────────────────────

resource "azurerm_key_vault" "this" {
  name                       = var.name
  resource_group_name        = var.resource_group_name
  location                   = var.location
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  purge_protection_enabled   = true
  soft_delete_retention_days = 7
  tags                       = var.tags
}

# ── Access Policy: Terraform deployer ────────────────────────

resource "azurerm_key_vault_access_policy" "terraform" {
  key_vault_id = azurerm_key_vault.this.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  secret_permissions = ["Get", "List", "Set", "Delete", "Purge", "Recover"]
  key_permissions    = ["Get", "List", "Create", "Delete", "Purge", "Recover"]
}

# ── Access Policy: App Services (Managed Identity) ───────────
# Each App Service gets Get + List on secrets only
# NOTE: Use a map with static string keys so Terraform can determine
# resource instance keys at plan time (unknown values only in values, not keys).

resource "azurerm_key_vault_access_policy" "app_services" {
  for_each = var.app_service_principal_ids

  key_vault_id = azurerm_key_vault.this.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = each.value

  secret_permissions = ["Get", "List"]
}

# ── Secrets ──────────────────────────────────────────────────

resource "azurerm_key_vault_secret" "secrets" {
  for_each = var.secrets

  name         = each.key
  value        = each.value
  key_vault_id = azurerm_key_vault.this.id

  # Secrets can only be written after Terraform access policy is in place
  depends_on = [azurerm_key_vault_access_policy.terraform]
}
