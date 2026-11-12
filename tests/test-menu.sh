#!/usr/bin/env bash
# 菜单 4 选项 + 换端口 + 完全卸载 + 扫描重装的测试 (不用真装 Xray, 全是替身)
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

# ---- 1) 菜单文案: 4 个选项 + 退出, 旧的 1-6 菜单不在了 ----
grep -Fq '1) 查看客户端配置 (Surge / QuanX / vless://)' "$repo/reality" || { echo 'FAIL: 菜单缺选项 1 查看配置'; exit 1; }
grep -Fq '2) 重新安装并扫描 Reality 域名' "$repo/reality" || { echo 'FAIL: 菜单缺选项 2 扫描重装'; exit 1; }
grep -Fq '3) 更换 Reality 端口' "$repo/reality" || { echo 'FAIL: 菜单缺选项 3 换端口'; exit 1; }
grep -Fq '4) 完全卸载' "$repo/reality" || { echo 'FAIL: 菜单缺选项 4 完全卸载'; exit 1; }
grep -Fq '6) 更改配置' "$repo/reality" && { echo 'FAIL: 菜单里还有旧的选项 6'; exit 1; }

# ---- 测试替身: reality 副本, 路径全部指到 $tmp, 不碰真系统 ----
cp "$repo/reality" "$tmp/reality"
sed -i \
  -e "s|/usr/local/bin/xray|$tmp/xray|g" \
  -e "s|/usr/local/etc/xray|$tmp/xray-etc|g" \
  -e "s|/root/xray-reality-client.txt|$tmp/client.txt|g" \
  -e "s|/usr/local/share/xray|$tmp/xray-share|g" \
  "$tmp/reality"
mkdir -p "$tmp/xray-etc" "$tmp/xray-share"
cat > "$tmp/xray" <<'XRAY'
#!/usr/bin/env bash
# 假 Xray: 只回固定值, 不联网不监听
case "$1" in
  x25519)
    if [ "${2:-}" = "-i" ]; then printf 'Password: cHViX2tleV9leGFtcGxlX2Jhc2U2NA==\n'; else printf 'Private key: cHJpdl9leGFtcGxl\nPublic key: cHViX2tleV9leGFtcGxlX2Jhc2U2NA==\n'; fi ;;
  -test) exit 0 ;;
  version) printf 'Xray 26.10.31\n' ;;
  uuid) printf '11111111-2222-3333-4444-555555555555\n' ;;
  *) exit 0 ;;
esac
XRAY
chmod +x "$tmp/xray"
cat > "$tmp/xray-etc/config.json" <<'JSON'
{
  "inbounds": [
    {
      "port": 443,
      "protocol": "vless",
      "settings": { "clients": [ { "id": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", "flow": "xtls-rprx-vision" } ] },
      "streamSettings": {
        "network": "tcp", "security": "reality",
        "realitySettings": {
          "target": "www.amazon.com:443",
          "serverNames": ["www.amazon.com"],
          "privateKey": "cHJpdl9leGFtcGxl",
          "shortIds": ["0123456789abcdef"]
        }
      }
    }
  ]
}
JSON
# 假扫描脚本: 写推荐域名, 不真扫网段
cat > "$tmp/scan-neighbors.sh" <<'SCAN'
#!/usr/bin/env bash
while [ "$#" -gt 0 ]; do case "$1" in --recommend-file) shift; printf '%s\n' 'scanned.example.com' > "$1" ;; esac; shift; done
SCAN
chmod +x "$tmp/scan-neighbors.sh"

# 替身环境: source 副本 (help 分支只打印用法就返回), 再把会碰系统的函数换成空操作
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
chmod +x "$tmp/harness.sh"

# ---- 2) 换端口: REALITY_PORT=24444 非交互, 域名/UUID/密钥不变 ----
bash -c 'source "$1" "$2"; REALITY_PORT=24444 do_change_port' _ "$tmp/harness.sh" "$tmp" > "$tmp/change-port.out" 2>&1
grep -Fq '端口已改: 443 -> 24444' "$tmp/change-port.out" || { echo 'FAIL: 换端口没报 443 -> 24444'; cat "$tmp/change-port.out"; exit 1; }
[ "$(jq -r '.inbounds[0].port' "$tmp/xray-etc/config.json")" = "24444" ] || { echo 'FAIL: 配置端口没改成 24444'; exit 1; }
[ "$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0]' "$tmp/xray-etc/config.json")" = "www.amazon.com" ] || { echo 'FAIL: 换端口时域名被改了'; exit 1; }
[ "$(jq -r '.inbounds[0].settings.clients[0].id' "$tmp/xray-etc/config.json")" = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee" ] || { echo 'FAIL: 换端口时 UUID 被改了'; exit 1; }
grep -Fq '203.0.113.1:24444' "$tmp/client.txt" || { echo 'FAIL: 客户端文件里没新端口'; exit 1; }
# 节点名现在按 IP 所在地自动生成, 这里只断言 Surge 行带新端口, 不写死名字
grep -Fq '= vless, 203.0.113.1, 24444' "$tmp/client.txt" || { echo 'FAIL: 客户端文件里 Surge 行没新端口'; exit 1; }

# ---- 3) 换端口拒绝 CF 端口: REALITY_PORT=8443 必须报错停下 ----
if bash -c 'source "$1" "$2"; REALITY_PORT=8443 do_change_port' _ "$tmp/harness.sh" "$tmp" > "$tmp/cf-port.out" 2>&1; then
  echo 'FAIL: 8443 是 CF 端口, 换端口居然没拒绝'; exit 1
fi
[ "$(jq -r '.inbounds[0].port' "$tmp/xray-etc/config.json")" = "24444" ] || { echo 'FAIL: 拒绝后端口被改了'; exit 1; }

# ---- 4) 扫描重装: 替身扫描给域名, do_install 被调用时只记 REALITY_SNI ----
# $0 设成 $tmp/reality, 让 do_rescan_reinstall 在 $tmp 里找到替身扫描脚本
bash -c 'source "$1" "$2"; do_install() { printf "%s" "${REALITY_SNI:-}" > "$TMPDIR/install-sni.txt"; }; do_rescan_reinstall' "$tmp/reality" "$tmp/harness.sh" "$tmp" "$tmp" > "$tmp/rescan.out" 2>&1
[ -f "$tmp/install-sni.txt" ] || { echo 'FAIL: 扫描重装没调 do_install'; cat "$tmp/rescan.out"; exit 1; }
[ "$(cat "$tmp/install-sni.txt")" = "scanned.example.com" ] || { echo "FAIL: 重装用的不是扫描到的域名: $(cat "$tmp/install-sni.txt")"; exit 1; }
grep -Fq '扫描推荐域名: scanned.example.com' "$tmp/rescan.out" || { echo 'FAIL: 没打印扫描推荐域名'; exit 1; }

# ---- 5) 扫描重装: 扫不到域名就停, 不调安装 ----
cat > "$tmp/scan-neighbors.sh" <<'SCAN'
#!/usr/bin/env bash
while [ "$#" -gt 0 ]; do case "$1" in --recommend-file) shift; : > "$1" ;; esac; shift; done
SCAN
chmod +x "$tmp/scan-neighbors.sh"
rm -f "$tmp/install-sni.txt"
if bash -c 'source "$1" "$2"; do_install() { printf "%s" "${REALITY_SNI:-}" > "$TMPDIR/install-sni.txt"; }; do_rescan_reinstall' "$tmp/reality" "$tmp/harness.sh" "$tmp" "$tmp" > "$tmp/rescan-empty.out" 2>&1; then
  echo 'FAIL: 没扫到域名, 重装居然继续了'; exit 1
fi
[ ! -f "$tmp/install-sni.txt" ] || { echo 'FAIL: 没扫到域名还调了安装'; exit 1; }

# ---- 6) 完全卸载 --purge: 配置、客户端文件、二维码、二进制全删 ----
touch "$tmp/client.png"
bash -c 'source "$1" "$2"; CLIENT_PNG="$3/client.png"; do_uninstall x --purge' _ "$tmp/harness.sh" "$tmp" "$tmp" > "$tmp/purge.out" 2>&1
grep -Fq '已彻底卸载' "$tmp/purge.out" || { echo 'FAIL: 完全卸载没报彻底卸载'; cat "$tmp/purge.out"; exit 1; }
[ ! -e "$tmp/xray-etc/config.json" ] && [ ! -e "$tmp/client.txt" ] && [ ! -e "$tmp/client.png" ] && [ ! -x "$tmp/xray" ] || { echo 'FAIL: 完全卸载后还有残留文件'; exit 1; }

# ---- 7) 菜单交互 (pty): 无效选择警告后回菜单, 选 4 输错确认词取消, 选 0 退出 ----
printf '9\n4\nno\n0\n' | timeout 15 script -qec "bash $tmp/reality" /dev/null > "$tmp/menu.out" 2>&1
grep -Fq '无效选择: 9' "$tmp/menu.out" || { echo 'FAIL: 菜单无效选择没警告'; cat "$tmp/menu.out"; exit 1; }
grep -Fq '已取消, 什么都没删' "$tmp/menu.out" || { echo 'FAIL: 菜单 4 输错确认词没取消'; cat "$tmp/menu.out"; exit 1; }
grep -Fq '1) 查看客户端配置 (Surge / QuanX / vless://)' "$tmp/menu.out" || { echo 'FAIL: 菜单里没显示选项 1'; cat "$tmp/menu.out"; exit 1; }

# ---- 8) 节点名: 城市映射 + 按 IP 生成三名字 + 查不到回退 ----
bash -c '
  source "$1" "$2"
  [ "$(city_code "Los Angeles" "US")" = "LA" ] || { echo "FAIL: Los Angeles 没映射成 LA"; exit 1; }
  [ "$(city_code "Frankfurt am Main" "DE")" = "FRA" ] || { echo "FAIL: Frankfurt 没映射成 FRA"; exit 1; }
  [ "$(city_code "Hong Kong" "HK")" = "HK" ] || { echo "FAIL: Hong Kong 没映射成 HK"; exit 1; }
  [ "$(city_code "Reykjavik" "IS")" = "REYKJAVIK" ] || { echo "FAIL: 不在映射表里的城市没转成全大写"; exit 1; }
  [ "$(city_code "" "DE")" = "DE" ] || { echo "FAIL: 没城市名时没用国家码"; exit 1; }
  geo_code() { printf "LA"; }
  unset REALITY_TAG
  show_info "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee" "cHViX2tleV9leGFtcGxlX2Jhc2U2NA==" "0123456789abcdef" "443" "www.amazon.com" > /dev/null
  grep -Fq "LA-Surge-Reality = vless, 203.0.113.1, 443" "$CLIENT_FILE" || { echo "FAIL: Surge 行名字不是 LA-Surge-Reality"; exit 1; }
  grep -Fq "tag=LA-Quanx-Reality" "$CLIENT_FILE" || { echo "FAIL: QuanX 行 tag 不是 LA-Quanx-Reality"; exit 1; }
  grep -Fq "#LA-Reality" "$CLIENT_FILE" || { echo "FAIL: vless 链接名字不是 LA-Reality"; exit 1; }
  geo_code() { :; }
  show_info "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee" "cHViX2tleV9leGFtcGxlX2Jhc2U2NA==" "0123456789abcdef" "443" "www.amazon.com" > /dev/null
  grep -Fq "Surge-Reality = vless, 203.0.113.1, 443" "$CLIENT_FILE" || { echo "FAIL: 查不到所在地时 Surge 行没回退到 Surge-Reality"; exit 1; }
  grep -Fq "tag=Quanx-Reality" "$CLIENT_FILE" || { echo "FAIL: 查不到所在地时 QuanX 行没回退到 Quanx-Reality"; exit 1; }
  grep -Fq "#Reality" "$CLIENT_FILE" || { echo "FAIL: 查不到所在地时 vless 链接没回退到 Reality"; exit 1; }
  grep -Fq "LA-" "$CLIENT_FILE" && { echo "FAIL: 回退后还有旧名字"; exit 1; }
  printf "%s\n" "节点名测试通过"
' _ "$tmp/harness.sh" "$tmp" || exit 1

# ---- 9) 自动换端口: 挑出来的端口都在 10000-30000 ----
bash -c '
  source "$1" "$2"
  for _ in $(seq 1 30); do
    p="$(pick_free_port)" || { echo "FAIL: pick_free_port 没挑到端口"; exit 1; }
    case "$p" in ""|*[!0-9]*) echo "FAIL: 挑到的不是数字: $p"; exit 1;; esac
    [ "$p" -ge 10000 ] && [ "$p" -le 30000 ] || { echo "FAIL: 挑到的端口 $p 不在 10000-30000"; exit 1; }
  done
  printf "%s\n" "自动换端口范围测试通过"
' _ "$tmp/harness.sh" "$tmp" || exit 1

printf '%s\n' '菜单、换端口、扫描重装、完全卸载测试全部通过'
