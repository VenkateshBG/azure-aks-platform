terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 4.0" }
    random  = { source = "hashicorp/random", version = "~> 3.6" }
    time    = { source = "hashicorp/time", version = "~> 0.12" }
  }

  # Remote state in Azure Storage (blob lease = state locking).
  # Values are passed at init time:  terraform init -backend-config=backend.hcl
  backend "azurerm" {
    use_azuread_auth = true # authenticate with Entra ID / OIDC, not storage account keys
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false # lets `terraform destroy` clean up fully
    }
    key_vault {
      purge_soft_delete_on_destroy = true # frees the vault name after destroy
    }
  }
  # subscription_id / tenant / client come from ARM_* environment variables
}

data "azurerm_client_config" "current" {}

locals {
  name_prefix = "${var.prefix}-${var.environment}"
  tags = {
    project     = var.prefix
    environment = var.environment
    managed_by  = "terraform"
  }
}

resource "random_string" "suffix" {
  length  = 4
  upper   = false
  special = false
}

resource "azurerm_resource_group" "this" {
  name     = "rg-${local.name_prefix}"
  location = var.location
  tags     = local.tags
}

module "network" {
  source              = "../../modules/network"
  name_prefix         = local.name_prefix
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

module "acr" {
  source              = "../../modules/acr"
  name                = "acr${var.prefix}${var.environment}${random_string.suffix.result}"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

module "aks" {
  source              = "../../modules/aks"
  name                = "aks-${local.name_prefix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  subnet_id           = module.network.aks_subnet_id
  acr_id              = module.acr.id
  vm_size             = var.aks_vm_size
  node_count          = var.aks_node_count
  kubernetes_version  = var.kubernetes_version
  tags                = local.tags
}

module "keyvault" {
  source                 = "../../modules/keyvault"
  name                   = "kv-${var.prefix}-${var.environment}-${random_string.suffix.result}"
  location               = var.location
  resource_group_name    = azurerm_resource_group.this.name
  tenant_id              = data.azurerm_client_config.current.tenant_id
  admin_object_ids       = distinct(concat([data.azurerm_client_config.current.object_id], var.extra_kv_admin_object_ids))
  csi_identity_object_id = module.aks.csi_identity_object_id
  tags                   = local.tags
}

module "budget" {
  source            = "../../modules/budget"
  name              = "budget-${local.name_prefix}"
  resource_group_id = azurerm_resource_group.this.id
  amount            = var.budget_amount
  contact_emails    = [var.alert_email]
}
