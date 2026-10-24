#!/usr/bin/env bash
# Shared settings. Override any of these with environment variables.
export PREFIX="${PREFIX:-aksplat}"
export LOCATION="${LOCATION:-centralindia}"
export RG="${RG:-rg-${PREFIX}-dev}"
export AKS="${AKS:-aks-${PREFIX}-dev}"
export ENVOY_GATEWAY_VERSION="${ENVOY_GATEWAY_VERSION:-v1.7.5}"

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
die() { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "'$1' is required but not installed"; }

repo_root() { cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd; }
