output "resource_group" { value = azurerm_resource_group.this.name }
output "aks_name" { value = module.aks.name }
output "acr_name" { value = module.acr.name }
output "acr_login_server" { value = module.acr.login_server }
output "keyvault_name" { value = module.keyvault.name }
output "tenant_id" { value = data.azurerm_client_config.current.tenant_id }
output "csi_identity_client_id" { value = module.aks.csi_identity_client_id }
output "oidc_issuer_url" { value = module.aks.oidc_issuer_url }
