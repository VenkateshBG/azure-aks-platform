variable "name" {
  type        = string
  description = "Globally unique, 3-24 chars"
}
variable "location" { type = string }
variable "resource_group_name" { type = string }
variable "tenant_id" { type = string }
variable "admin_object_ids" {
  type        = list(string)
  description = "Identities that run Terraform (CI service principal and/or you); each gets rights to manage secrets"
}
variable "csi_identity_object_id" {
  type        = string
  description = "AKS Key Vault CSI identity; gets read-only access"
}
variable "tags" {
  type    = map(string)
  default = {}
}

resource "azurerm_key_vault" "this" {
  name                       = var.name
  location                   = var.location
  resource_group_name        = var.resource_group_name
  tenant_id                  = var.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true # RBAC instead of legacy access policies
  soft_delete_retention_days = 7
  purge_protection_enabled   = false # allows clean teardown of the demo
  tags                       = var.tags
}

resource "azurerm_role_assignment" "admins" {
  for_each             = toset(var.admin_object_ids)
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = each.value
}

# Least privilege: pods can only READ secrets
resource "azurerm_role_assignment" "csi_reader" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = var.csi_identity_object_id
}

# RBAC assignments take a while to propagate; writing a secret too early fails with 403
resource "time_sleep" "rbac_propagation" {
  depends_on      = [azurerm_role_assignment.admins]
  create_duration = "90s"
}

resource "random_password" "api_key" {
  length  = 32
  special = false
}

resource "azurerm_key_vault_secret" "api_key" {
  name         = "app-api-key"
  value        = random_password.api_key.result
  key_vault_id = azurerm_key_vault.this.id
  depends_on   = [time_sleep.rbac_propagation]
}

output "id" { value = azurerm_key_vault.this.id }
output "name" { value = azurerm_key_vault.this.name }
