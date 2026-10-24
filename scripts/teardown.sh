#!/usr/bin/env bash
# Destroys EVERYTHING this project created, so nothing keeps billing.
# Run this after you have recorded the demo video and taken screenshots.
set -euo pipefail
source "$(dirname "$0")/common.sh"
ROOT="$(repo_root)"
need az; need terraform
read -r -p "This deletes the AKS cluster, ACR, Key Vault and state. Type 'destroy' to continue: " ANS
[ "$ANS" = "destroy" ] || die "aborted"

export ARM_SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
log "Removing Gateways first so Azure load balancers/public IPs are released cleanly"
az aks get-credentials -g "$RG" -n "$AKS" --overwrite-existing >/dev/null 2>&1 && \
  kubectl delete gateway --all -A --ignore-not-found --wait=true --timeout=3m || true

log "terraform destroy (dev environment)"
cd "$ROOT/terraform/envs/dev"
terraform init -input=false -backend-config=backend.hcl
terraform destroy -input=false -auto-approve -var "alert_email=${ALERT_EMAIL:-destroy@example.com}"

read -r -p "Also delete the Terraform state storage account? (y/N) " ANS2
if [[ "$ANS2" =~ ^[Yy]$ ]]; then
  cd "$ROOT/terraform/bootstrap" && terraform destroy -input=false -auto-approve
fi
log "Teardown complete. Verify in the portal that no resource groups named rg-${PREFIX}-* remain."
