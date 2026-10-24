variable "name" { type = string }
variable "location" { type = string }
variable "resource_group_name" { type = string }
variable "subnet_id" { type = string }
variable "acr_id" { type = string }

variable "vm_size" {
  type        = string
  description = "Node VM size. Must fit your regional vCPU quota."
  default     = "Standard_D2nls_v6"
}

variable "node_count" {
  type        = number
  description = "Fixed node count. 2 x 2 vCPU = 4 vCPU = the whole free-subscription quota."
  default     = 2
}

variable "kubernetes_version" {
  type        = string
  description = "Leave null to use the AKS default for the region."
  default     = null
}

variable "tags" {
  type    = map(string)
  default = {}
}

resource "azurerm_kubernetes_cluster" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = var.name
  kubernetes_version  = var.kubernetes_version
  sku_tier            = "Free" # free control plane; you only pay for nodes

  # Upgrades need an extra "surge" node, which the 4-vCPU quota can't provide.
  # Turn automatic upgrades off so nothing tries to surge behind your back.
  # automatic_upgrade_channel left unset = no automatic cluster upgrades
  node_os_upgrade_channel = "Unmanaged"

  oidc_issuer_enabled       = true # needed for workload identity
  workload_identity_enabled = true

  default_node_pool {
    name            = "system"
    vm_size         = var.vm_size
    node_count      = var.node_count
    vnet_subnet_id  = var.subnet_id
    os_disk_type    = "Managed" # Dnlsv6 has no ephemeral OS disk support
    os_disk_size_gb = 64
    type            = "VirtualMachineScaleSets"
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_data_plane  = "cilium"
    network_policy      = "cilium"
    pod_cidr            = "10.244.0.0/16"
    service_cidr        = "10.0.0.0/16"
    dns_service_ip      = "10.0.0.10"
    load_balancer_sku   = "standard"
  }

  # Key Vault CSI driver: mounts Key Vault secrets into pods as files
  key_vault_secrets_provider {
    secret_rotation_enabled = true
  }

  tags = var.tags
}

# Let the cluster's kubelet identity pull images from ACR (no image-pull secrets)
resource "azurerm_role_assignment" "acr_pull" {
  scope                            = var.acr_id
  role_definition_name             = "AcrPull"
  principal_id                     = azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id
  skip_service_principal_aad_check = true
}

output "name" { value = azurerm_kubernetes_cluster.this.name }
output "oidc_issuer_url" { value = azurerm_kubernetes_cluster.this.oidc_issuer_url }
output "csi_identity_client_id" {
  value = azurerm_kubernetes_cluster.this.key_vault_secrets_provider[0].secret_identity[0].client_id
}
output "csi_identity_object_id" {
  value = azurerm_kubernetes_cluster.this.key_vault_secrets_provider[0].secret_identity[0].object_id
}
