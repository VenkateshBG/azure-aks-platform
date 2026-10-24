#!/usr/bin/env bash
# Generates CPU load so you can watch the HPA scale the app (record this for your demo video!).
# Usage: scripts/load-test.sh [start|stop] [namespace]
set -euo pipefail
ACTION="${1:-start}"; NS="${2:-demo-dev}"
case "$ACTION" in
  start)
    for i in 1 2 3 4; do
      kubectl -n "$NS" run "loadgen-$i" --image=busybox:1.36 --restart=Never \
        --requests='cpu=10m,memory=8Mi' --limits='cpu=100m,memory=32Mi' -- \
        /bin/sh -c 'while true; do wget -q -O- "http://aks-platform-api/burn?seconds=0.5" >/dev/null 2>&1; done'
    done
    echo "Load started. Watch scaling:  kubectl -n $NS get hpa,pods -w"
    ;;
  stop)
    for i in 1 2 3 4; do kubectl -n "$NS" delete pod "loadgen-$i" --ignore-not-found --wait=false; done
    echo "Load stopped. The HPA scales back down after ~2 minutes."
    ;;
  *) echo "usage: $0 [start|stop] [namespace]"; exit 1 ;;
esac
