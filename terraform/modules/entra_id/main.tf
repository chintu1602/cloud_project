data "azuread_client_config" "current" {}

resource "azuread_application" "this" {
  display_name = var.display_name
  owners       = [data.azuread_client_config.current.object_id]

  web {
    redirect_uris = [var.redirect_uri]
    implicit_grant {
      access_token_issuance_enabled = false
      id_token_issuance_enabled     = true
    }
  }

  required_resource_access {
    resource_app_id = "00000003-0000-0000-c000-000000000000" # Microsoft Graph
    resource_access {
      id   = "e1fe6dd8-ba31-4d61-89e7-88639da4683d" # User.Read
      type = "Scope"
    }
    resource_access {
      id   = "64a6cdd6-aab1-4aaf-94b8-3cc8405e90d0" # email
      type = "Scope"
    }
    resource_access {
      id   = "14dad69e-099b-42c9-810b-d002981feec1" # profile
      type = "Scope"
    }
  }
}

resource "azuread_application_password" "this" {
  application_id = azuread_application.this.id
  display_name   = "nutriai-client-secret"
  end_date       = "2027-12-31T00:00:00Z"
}
