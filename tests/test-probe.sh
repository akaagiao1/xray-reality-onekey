#!/usr/bin/env bash
# 443 入站探活 fallback 测试 (不用真装 Xray, 全是替身; 配置校验另用真 Xray 二进制)
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

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
cp "$tmp/xray-etc/config.json" "$tmp/config-orig.json"

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
geo_code() { printf 'LA'; }
export REALITY_HOST="${REALITY_HOST:-203.0.113.1}"
export TMPDIR="$tmp"
HARNESS
chmod +x "$tmp/harness.sh"

# ---- 1) is_private_target: 内网/回环/ULA 算私有, 公网 IP 与域名不算 ----
bash -c '
  source "$1" "$2"
  for h in 10.0.0.1 192.168.1.1 127.0.0.1 172.16.0.1 172.31.255.1 ::1 fe80::1 FE80::1 fc00::1 FC00::1 fd12::1 localhost "[::1]"; do
    is_private_target "$h" || { echo "FAIL: $h 该算私有"; exit 1; }
  done
  for h in 8.8.8.8 172.32.0.1 203.0.113.1 2408:8656:f1f5:e222::c103 2606:4700:4700::1111 example.com "[2408:8656:f1f5:e222::c103]"; do
    is_private_target "$h" && { echo "FAIL: $h 不该算私有"; exit 1; }
  done
  printf "%s\n" "私有地址判断测试通过"
' _ "$tmp/harness.sh" "$tmp" || exit 1

# ---- 2) probe_one_node: 按 EDIS 返回的 status 解析, 探活失败/垃圾响应都算 unknown ----
bash -c '
  source "$1" "$2"
  curl() { printf "%s" "$CURL_BODY"; }
  run_case() {
    local want="$1" body="$2" got
    CURL_BODY="$body"
    got="$(probe_one_node at.edisglobal.com 203.0.113.1 443)"
    [ "$got" = "$want" ] || { echo "FAIL: probe_one_node 对 [$body] 应回 $want, 实际 $got"; exit 1; }
  }
  run_case open "{\"source\":\"Vienna NDC2\",\"target\":\"1.1.1.1\",\"status\":\"open\",\"connectTimeMs\":1.31}"
  run_case closed "{\"source\":\"Vienna NDC2\",\"target\":\"38.190.222.177\",\"status\":\"closed\"}"
  run_case closed "{\"source\":\"Vienna NDC2\",\"status\":\"timeout\"}"
  run_case closed "{\"source\":\"Vienna NDC2\",\"status\":\"unreachable\"}"
  run_case unknown "{\"source\":\"Vienna NDC2\",\"status\":\"cancelled\"}"
  run_case unknown "{\"source\":\"Vienna NDC2\",\"status\":\"unavailable\"}"
  run_case unknown "not json at all"
  run_case unknown "{\"error\":\"invalid_url\"}"
  curl() { return 7; }
  [ "$(probe_one_node at.edisglobal.com 203.0.113.1 443)" = "unknown" ] || { echo "FAIL: curl 失败时应回 unknown"; exit 1; }
  # IPv6 地址传给探活时去掉方括号 (EDIS 要裸地址)
  curl() { printf "%s\n" "$@" > "$CURL_ARGS"; printf "{\"status\":\"open\"}"; }
  CURL_ARGS="$tmp/curl.args" probe_one_node at.edisglobal.com "[2408:8656:f1f5:e222::c103]" 443 >/dev/null
  grep -Fq "target=2408:8656:f1f5:e222::c103" "$tmp/curl.args" || { echo "FAIL: 探活没收到裸 IPv6 地址"; cat "$tmp/curl.args"; exit 1; }
  grep -Fq "[" "$tmp/curl.args" && { echo "FAIL: 探活收到的 IPv6 地址还带方括号"; exit 1; }
  printf "%s\n" "单节点探活解析测试通过"
' _ "$tmp/harness.sh" "$tmp" || exit 1

# ---- 3) probe_port_external: 一通即通, 两堵才堵, 其余 unknown ----
# 替身 probe_one_node 从队列文件里按顺序取值 (命令替换是子 shell, 只能用文件传状态)
cat > "$tmp/queue-stub.sh" <<'QSTUB'
probe_one_node() {
  local line
  line="$(head -1 "$QUEUE")"
  tail -n +2 "$QUEUE" > "$QUEUE.tmp"; mv "$QUEUE.tmp" "$QUEUE"
  printf '%s' "$line"
}
QSTUB
probe_case() { # $1=期望 $2..=队列值
  local want="$1"; shift
  printf '%s\n' "$@" > "$tmp/queue.txt"
  local got
  got="$(QUEUE="$tmp/queue.txt" bash -c 'source "$1" "$2"; source "$3"; probe_port_external 203.0.113.1 443' _ "$tmp/harness.sh" "$tmp" "$tmp/queue-stub.sh")"
  [ "$got" = "$want" ] || { echo "FAIL: 队列 [$*] 应回 $want, 实际 $got"; exit 1; }
}
probe_case open open closed
probe_case closed closed closed
probe_case unknown closed unknown
probe_case unknown unknown closed
probe_case unknown unknown unknown
probe_case open unknown open
printf '%s\n' '双节点判定测试通过'

# ---- 4) probe_fallback <模式>: 堵了只换该模式的端口, 另一模式不动, stdout 只有端口号 ----
# 双入站夹具: 模式 3 在 443, 模式 1 在高端口; 模式 3 的 decryption 是假值 (假 xray 不校验),
# §9 用真 xray 校验前会换成真值。
DEC43="mlkem768x25519plus.native.600s.$(printf 'A%.0s' $(seq 1 43))"
jq -n --arg dec "$DEC43" '{inbounds: [
  {tag: "vless-reality", port: 24431, protocol: "vless",
   settings: {clients: [{id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", flow: "xtls-rprx-vision"}], decryption: "none"},
   streamSettings: {network: "tcp", security: "reality",
     realitySettings: {show: false, target: "www.amazon.com:443", xver: 0, serverNames: ["www.amazon.com"], privateKey: "cHJpdl9leGFtcGxl", shortIds: ["0123456789abcdef"]}}},
  {tag: "vless-reality-enc", port: 443, protocol: "vless",
   settings: {clients: [{id: "cccccccc-bbbb-cccc-dddd-eeeeeeeeeeee", flow: "xtls-rprx-vision"}], decryption: $dec},
   streamSettings: {network: "tcp", security: "reality",
     realitySettings: {show: false, target: "www.amazon.com:443", xver: 0, serverNames: ["www.amazon.com"], privateKey: "cHJpdl9leGFtcGxl", shortIds: ["0123456789abcdef"]}}}
], outbounds: [{protocol: "freedom", tag: "direct"}, {protocol: "blackhole", tag: "block"}]}' > "$tmp/config-two.json"
cat > "$tmp/verdict-stub.sh" <<'VSTUB'
probe_port_external() { [ -n "${ARGS_LOG:-}" ] && printf 'probe_port_external %s %s\n' "$@" >> "$ARGS_LOG"; printf '%s' "$VERDICT"; }
probe_one_node() { [ -n "${ARGS_LOG:-}" ] && printf '%s %s %s\n' "$@" >> "$ARGS_LOG"; printf '%s' "$VERDICT2"; }
VSTUB
fallback_case() { # $1=verdict $2=verdict2 ; 跑一次 probe_fallback 3, 输出 stdout/stderr/配置到 $tmp/fb.*
  local v="$1" v2="$2"
  cp "$tmp/config-two.json" "$tmp/xray-etc/config.json"
  rm -f "$tmp/fb.args"
  VERDICT="$v" VERDICT2="$v2" ARGS_LOG="$tmp/fb.args" bash -c '
    source "$1" "$2"; source "$3"
    probe_fallback 3 > "$4/fb.stdout" 2> "$4/fb.stderr"
  ' _ "$tmp/harness.sh" "$tmp" "$tmp/verdict-stub.sh" "$tmp" || { echo 'FAIL: probe_fallback 退出了'; cat "$tmp/fb.stderr"; exit 1; }
}
fallback_case closed open
new_port="$(cat "$tmp/fb.stdout")"
case "$new_port" in ''|*[!0-9]*) echo "FAIL: fallback 输出的不是纯端口号: [$new_port]"; exit 1 ;; esac
[ "$new_port" -ge 10000 ] && [ "$new_port" -le 30000 ] || { echo "FAIL: fallback 换的端口 $new_port 不在 10000-30000"; exit 1; }
[ "$(jq -r '.inbounds[] | select(.tag=="vless-reality-enc") | .port' "$tmp/xray-etc/config.json")" = "$new_port" ] || { echo 'FAIL: 模式 3 端口没换成新端口'; exit 1; }
[ "$(jq -r '.inbounds[] | select(.tag=="vless-reality") | .port' "$tmp/xray-etc/config.json")" = "24431" ] || { echo 'FAIL: fallback 时模式 1 的端口被动了'; exit 1; }
[ "$(jq -r '.inbounds[] | select(.tag=="vless-reality-enc") | .settings.clients[0].id' "$tmp/xray-etc/config.json")" = "cccccccc-bbbb-cccc-dddd-eeeeeeeeeeee" ] || { echo 'FAIL: fallback 时 UUID 被改了'; exit 1; }
[ "$(jq -r '.inbounds[] | select(.tag=="vless-reality-enc") | .streamSettings.realitySettings.privateKey' "$tmp/xray-etc/config.json")" = "cHJpdl9leGFtcGxl" ] || { echo 'FAIL: fallback 时私钥被改了'; exit 1; }
[ "$(jq -r '.inbounds[] | select(.tag=="vless-reality-enc") | .streamSettings.realitySettings.shortIds[0]' "$tmp/xray-etc/config.json")" = "0123456789abcdef" ] || { echo 'FAIL: fallback 时 shortId 被改了'; exit 1; }
[ "$(jq -r '.inbounds[] | select(.tag=="vless-reality-enc") | .streamSettings.realitySettings.serverNames[0]' "$tmp/xray-etc/config.json")" = "www.amazon.com" ] || { echo 'FAIL: fallback 时域名被改了'; exit 1; }
grep -Fq "端口已改: 443 -> $new_port" "$tmp/fb.stderr" || { echo 'FAIL: fallback 没报端口变化'; cat "$tmp/fb.stderr"; exit 1; }
grep -Fq "探活确认: 203.0.113.1:${new_port} 外面连得进来" "$tmp/fb.stderr" || { echo 'FAIL: fallback 后没确认新端口'; cat "$tmp/fb.stderr"; exit 1; }
cp "$tmp/xray-etc/config.json" "$tmp/config-fallback.json"
printf '%s\n' '探活 fallback 换端口测试通过'

# 通 / 没结论时保持 443, 配置不动
fallback_case open open
[ "$(cat "$tmp/fb.stdout")" = "443" ] || { echo 'FAIL: 探活通时端口被改了'; exit 1; }
cmp -s "$tmp/xray-etc/config.json" "$tmp/config-two.json" || { echo 'FAIL: 探活通时配置被改了'; exit 1; }
fallback_case unknown unknown
[ "$(cat "$tmp/fb.stdout")" = "443" ] || { echo 'FAIL: 探活没结论时端口被改了'; exit 1; }
cmp -s "$tmp/xray-etc/config.json" "$tmp/config-two.json" || { echo 'FAIL: 探活没结论时配置被改了'; exit 1; }
printf '%s\n' '探活通/没结论保持 443 测试通过'

# ---- 5) 不探活的几种情况: SKIP 开关 / 模式不在 443 上 / 内网地址, 探活函数一次都不该被调 ----
no_probe_case() { # $1=描述 $2=模式 ; VERDICT/VERDICT2/ARGS_LOG/REALITY_SKIP_PROBE/REALITY_HOST 由调用方指定
  local desc="$1" mode="$2"
  cp "$tmp/config-two.json" "$tmp/xray-etc/config.json"
  rm -f "$tmp/fb.args"
  env "VERDICT=${VERDICT:-}" "VERDICT2=${VERDICT2:-}" "ARGS_LOG=${ARGS_LOG:-}" \
      "REALITY_SKIP_PROBE=${REALITY_SKIP_PROBE:-0}" "REALITY_HOST=${REALITY_HOST:-203.0.113.1}" \
      bash -c '
    source "$1" "$2"; source "$3"
    probe_fallback "$5" > "$4/fb.stdout" 2> "$4/fb.stderr"
  ' _ "$tmp/harness.sh" "$tmp" "$tmp/verdict-stub.sh" "$tmp" "$mode" || { echo "FAIL: $desc 时 probe_fallback 退出了"; exit 1; }
  [ -f "$tmp/fb.args" ] && { echo "FAIL: $desc 时不该调探活, 却调了"; exit 1; }
  cmp -s "$tmp/xray-etc/config.json" "$tmp/config-two.json" || { echo "FAIL: $desc 时配置被改了"; exit 1; }
}
VERDICT=closed VERDICT2=open ARGS_LOG="$tmp/fb.args" REALITY_SKIP_PROBE=1 no_probe_case "SKIP 开关" 3
[ "$(cat "$tmp/fb.stdout")" = "443" ] || { echo 'FAIL: SKIP 开关时端口变了'; exit 1; }
VERDICT=closed VERDICT2=open ARGS_LOG="$tmp/fb.args" no_probe_case "模式不在 443 上" 1
[ "$(cat "$tmp/fb.stdout")" = "24431" ] || { echo 'FAIL: 模式不在 443 上时端口变了'; exit 1; }
VERDICT=closed VERDICT2=open ARGS_LOG="$tmp/fb.args" REALITY_HOST=10.0.0.1 no_probe_case "内网地址" 3
[ "$(cat "$tmp/fb.stdout")" = "443" ] || { echo 'FAIL: 内网地址时端口变了'; exit 1; }
printf '%s\n' '不探活场景测试通过'

# ---- 6) IPv6 地址原样传给探活 (去方括号, 不丢地址) ----
cp "$tmp/config-two.json" "$tmp/xray-etc/config.json"
rm -f "$tmp/fb.args"
VERDICT=closed VERDICT2=open ARGS_LOG="$tmp/fb.args" REALITY_HOST='[2408:8656:f1f5:e222::c103]' bash -c '
  source "$1" "$2"; source "$3"
  probe_fallback 3 > "$4/fb.stdout" 2> "$4/fb.stderr"
' _ "$tmp/harness.sh" "$tmp" "$tmp/verdict-stub.sh" "$tmp" || { echo 'FAIL: IPv6 地址 fallback 退出了'; exit 1; }
grep -Fq '2408:8656:f1f5:e222::c103' "$tmp/fb.args" || { echo 'FAIL: 探活没收到 IPv6 地址'; cat "$tmp/fb.args" 2>/dev/null; exit 1; }
v6_port="$(cat "$tmp/fb.stdout")"
[ "$v6_port" -ge 10000 ] && [ "$v6_port" -le 30000 ] || { echo "FAIL: IPv6 地址 fallback 没换高端口: $v6_port"; exit 1; }
printf '%s\n' 'IPv6 地址传递测试通过'

# ---- 7) do_probe: 只测不改, 三种结果各报一句; 没配置时报错 ----
cp "$tmp/config-orig.json" "$tmp/xray-etc/config.json"
VERDICT=open bash -c 'source "$1" "$2"; probe_port_external() { printf "%s" "$VERDICT"; }; do_probe' _ "$tmp/harness.sh" "$tmp" > "$tmp/probe-open.out" 2>&1
grep -Fq '结果: 通, 203.0.113.1:443 外面连得进来' "$tmp/probe-open.out" || { echo 'FAIL: do_probe 通时没报通'; cat "$tmp/probe-open.out"; exit 1; }
VERDICT=closed bash -c 'source "$1" "$2"; probe_port_external() { printf "%s" "$VERDICT"; }; do_probe' _ "$tmp/harness.sh" "$tmp" > "$tmp/probe-closed.out" 2>&1
grep -Fq '结果: 不通' "$tmp/probe-closed.out" || { echo 'FAIL: do_probe 不通时没报不通'; cat "$tmp/probe-closed.out"; exit 1; }
VERDICT=unknown bash -c 'source "$1" "$2"; probe_port_external() { printf "%s" "$VERDICT"; }; do_probe' _ "$tmp/harness.sh" "$tmp" > "$tmp/probe-unknown.out" 2>&1
grep -Fq '结果: 没结论' "$tmp/probe-unknown.out" || { echo 'FAIL: do_probe 没结论时没报没结论'; cat "$tmp/probe-unknown.out"; exit 1; }
cmp -s "$tmp/xray-etc/config.json" "$tmp/config-orig.json" || { echo 'FAIL: do_probe 改了配置'; exit 1; }
mv "$tmp/xray-etc/config.json" "$tmp/config-hidden.json"
if bash -c 'source "$1" "$2"; do_probe' _ "$tmp/harness.sh" "$tmp" > "$tmp/probe-noconfig.out" 2>&1; then
  echo 'FAIL: 没配置时 do_probe 居然没报错'; exit 1
fi
mv "$tmp/config-hidden.json" "$tmp/xray-etc/config.json"
printf '%s\n' 'do_probe 测试通过'

# ---- 8) 全链路: do_install 走探活 fallback, 客户端文件按新端口生成 ----
cp "$tmp/config-orig.json" "$tmp/xray-etc/config.json"
rm -f "$tmp/client.txt"
VERDICT=closed VERDICT2=open bash -c '
  source "$1" "$2"; source "$3"
  REALITY_SNI=www.amazon.com do_install > "$4/install.out" 2>&1
' _ "$tmp/harness.sh" "$tmp" "$tmp/verdict-stub.sh" "$tmp" || { echo 'FAIL: do_install 退出了'; cat "$tmp/install.out"; exit 1; }
inst_port="$(jq -r '.inbounds[0].port' "$tmp/xray-etc/config.json")"
[ "$inst_port" -ge 10000 ] && [ "$inst_port" -le 30000 ] || { echo "FAIL: 安装后端口 $inst_port 不在高端口范围"; exit 1; }
grep -Fq "203.0.113.1:${inst_port}" "$tmp/client.txt" || { echo 'FAIL: 客户端文件里没新端口'; exit 1; }
grep -Fq "= vless, 203.0.113.1, ${inst_port}" "$tmp/client.txt" || { echo 'FAIL: 客户端文件里 Surge 行没新端口'; exit 1; }
grep -Fq "端口已改: 443 -> ${inst_port}" "$tmp/install.out" || { echo 'FAIL: 安装输出里没报 fallback'; cat "$tmp/install.out"; exit 1; }
printf '%s\n' '安装全链路 fallback 测试通过'

# ---- 9) 真 Xray 二进制校验 fallback 生成的配置 ----
arch="$(uname -m)"
case "$arch" in
  x86_64|amd64) asset="Xray-linux-64.zip" ;;
  aarch64|arm64) asset="Xray-linux-arm64-v8a.zip" ;;
  *) printf '%s\n' "跳过真二进制校验: 不支持的架构 $arch"; asset="" ;;
esac
if [ -n "$asset" ]; then
  ver="v26.10.31"
  url="https://github.com/XTLS/Xray-core/releases/download/${ver}/${asset}"
  mkdir -p "$tmp/realxray"
  curl -fL --retry 2 --max-time 120 -o "$tmp/realxray/xray.zip" "$url" || { echo 'FAIL: 真 Xray 下载失败'; exit 1; }
  if curl -fsSL --max-time 30 -o "$tmp/realxray/xray.zip.dgst" "${url}.dgst" 2>/dev/null; then
    # .dgst 里是 SHA2-256= 写法 (不是 SHA256), 两个都认; 找不到就大声失败, 别静默跳过校验
    want="$(grep -iE 'SHA2-256|SHA256' "$tmp/realxray/xray.zip.dgst" | head -1 | awk '{print $NF}')" || true
    [ -n "$want" ] || { echo 'FAIL: .dgst 里没找到 sha256'; exit 1; }
    got="$(sha256sum "$tmp/realxray/xray.zip" | awk '{print $1}')"
    [ "$got" = "$want" ] || { echo 'FAIL: 真 Xray sha256 不符'; exit 1; }
  fi
  unzip -o -q "$tmp/realxray/xray.zip" -d "$tmp/realxray" || { echo 'FAIL: 真 Xray 解压失败'; exit 1; }
  # 替身配置里的私钥/Encryption 密钥是假值, 真 Xray 校验格式会拒;
  # 换成真 x25519 私钥与真 vlessenc decryption 再验结构 (所有 Reality 入站都要换)
  real_priv="$("$tmp/realxray/xray" x25519 2>/dev/null | grep -i 'private' | head -1 | sed -E 's/.*:[[:space:]]*//;s/[[:space:]]//g')"
  [ -n "$real_priv" ] || { echo 'FAIL: 真 Xray 生成密钥失败'; exit 1; }
  real_dec="$("$tmp/realxray/xray" vlessenc 2>/dev/null | grep -m1 'decryption' | sed -E 's/.*"decryption": "([^"]+)".*/\1/')"
  [ -n "$real_dec" ] || { echo 'FAIL: 真 Xray 生成 vlessenc 密钥失败'; exit 1; }
  fix_keys() { # $1=输入 $2=输出 : 所有入站的 Reality 私钥与非 none 的 decryption 都换真值
    jq --arg k "$real_priv" --arg d "$real_dec" \
      '.inbounds |= map(if .streamSettings.realitySettings then .streamSettings.realitySettings.privateKey = $k else . end
        | if (.settings.decryption // "none") != "none" then .settings.decryption = $d else . end)' \
      "$1" > "$2"
  }
  fix_keys "$tmp/config-fallback.json" "$tmp/config-fallback-real.json"
  fix_keys "$tmp/xray-etc/config.json" "$tmp/config-install-real.json"
  out="$("$tmp/realxray/xray" -test -config "$tmp/config-fallback-real.json" 2>&1)" || { echo "FAIL: 真 Xray 校验 fallback 配置不通过: $out"; exit 1; }
  out="$("$tmp/realxray/xray" -test -config "$tmp/config-install-real.json" 2>&1)" || { echo "FAIL: 真 Xray 校验安装后配置不通过: $out"; exit 1; }
  printf '%s\n' '真 Xray 配置校验通过'
fi

printf '%s\n' '443 入站探活 fallback 测试全部通过'
