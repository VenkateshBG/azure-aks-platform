#!/usr/bin/env bash
# Creates an Entra ID app + federated credentials so GitHub Actions can log in to Azure
# WITHOUT any stored secret (OpenID Connect). Optionally sets the GitHub repo variables.
# Usage: scripts/01-setup-github-oidc.sh <owner>/<repo>
set -euo pipefail
source "$(dirname "$0")/common.sh"
ROOT="$(repo_root)"
need az
REPO="${1:?usage: $0 <owner>/<repo>}"
APP_NAME="${APP_NAME:-gh-${PREFIX}-oidc}"

SUB_ID=$(az account show --query id -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)

log "Creating app registration $APP_NAME"
APP_ID=$(az ad app list --display-name "$APP_NAME" --query '[0].appId' -o tsv)
[ -n "$APP_ID" ] || APP_ID=$(az ad app create --display-name "$APP_NAME" --query appId -o tsv)
az ad sp show --id "$APP_ID" >/dev/null 2>&1 || az ad sp create --id "$APP_ID" >/dev/null
SP_OBJECT_ID=$(az ad sp show --id "$APP_ID" --query id -o tsv)

log "Adding federated credentials (which GitHub contexts may log in)"
add_cred() {  # name subject
  az ad app federated-credential list --id "$APP_ID" --query "[?name=='$1'].name" -o tsv | grep -q . && return 0
  az ad app federated-credential create --id "$APP_ID" --parameters "{
    \"name\": \"$1\", \"issuer\": \"https://token.actions.githubusercontent.com\",
    \"subject\": \"$2\", \"audiences\": [\"api://AzureADTokenExchange\"]}" >/dev/null
  echo "added $1"
}
add_cred gh-main         "repo:${REPO}:ref:refs/heads/main"
add_cred gh-pull-request "repo:${REPO}:pull_request"
add_cred gh-env-dev      "repo:${REPO}:environment:dev"
add_cred gh-env-prod     "repo:${REPO}:environment:prod"

log "Granting roles (subscription scope - fine for a dedicated sandbox subscription)"
# Contributor creates resources; User Access Administrator lets Terraform create role assignments
for ROLE in "Contributor" "User Access Administrator"; do
  az role assignment create --assignee-object-id "$SP_OBJECT_ID" --assignee-principal-type ServicePrincipal \
    --role "$ROLE" --scope "/subscriptions/$SUB_ID" >/dev/null 2>&1 || true
  echo "role: $ROLE"
done
STATE_SA=$(grep storage_account_name "$ROOT/terraform/envs/dev/backend.hcl" | cut -d'"' -f2)
STATE_RG=$(grep resource_group_name "$ROOT/terraform/envs/dev/backend.hcl" | cut -d'"' -f2)
az role assignment create --assignee-object-id "$SP_OBJECT_ID" --assignee-principal-type ServicePrincipal \
  --role "Storage Blob Data Contributor" \
  --scope "$(az storage account show -n "$STATE_SA" -g "$STATE_RG" --query id -o tsv)" >/dev/null 2>&1 || true

if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  log "Setting GitHub repository variables on $REPO"
  gh variable set AZURE_CLIENT_ID       --repo "$REPO" --body "$APP_ID"
  gh variable set AZURE_TENANT_ID       --repo "$REPO" --body "$TENANT_ID"
  gh variable set AZURE_SUBSCRIPTION_ID --repo "$REPO" --body "$SUB_ID"
  gh variable set TF_STATE_RG           --repo "$REPO" --body "$STATE_RG"
  gh variable set TF_STATE_SA           --repo "$REPO" --body "$STATE_SA"
  gh variable set AZURE_LOCATION        --repo "$REPO" --body "$LOCATION"
  echo "Still to set by hand:  gh variable set ALERT_EMAIL --repo $REPO --body you@example.com"
else
  log "gh CLI not logged in - add these as repository VARIABLES (Settings > Secrets and variables > Actions > Variables):"
  printf 'AZURE_CLIENT_ID=%s\nAZURE_TENANT_ID=%s\nAZURE_SUBSCRIPTION_ID=%s\nTF_STATE_RG=%s\nTF_STATE_SA=%s\nAZURE_LOCATION=%s\nALERT_EMAIL=<your email>\n' \
    "$APP_ID" "$TENANT_ID" "$SUB_ID" "$STATE_RG" "$STATE_SA" "$LOCATION"
fi
echo
echo "CI service principal object id (needed only if you ALSO run terraform locally):"
echo "  export TF_VAR_extra_kv_admin_object_ids='[\"$SP_OBJECT_ID\"]'"
echo "These IDs are not secrets - OIDC means there is no password to leak."
