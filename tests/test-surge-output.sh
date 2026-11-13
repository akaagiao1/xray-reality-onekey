#!/usr/bin/env bash
# Surge 行 / QuanX 行 / vless 链接输出检查 (走 do_show 读配置, 不再拼 show_info 参数)
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
cp "$repo/reality" "$tmp/reality"
sed -i \
  -e "s|/usr/local/bin/xray|$tmp/xray|g" \
  -e "s|/usr/local/etc/xray|$tmp/xray-etc|g" \
  -e "s|/root/xray-reality-client.txt|$tmp/client.txt|g" \
  "$tmp/reality"
mkdir -p "$tmp/xray-etc"
cat > "$tmp/xray" <<'XRAY'
#!/usr/bin/env bash
# 假 Xray: x25519 -i 回固定公钥 (Password 格式, 新版 Xray 的叫法)
case "$1" in
  x25519)
    if [ "${2:-}" = "-i" ]; then printf 'Password: dwrjY6KiAMPxKdlF7T4AWFXXBtsxeHCXtBQYeCOdZV4\n'; else printf 'Private key: dummy\nPublic key: dwrjY6KiAMPxKdlF7T4AWFXXBtsxeHCXtBQYeCOdZV4\n'; fi ;;
  -test) exit 0 ;;
  version) printf 'Xray 26.11.9\n' ;;
  *) exit 0 ;;
esac
XRAY
chmod +x "$tmp/xray"
cat > "$tmp/xray-etc/config.json" <<'JSON'
{
  "inbounds": [
    {
      "tag": "vless-reality",
      "port": 443,
      "protocol": "vless",
      "settings": { "clients": [ { "id": "2cae91b3-f85c-433b-88ee-a002b9ed6d61", "flow": "xtls-rprx-vision" } ], "decryption": "none" },
      "streamSettings": {
        "network": "tcp", "security": "reality",
        "realitySettings": {
          "show": false, "target": "example.com:443", "xver": 0,
          "serverNames": ["example.com"],
          "privateKey": "dummy-private-key",
          "shortIds": ["0123456789abcdef"]
        }
      }
    }
  ],
  "outbounds": [ { "protocol": "freedom", "tag": "direct" }, { "protocol": "blackhole", "tag": "block" } ]
}
JSON
cat > "$tmp/harness.sh" <<'HARNESS'
#!/usr/bin/env bash
tmp="$1"; shift
source "$tmp/reality" help >/dev/null 2>&1
need_root() { :; }
detect_os() { OS_ID=debian; :; }
detect_init() { INIT=none; :; }
install_deps() { :; }
download_xray() { :; }
stop_service() { :; }
start_service() { :; }
service_active() { return 0; }
open_firewall() { :; }
try_bbr() { :; }
export REALITY_HOST=203.0.113.1
export TMPDIR="$tmp"
HARNESS
# 单装模式 1 时 REALITY_TAG 原样做节点名
REALITY_TAG='Reality-Test' bash -c 'source "$1" "$2"; do_show' _ "$tmp/harness.sh" "$tmp" > "$tmp/terminal.txt" 2>&1
expected='Reality-Test = vless, 203.0.113.1, 443, username=2cae91b3-f85c-433b-88ee-a002b9ed6d61, flow=xtls-rprx-vision, sni=example.com, reality-public-key=dwrjY6KiAMPxKdlF7T4AWFXXBtsxeHCXtBQYeCOdZV4, reality-short-id=0123456789abcdef'
grep -Fxq "$expected" "$tmp/terminal.txt" || { echo 'FAIL: terminal missing Surge config'; exit 1; }
grep -Fxq "$expected" "$tmp/client.txt" || { echo 'FAIL: saved file missing Surge config'; exit 1; }
grep -Fq 'vless=203.0.113.1:443' "$tmp/client.txt" || { echo 'FAIL: QuanX config missing'; exit 1; }
grep -Fq 'vless://2cae91b3-f85c-433b-88ee-a002b9ed6d61@203.0.113.1:443' "$tmp/client.txt" || { echo 'FAIL: share link missing'; exit 1; }
grep -Fq 'tag=Reality-Test' "$tmp/client.txt" || { echo 'FAIL: QuanX tag 不是 Reality-Test'; exit 1; }
grep -Fq '#Reality-Test' "$tmp/client.txt" || { echo 'FAIL: vless 链接名字不是 Reality-Test'; exit 1; }
printf '[General]\n[Proxy]\n%s\n[Rule]\nFINAL,DIRECT\n' "$expected" > "$tmp/surge.conf"
surge_cli=${SURGE_CLI:-/Applications/Surge.app/Contents/Applications/surge-cli}
if [[ -x $surge_cli ]]; then "$surge_cli" --check "$tmp/surge.conf"; else echo 'Surge CLI unavailable: parser check skipped'; fi
printf '%s\n' 'Surge, QuanX, and share-link output checks passed'
