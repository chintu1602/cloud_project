resource "azurerm_monitor_action_group" "this" {
  name                = "${var.name}-action-group"
  resource_group_name = var.resource_group_name
  short_name          = "nutriai"
  tags                = var.tags

  email_receiver {
    name          = "admin"
    email_address = var.action_group_email
  }
}

resource "azurerm_monitor_metric_alert" "high_response_time" {
  name                = "${var.name}-high-response-time"
  resource_group_name = var.resource_group_name
  scopes              = [var.app_service_id]
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"
  tags                = var.tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "HttpResponseTime"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 5
  }

  action {
    action_group_id = azurerm_monitor_action_group.this.id
  }
}

resource "azurerm_monitor_metric_alert" "high_error_rate" {
  name                = "${var.name}-high-error-rate"
  resource_group_name = var.resource_group_name
  scopes              = [var.app_service_id]
  severity            = 1
  frequency           = "PT5M"
  window_size         = "PT15M"
  tags                = var.tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "Http5xx"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 10
  }

  action {
    action_group_id = azurerm_monitor_action_group.this.id
  }
}

resource "azurerm_monitor_metric_alert" "high_cpu" {
  name                = "${var.name}-high-cpu"
  resource_group_name = var.resource_group_name
  scopes              = [var.app_service_id]
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"
  tags                = var.tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "CpuPercentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }

  action {
    action_group_id = azurerm_monitor_action_group.this.id
  }
}
