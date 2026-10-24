#!/usr/bin/env bash
# Installs the Gateway API controller (Envoy Gateway) with Helm + our GatewayClass.
# Needs kubectl pointed at the cluster (az aks get-credentials ...).
set -euo pipefail
source "$(dirname "$0")/common.sh"
ROOT="$(repo_root)"
need helm; need kubectl

log "Installing Envoy Gateway $ENVOY_GATEWAY_VERSION"
helm upgrade --install eg oci://docker.io/envoyproxy/gateway-helm \
  --version "$ENVOY_GATEWAY_VERSION" -n envoy-gateway-system --create-namespace \
  -f "$ROOT/k8s/platform/envoy-gateway-values.yaml" --wait --timeout 5m

kubectl wait --timeout=5m -n envoy-gateway-system deployment/envoy-gateway --for=condition=Available
kubectl apply -f "$ROOT/k8s/platform/gatewayclass.yaml"
kubectl get gatewayclass eg
