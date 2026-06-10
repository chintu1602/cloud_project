resource "azurerm_linux_web_app" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  service_plan_id     = var.app_service_plan_id
  https_only          = true
  tags                = var.tags

  virtual_network_subnet_id = var.vnet_integration_subnet_id

  site_config {
    always_on                              = true
    ftps_state                             = "Disabled"
    health_check_path                      = "/"
    container_registry_use_managed_identity = false

    application_stack {
      docker_image_name        = "nutriai-frontend:latest"
      docker_registry_url      = "https://${var.acr_login_server}"
      docker_registry_username = var.acr_admin_username
      docker_registry_password = var.acr_admin_password
    }
  }

  app_settings = {
    WEBSITES_ENABLE_APP_SERVICE_STORAGE = "false"
    DOCKER_REGISTRY_SERVER_URL          = "https://${var.acr_login_server}"
    DOCKER_REGISTRY_SERVER_USERNAME     = var.acr_admin_username
    DOCKER_REGISTRY_SERVER_PASSWORD     = var.acr_admin_password
    WEBSITES_PORT                       = "80"
    BACKEND_URL                         = var.backend_url
  }

  identity { type = "SystemAssigned" }

  logs {
    http_logs {
      file_system {
        retention_in_days = 7
        retention_in_mb   = 35
      }
    }
    application_logs {
      file_system_level = "Warning"
    }
  }
}
