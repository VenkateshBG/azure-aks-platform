#!/usr/bin/env bash
# Deploys the app to the cluster. Used by BOTH GitHub Actions and Azure DevOps (and by hand).
# Requires: az logged in, kubectl, envsubst.   Usage: scripts/deploy.sh <dev|prod> <image-tag>
set -euo pipefail
source "$(dirname "$0")/common.sh"
ROOT="$(repo_root)"
need az; need kubectl; need envsubst
TARGET="${1:?usage: $0 <dev|prod> <image-tag>}"
export IMAGE_TAG="${2:?usage: $0 <dev|prod> <image-tag>}"
[[ "$TARGET" =~ ^(dev|prod)$ ]] || die "environment must be dev or prod"

log "Discovering resource names from Azure (no hard-coded values)"
ACR_NAME=$(az acr list -g "$RG" --query '[0].name' -o tsv)
[ -n "$ACR_NAME" ] || die "No ACR found in $RG - has the infrastructure been applied?"
export ACR_LOGIN_SERVER=$(az acr show -n "$ACR_NAME" --query loginServer -o tsv)
export KEYVAULT_NAME=$(az keyvault list -g "$RG" --query '[0].name' -o tsv)
export TENANT_ID=$(az account show --query tenantId -o tsv)
export CSI_CLIENT_ID=$(az aks show -g "$RG" -n "$AKS" \
  --query 'addonProfiles.azureKeyvaultSecretsProvider.identity.clientId' -o tsv)
[ -n "$CSI_CLIENT_ID" ] || die "Key Vault CSI identity not found on $AKS"

az aks get-credentials -g "$RG" -n "$AKS" --overwrite-existing >/dev/null
NS="demo-${TARGET}"

log "Applying overlay '$TARGET' with image ${ACR_LOGIN_SERVER}/aks-platform-api:${IMAGE_TAG}"
kubectl kustomize "$ROOT/k8s/overlays/$TARGET" \
  | envsubst '$ACR_LOGIN_SERVER $IMAGE_TAG $KEYVAULT_NAME $TENANT_ID $CSI_CLIENT_ID' \
  | kubectl apply -f -

log "Waiting for rollout"
kubectl -n "$NS" rollout status deployment/aks-platform-api --timeout=240s
kubectl -n "$NS" wait --for=condition=Programmed gateway/aks-platform-gw --timeout=240s

IP=""
for _ in $(seq 1 30); do
  IP=$(kubectl -n "$NS" get gateway aks-platform-gw -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || true)
  [ -n "$IP" ] && break; sleep 5
done
[ -n "$IP" ] || die "Gateway has no address yet"

log "Smoke test against http://$IP"
for i in $(seq 1 24); do
  if curl -fsS -m 5 "http://$IP/healthz" >/dev/null; then
    curl -fsS -m 5 "http://$IP/"; echo
    curl -fsS -m 5 "http://$IP/config-check"; echo
    echo "Deployed. Public endpoint: http://$IP"
    [ -z "${GITHUB_STEP_SUMMARY:-}" ] || echo "### Deployed **$TARGET** \`$IMAGE_TAG\` → http://$IP" >> "$GITHUB_STEP_SUMMARY"
    exit 0
  fi
  sleep 5
done
die "Smoke test failed"
