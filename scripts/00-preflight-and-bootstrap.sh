#!/usr/bin/env bash
# 1) checks your quota/VM size in the chosen region  2) registers resource providers
# 3) creates the Terraform remote-state storage account  4) writes terraform/envs/dev/backend.hcl
# Run ONCE, after `az login`.
set -euo pipefail
source "$(dirname "$0")/common.sh"
ROOT="$(repo_root)"
need az; need terraform

az account show >/dev/null 2>&1 || die "Run 'az login' first"
export ARM_SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
VM_SIZE="${VM_SIZE:-Standard_D2nls_v6}"

log "Subscription: $(az account show --query name -o tsv)  |  region: $LOCATION"

log "Checking that $VM_SIZE is offered in $LOCATION"
RESTRICTIONS=$(az vm list-skus -l "$LOCATION" --size "$VM_SIZE" --resource-type virtualMachines \
  --query "[0].restrictions[].reasonCode" -o tsv 2>/dev/null || true)
FOUND=$(az vm list-skus -l "$LOCATION" --size "$VM_SIZE" --resource-type virtualMachines --query "length(@)" -o tsv 2>/dev/null || echo 0)
[ "${FOUND:-0}" -ge 1 ] || die "$VM_SIZE is not available in $LOCATION. Pick another region (LOCATION=...) or size (VM_SIZE=...)"
[ -z "$RESTRICTIONS" ] || die "$VM_SIZE is restricted in $LOCATION ($RESTRICTIONS). Pick another region."

log "vCPU quota in $LOCATION (you need 4 free 'Total Regional vCPUs' and 4 in the VM family)"
az vm list-usage -l "$LOCATION" -o table --query "[?contains(name.localizedValue,'Total Regional') || contains(name.localizedValue,'Dnl') || contains(name.localizedValue,'Dn')].{Name:name.localizedValue,Used:currentValue,Limit:limit}" || true

log "Registering resource providers (safe to repeat)"
for p in Microsoft.ContainerService Microsoft.Compute Microsoft.Network Microsoft.Storage \
         Microsoft.KeyVault Microsoft.ContainerRegistry Microsoft.Consumption Microsoft.ManagedIdentity; do
  az provider register --namespace "$p" --wait >/dev/null && echo "registered $p"
done

log "Creating Terraform state storage (terraform/bootstrap)"
cd "$ROOT/terraform/bootstrap"
terraform init -input=false
terraform apply -input=false -auto-approve -var "location=$LOCATION" -var "prefix=$PREFIX"
SA=$(terraform output -raw storage_account_name)
STATE_RG=$(terraform output -raw resource_group_name)

cat > "$ROOT/terraform/envs/dev/backend.hcl" <<HCL
resource_group_name  = "$STATE_RG"
storage_account_name = "$SA"
container_name       = "tfstate"
key                  = "dev.terraform.tfstate"
HCL

# Your own account needs data-plane rights on the state container to run terraform locally
ME=$(az ad signed-in-user show --query id -o tsv)
az role assignment create --assignee-object-id "$ME" --assignee-principal-type User \
  --role "Storage Blob Data Contributor" \
  --scope "$(az storage account show -n "$SA" -g "$STATE_RG" --query id -o tsv)" >/dev/null || true

log "Done. State account: $SA  (backend.hcl written)"
echo "Next: scripts/01-setup-github-oidc.sh <github-owner>/<repo>"
