#!/usr/bin/env bash
# Xray 公钥解析 (Password 格式) + do_show 从配置私钥反推公钥
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
# ---- 1) extract_xray_public: Public key / Password / Password (PublicKey) 都认, Hash32 不认 ----
sed -n '/^extract_xray_public() {/,/^gen_uuid() {/p' "$repo/reality" | sed '$d' > "$tmp/functions.sh"
source "$tmp/functions.sh"
for input in 'Public key: old_key' 'Password: old_key' 'Password (PublicKey): old_key'; do
  actual=$(printf '%s\n' "$input" 'Hash32: wrong' | extract_xray_public)
  [[ $actual == old_key ]] || { echo "FAIL: invalid public key parse: $input"; exit 1; }
done
[[ -z $(printf 'Hash32: wrong\n' | extract_xray_public) ]] || { echo 'FAIL: Hash32 mistaken for public key'; exit 1; }
# ---- 2) do_show: 配置里只有私钥, 展示输出里出现的是反推出的公钥 (Password 格式) ----
cp "$repo/reality" "$tmp/reality"
sed -i \
  -e "s|/usr/local/bin/xray|$tmp/xray|g" \
  -e "s|/usr/local/etc/xray|$tmp/xray-etc|g" \
  -e "s|/root/xray-reality-client.txt|$tmp/client.txt|g" \
  "$tmp/reality"
mkdir -p "$tmp/xray-etc"
cat > "$tmp/xray" <<'XRAY'
#!/usr/bin/env bash
# 假 Xray: x25519 -i 回 Password 格式的公钥 (新版 Xray 的叫法)
printf 'PrivateKey: private_example\nPassword: public_example\nHash32: ignored\n'
XRAY
chmod +x "$tmp/xray"
cat > "$tmp/xray-etc/config.json" <<'JSON'
{
  "inbounds": [
    {
      "tag": "vless-reality",
      "port": 443,
      "protocol": "vless",
      "settings": { "clients": [ { "id": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", "flow": "xtls-rprx-vision" } ], "decryption": "none" },
      "streamSettings": {
        "network": "tcp", "security": "reality",
        "realitySettings": {
          "show": false, "target": "example.com:443", "xver": 0,
          "serverNames": ["example.com"],
          "privateKey": "private_example",
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
bash -c 'source "$1" "$2"; do_show' _ "$tmp/harness.sh" "$tmp" > "$tmp/show.out" 2>&1
grep -Fq 'reality-public-key=public_example' "$tmp/client.txt" || { echo 'FAIL: Surge 行里没有反推出的公钥'; exit 1; }
grep -Fq 'pbk=public_example' "$tmp/client.txt" || { echo 'FAIL: vless 链接里没有反推出的公钥'; exit 1; }
grep -Fq 'private_example' "$tmp/client.txt" && { echo 'FAIL: 客户端文件里泄露了私钥'; exit 1; }
printf '%s\n' 'Xray public key format and show checks passed'
