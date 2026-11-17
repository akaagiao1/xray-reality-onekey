#!/usr/bin/env bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
bash -c '
source "$1/reality" help >/dev/null
CONFIG_DIR="$2"; CONFIG_FILE="$2/config.json"
[ "$(parse_modes 4)" = 4 ] || { echo "mode 4 missing"; exit 1; }
[ "$(parse_modes all)" = "1 2 3 4" ] || exit 1
HY2_CERT="$2/hy2.crt"; HY2_KEY="$2/hy2.key"
hy2_generate_cert
inb=$(inbound_json 4 secret-password 24000 "" "" "" none)
printf "{\"inbounds\":[%s]}" "$inb" > "$CONFIG_FILE"
jq -e '\'' .inbounds[0] | .protocol == "hysteria" and .settings.version == 2 and .settings.users[0].auth == "secret-password" and .streamSettings.security == "tls" and .streamSettings.network == "hysteria" '\'' "$CONFIG_FILE" >/dev/null
[ "$(installed_modes)" = 4 ] || exit 1
mode_client_config 4 203.0.113.1 203.0.113.1 "" 1
case "$MODE_LINK" in hysteria2://secret-password@203.0.113.1:24000*) ;; *) echo "bad link: $MODE_LINK"; exit 1;; esac
case "$MODE_SURGE" in *" = hysteria2, 203.0.113.1, 24000, password=secret-password"*"download-bandwidth=200"*"server-cert-fingerprint-sha256="*) ;; *) echo "bad Surge line: $MODE_SURGE"; exit 1;; esac
printf "{\"up\":50,\"down\":200,\"hop\":\"20000-20100\"}" > "$CONFIG_DIR/hy2-options.json"
mode_client_config 4 203.0.113.1 203.0.113.1 LA 1
case "$MODE_SURGE" in LA-Hysteria2\ =*) ;; *) echo "name missing region or protocol: $MODE_SURGE"; exit 1;; esac
case "$MODE_LINK" in *"#LA-Hysteria2") ;; *) echo "link name missing region"; exit 1;; esac
case "$MODE_SURGE" in *"port-hopping=20000-20100"*"port-hopping-interval=30"*) ;; *) echo "Surge hopping missing: $MODE_SURGE"; exit 1;; esac
' _ "$repo" "$tmp"
echo 'HY2 tests passed'
