#!/usr/bin/env bash
# Installs Prometheus + Grafana (kube-prometheus-stack) with trimmed resources,
# then the app's ServiceMonitor, alert rule and Grafana dashboard.
# Optional: CHART_VERSION=<x.y.z> to pin the chart (find it with `helm list -n monitoring` after the first install).
set -euo pipefail
source "$(dirname "$0")/common.sh"
ROOT="$(repo_root)"
need helm; need kubectl

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update >/dev/null

GENERATED=""
if [ -z "${GRAFANA_ADMIN_PASSWORD:-}" ]; then
  # In CI the logs may be public: never generate-and-print a password there.
  [ -z "${CI:-}" ] || die "Set the GRAFANA_ADMIN_PASSWORD secret (Settings > Secrets > Actions) before running in CI"
  GRAFANA_ADMIN_PASSWORD="$(head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 20)"
  GENERATED=1
fi

VERSION_ARG=()
[ -z "${CHART_VERSION:-}" ] || VERSION_ARG=(--version "$CHART_VERSION")

log "Installing kube-prometheus-stack (takes a few minutes on small nodes)"
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace "${VERSION_ARG[@]}" \
  -f "$ROOT/monitoring/kube-prometheus-stack-values.yaml" \
  --set-string grafana.adminPassword="$GRAFANA_ADMIN_PASSWORD" \
  --wait --timeout 10m

kubectl apply -f "$ROOT/monitoring/app-monitoring.yaml" -f "$ROOT/monitoring/dashboard-configmap.yaml"

log "Monitoring installed"
echo "Grafana:    kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80   (user: admin)"
echo "Prometheus: kubectl -n monitoring port-forward svc/monitoring-prometheus 9090:9090"
[ -z "$GENERATED" ] || echo "Generated Grafana admin password: $GRAFANA_ADMIN_PASSWORD   (save it - it is not stored anywhere)"
