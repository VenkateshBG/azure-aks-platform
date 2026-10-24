variable "prefix" {
  type        = string
  description = "Short project prefix (lowercase letters/digits) used in resource names"
  default     = "aksplat"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "location" {
  type        = string
  description = "Region where your D2nls_v6 vCPU quota exists. Check: az vm list-usage -l <region> -o table"
  default     = "centralindia"
}

variable "aks_vm_size" {
  type    = string
  default = "Standard_D2nls_v6"
}

variable "aks_node_count" {
  type        = number
  description = "2 nodes x 2 vCPU = 4 vCPU (your whole quota)"
  default     = 2
}

variable "kubernetes_version" {
  type    = string
  default = null
}

variable "budget_amount" {
  type        = number
  description = "Monthly budget in your billing currency (INR account => rupees)"
  default     = 5000
}

variable "alert_email" {
  type        = string
  description = "Email that receives budget alerts"
}

variable "extra_kv_admin_object_ids" {
  type        = list(string)
  description = "Extra identities (e.g. the CI service principal) that need Key Vault admin so plan/apply works from both CI and your laptop"
  default     = []
}
