#!/usr/bin/env bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
bash -c '
source "$1/reality" help >/dev/null
CONFIG_DIR="$2/newdir"; CONFIG_FILE="$CONFIG_DIR/config.json"
HY2_UP=20 HY2_DOWN=100 HY2_HOP_PORTS=off hy2_options
[ "$(jq -r '\''.up, .down, .hop'\'' "$CONFIG_DIR/hy2-options.json" | tr "\n" " ")" = "20 100  " ]
if (HY2_UP=0 HY2_DOWN=100 hy2_options >/dev/null 2>&1); then echo "zero bandwidth accepted"; exit 1; fi
hy2_generate_cert
before=$(openssl x509 -in "$CONFIG_DIR/hy2.crt" -noout -fingerprint)
hy2_generate_cert
[ "$before" = "$(openssl x509 -in "$CONFIG_DIR/hy2.crt" -noout -fingerprint)" ]
' _ "$repo" "$tmp"
echo 'HY2 options tests passed'
