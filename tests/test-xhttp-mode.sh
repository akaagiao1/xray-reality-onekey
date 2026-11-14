#!/usr/bin/env bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
cp "$repo/reality" "$tmp/reality"
cat > "$tmp/xray" <<'XRAY'
#!/usr/bin/env bash
printf 'Password: BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB\n'
XRAY
chmod +x "$tmp/xray"
bash -c '
source "$1/reality" help >/dev/null
CONFIG_FILE="$1/config.json"; XRAY_BIN="$1/xray"
priv=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
dec="mlkem768x25519plus.native.600s.$priv"
inb=$(inbound_json 2 11111111-2222-3333-4444-555555555555 24432 scanned.example.com "$priv" 1234567890abcdef "$dec")
printf "{\"inbounds\":[%s]}" "$inb" > "$CONFIG_FILE"
jq -e '\'' .inbounds[0] | .streamSettings.network == "xhttp" and .streamSettings.security == "reality" and .streamSettings.realitySettings.serverNames[0] == "scanned.example.com" and .settings.decryption != "none" '\'' "$CONFIG_FILE" >/dev/null || { echo "mode 2 server configuration incorrect"; exit 1; }
mode_has_reality 2 || { echo "mode 2 must use Reality"; exit 1; }
mode_client_config 2 203.0.113.1 203.0.113.1 "" 1
case "$MODE_SURGE" in *xhttp=true*sni=scanned.example.com*reality-public-key=*encryption=mlkem768x25519plus*) ;; *) echo "Surge output incorrect: $MODE_SURGE"; exit 1;; esac
case "$MODE_LINK" in *security=reality*sni=scanned.example.com*type=xhttp*) ;; *) echo "link incorrect: $MODE_LINK"; exit 1;; esac
# Old TCP-only mode 2 must remain readable until explicitly reinstalled.
jq "(.inbounds[0].streamSettings) = {network:\"tcp\",security:\"none\"}" "$CONFIG_FILE" > "$1/legacy.json"
CONFIG_FILE="$1/legacy.json"
mode_client_config 2 203.0.113.1 203.0.113.1 "" 1
case "$MODE_LINK" in *security=none*type=tcp*) ;; *) echo "legacy output incorrect"; exit 1;; esac
' _ "$tmp"
echo 'XHTTP mode tests passed'
