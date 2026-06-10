# ============================================================
# NutriAI Health Portal - Terraform Root Configuration
# Azure Cloud Infrastructure
#
# Workspaces:
#   terraform workspace new dev
#   terraform workspace new prod
#   terraform plan -var-file=environments/dev.tfvars
#   terraform plan -var-file=environments/prod.tfvars
# ============================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.85"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.47"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  backend "azurerm" {
    resource_group_name  = "nutriai-terraform-state"
    storage_account_name = "nutriaitfstate"
    container_name       = "tfstate"
    key                  = "nutriai.tfstate"
  }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

provider "azuread" {}
provider "random" {}
