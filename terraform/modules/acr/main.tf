variable "name" {
  type        = string
  description = "Globally unique, 5-50 chars, alphanumeric only"
}
variable "location" { type = string }
variable "resource_group_name" { type = string }
variable "tags" {
  type    = map(string)
  default = {}
}

resource "azurerm_container_registry" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "Basic" # cheapest tier; ~$5/month
  admin_enabled       = false   # no shared admin password; AKS pulls via managed identity
  tags                = var.tags
}

output "id" { value = azurerm_container_registry.this.id }
output "name" { value = azurerm_container_registry.this.name }
output "login_server" { value = azurerm_container_registry.this.login_server }
