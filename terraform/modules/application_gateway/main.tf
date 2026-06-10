# ============================================================
# Application Gateway with path-based routing
# /api/* -> Backend App Service
# /*     -> Frontend App Service
# ============================================================

resource "azurerm_public_ip" "this" {
  name                = "${var.name}-pip"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  domain_name_label   = var.name
  tags                = var.tags
}

resource "azurerm_application_gateway" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  sku {
    name     = var.sku_name
    tier     = var.sku_tier
    capacity = var.capacity
  }

  gateway_ip_configuration {
    name      = "gateway-ip-config"
    subnet_id = var.subnet_id
  }

  # ── Frontend ──────────────────────────────────────────────

  frontend_port {
    name = "http-port"
    port = 80
  }

  frontend_ip_configuration {
    name                 = "frontend-ip"
    public_ip_address_id = azurerm_public_ip.this.id
  }

  # ── Backend Pools ─────────────────────────────────────────

  backend_address_pool {
    name  = "backend-pool"
    fqdns = [var.backend_fqdn]
  }

  backend_address_pool {
    name  = "frontend-pool"
    fqdns = [var.frontend_fqdn]
  }

  # ── Backend HTTP Settings ─────────────────────────────────

  backend_http_settings {
    name                                = "backend-http-settings"
    cookie_based_affinity               = "Disabled"
    port                                = 443
    protocol                            = "Https"
    request_timeout                     = 120
    pick_host_name_from_backend_address = true

    probe_name = "backend-probe"
  }

  backend_http_settings {
    name                                = "frontend-http-settings"
    cookie_based_affinity               = "Disabled"
    port                                = 443
    protocol                            = "Https"
    request_timeout                     = 60
    pick_host_name_from_backend_address = true

    probe_name = "frontend-probe"
  }

  # ── Health Probes ─────────────────────────────────────────

  probe {
    name                                      = "backend-probe"
    protocol                                  = "Https"
    path                                      = "/health"
    interval                                  = 30
    timeout                                   = 30
    unhealthy_threshold                       = 3
    pick_host_name_from_backend_http_settings = true
  }

  probe {
    name                                      = "frontend-probe"
    protocol                                  = "Https"
    path                                      = "/"
    interval                                  = 30
    timeout                                   = 30
    unhealthy_threshold                       = 3
    pick_host_name_from_backend_http_settings = true
  }

  # ── HTTP Listener ─────────────────────────────────────────

  http_listener {
    name                           = "http-listener"
    frontend_ip_configuration_name = "frontend-ip"
    frontend_port_name             = "http-port"
    protocol                       = "Http"
  }

  # ── URL Path Map (path-based routing) ─────────────────────

  url_path_map {
    name                               = "path-map"
    default_backend_address_pool_name  = "frontend-pool"
    default_backend_http_settings_name = "frontend-http-settings"

    path_rule {
      name                       = "api-rule"
      paths                      = ["/api/*"]
      backend_address_pool_name  = "backend-pool"
      backend_http_settings_name = "backend-http-settings"
    }
  }

  # ── Request Routing Rule ──────────────────────────────────

  request_routing_rule {
    name               = "path-based-rule"
    priority           = 100
    rule_type          = "PathBasedRouting"
    http_listener_name = "http-listener"
    url_path_map_name  = "path-map"
  }
}
