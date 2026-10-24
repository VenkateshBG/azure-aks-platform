# Bootstrap: creates the storage account that holds Terraform remote state.
# Run ONCE with local state (chicken-and-egg: state storage can't store its own state).
terraform {
  required_version = ">= 1.9.0"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 4.0" }
    random  = { source = "hashicorp/random", version = "~> 3.6" }
  }
}

provider "azurerm" {
  features {}
  # subscription_id comes from ARM_SUBSCRIPTION_ID (azurerm 4.x requires it)
}

variable "location" {
  type    = string
  default = "centralindia"
}

variable "prefix" {
  type    = string
  default = "aksplat"
}

resource "random_string" "suffix" {
  length  = 5
  upper   = false
  special = false
}

resource "azurerm_resource_group" "state" {
  name     = "rg-${var.prefix}-tfstate"
  location = var.location
  tags     = { project = var.prefix, purpose = "terraform-state" }
}

resource "azurerm_storage_account" "state" {
  name                            = "st${var.prefix}tf${random_string.suffix.result}"
  resource_group_name             = azurerm_resource_group.state.name
  location                        = azurerm_resource_group.state.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  # State locking uses blob leases; versioning lets you recover a bad state.
  blob_properties {
    versioning_enabled = true
  }
  tags = { project = var.prefix }
}

resource "azurerm_storage_container" "state" {
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.state.id
  container_access_type = "private"
}

output "resource_group_name" { value = azurerm_resource_group.state.name }
output "storage_account_name" { value = azurerm_storage_account.state.name }
output "container_name" { value = azurerm_storage_container.state.name }
