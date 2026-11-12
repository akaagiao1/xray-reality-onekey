#!/usr/bin/env bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
sed -n '/^show_info() {/,/^do_show() {/p' "$repo/reality" | sed '$d' > "$tmp/function.sh"
export CLIENT_FILE="$tmp/client.txt" CLIENT_PNG="$tmp/qr.png" CONFIG_FILE="$tmp/config.json"
export REALITY_HOST='203.0.113.1' REALITY_TAG='Reality-Test'
info() { :; }
warn() { :; }
source "$tmp/function.sh"
show_info '2cae91b3-f85c-433b-88ee-a002b9ed6d61' 'dwrjY6KiAMPxKdlF7T4AWFXXBtsxeHCXtBQYeCOdZV4' '0123456789abcdef' '443' 'example.com' > "$tmp/terminal.txt"
expected='Reality-Test = vless, 203.0.113.1, 443, username=2cae91b3-f85c-433b-88ee-a002b9ed6d61, flow=xtls-rprx-vision, sni=example.com, reality-public-key=dwrjY6KiAMPxKdlF7T4AWFXXBtsxeHCXtBQYeCOdZV4, reality-short-id=0123456789abcdef'
grep -Fxq "$expected" "$tmp/terminal.txt" || { echo 'FAIL: terminal missing Surge config'; exit 1; }
grep -Fxq "$expected" "$CLIENT_FILE" || { echo 'FAIL: saved file missing Surge config'; exit 1; }
grep -Fq 'vless=203.0.113.1:443' "$CLIENT_FILE" || { echo 'FAIL: QuanX config missing'; exit 1; }
grep -Fq 'vless://2cae91b3-f85c-433b-88ee-a002b9ed6d61@203.0.113.1:443' "$CLIENT_FILE" || { echo 'FAIL: share link missing'; exit 1; }
printf '[General]\n[Proxy]\n%s\n[Rule]\nFINAL,DIRECT\n' "$expected" > "$tmp/surge.conf"
surge_cli=${SURGE_CLI:-/Applications/Surge.app/Contents/Applications/surge-cli}
if [[ -x $surge_cli ]]; then "$surge_cli" --check "$tmp/surge.conf"; else echo 'Surge CLI unavailable: parser check skipped'; fi
printf '%s\n' 'Surge, QuanX, and share-link output checks passed'
