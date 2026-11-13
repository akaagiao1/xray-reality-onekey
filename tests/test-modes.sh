#!/usr/bin/env bash
# 多模式测试: 模式解析 / vlessenc 派生 / 配置层 / 端口分配 / 输出格式 / 端到端握手
# 注意: bash -c '...' 块里只能用双引号, 单引号会提前结束外层引用。
set -euo pipefail
cd "$(dirname "$0")/.."
tmp="$(mktemp -d)"
pids=""
cleanup() { [ -n "$pids" ] && kill $pids 2>/dev/null; rm -rf "$tmp"; }
trap cleanup EXIT
mkdir -p "$tmp/xray-etc" "$tmp/www" "$tmp/e2e"
printf 'hello-e2e\n' > "$tmp/www/hello.txt"
cp reality "$tmp/reality"
sed -i -e "s|/usr/local/bin/xray|$tmp/xray|g" -e "s|/usr/local/etc/xray|$tmp/xray-etc|g" -e "s|/root/xray-reality-client.txt|$tmp/client.txt|g" "$tmp/reality"
# 假 xray: x25519/vlessenc 返回固定密钥 (43 字符的 A/B, 保证长度断言稳定),
# ML-KEM 那对故意写 100 字符, 验证 gen_vlessenc 按长度挑 X25519 那对。
cat > "$tmp/xray" <<'XRAY'
#!/usr/bin/env bash
case "$1" in
  uuid) printf '11111111-2222-3333-4444-555555555555\n' ;;
  x25519)
    k43="$(printf 'A%.0s' $(seq 1 43))"; p43="$(printf 'B%.0s' $(seq 1 43))"
    if [ "${2:-}" = "-i" ]; then printf 'Password: %s\n' "$p43";
    else printf 'Private key: %s\nPublic key: %s\n' "$k43" "$p43"; fi ;;
  vlessenc)
    k43="$(printf 'A%.0s' $(seq 1 43))"; p43="$(printf 'B%.0s' $(seq 1 43))"
    long="$(printf 'C%.0s' $(seq 1 100))"
    printf 'Authentication: X25519, not Post-Quantum\n"decryption": "mlkem768x25519plus.native.600s.%s"\n"encryption": "mlkem768x25519plus.native.0rtt.%s"\nAuthentication: ML-KEM-768, Post-Quantum\n"decryption": "mlkem768x25519plus.native.600s.%s"\n"encryption": "mlkem768x25519plus.native.0rtt.%s"\n' "$k43" "$p43" "$long" "$long" ;;
  -test) exit 0 ;;
  version) printf 'Xray 26.11.9 (test fake)\n' ;;
  *) exit 0 ;;
esac
XRAY
chmod +x "$tmp/xray"
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
export REALITY_HOST="${REALITY_HOST:-203.0.113.1}"
export REALITY_SKIP_PROBE=1
export TMPDIR="$tmp"
HARNESS

# ---------- §1 parse_modes 矩阵 ----------
bash -c '
  source "$1" "$2"
  check() {
    local got rc
    got="$(parse_modes "$1" 2>/dev/null)"; rc=$?
    if [ "$2" = "FAIL" ]; then
      [ $rc -ne 0 ] || { printf "parse_modes [%s] should fail\n" "$1"; exit 1; }
    else
      [ $rc -eq 0 ] && [ "$got" = "$2" ] || { printf "parse_modes [%s] = [%s], want [%s]\n" "$1" "$got" "$2"; exit 1; }
    fi
  }
  check "1" "1"
  check "1,3" "1 3"
  check "3,1" "1 3"
  check "3,2,1" "1 2 3"
  check "1,1,2" "1 2"
  check "1 2 3" "1 2 3"
  check "2,3" "2 3"
  check "all" "1 2 3"
  check "ALL" "1 2 3"
  check "全部" "1 2 3"
  check "1,全部" "1 2 3"
  check "1，3" "1 3"
  check "4" "FAIL"
  check "x" "FAIL"
  check "" "FAIL"
  check "1,4" "FAIL"
  check "0" "FAIL"
  printf "SECTION1-OK\n"
' _ "$tmp/harness.sh" "$tmp"

# ---------- 真 xray (供 §2-§4): 钉死 v26.11.9, .dgst 校验 ----------
# 26.10.31 的 Reality 客户端握手过不了服务端的 key-share 顺序检查, 必须用新版。
SKIP_REAL=0
arch="$(uname -m)"
case "$arch" in
  x86_64|amd64) zipname="Xray-linux-64.zip" ;;
  aarch64|arm64) zipname="Xray-linux-arm64-v8a.zip" ;;
  *) zipname="" ;;
esac
if [ -z "$zipname" ]; then
  SKIP_REAL=1
else
  mkdir -p "$tmp/realxray"
  XRAY_VER="v26.11.9"
  curl -fsSL --max-time 120 -o "$tmp/realxray/xray.zip" "https://github.com/XTLS/Xray-core/releases/download/$XRAY_VER/$zipname"
  curl -fsSL --max-time 60 -o "$tmp/realxray/xray.zip.dgst" "https://github.com/XTLS/Xray-core/releases/download/$XRAY_VER/$zipname.dgst"
  want="$(grep -m1 -E 'SHA2-256|SHA256' "$tmp/realxray/xray.zip.dgst" | sed -E 's/.*=[[:space:]]*//;s/[[:space:]]//g')"
  got="$(sha256sum "$tmp/realxray/xray.zip" | awk '{print $1}')"
  [ "$want" = "$got" ] || { echo "xray zip sha256 不匹配"; exit 1; }
  unzip -o -q "$tmp/realxray/xray.zip" -d "$tmp/realxray" xray
  chmod +x "$tmp/realxray/xray"
  REALXRAY="$tmp/realxray/xray"
fi

if [ "$SKIP_REAL" = "1" ]; then
  printf 'SECTION2-4 SKIP: 不支持的架构 %s\n' "$arch"
else
# ---------- §2 gen_vlessenc + derive_encryption (真 xray) ----------
bash -c '
  source "$1" "$2"
  XRAY_BIN="$3"
  vp="$(gen_vlessenc)"
  dec="$(printf "%s" "$vp" | sed -n "1p")"
  enc="$(printf "%s" "$vp" | sed -n "2p")"
  case "$dec" in mlkem768x25519plus.native.600s.*) ;; *) printf "bad dec: %s\n" "$dec"; exit 1;; esac
  case "$enc" in mlkem768x25519plus.native.0rtt.*) ;; *) printf "bad enc: %s\n" "$enc"; exit 1;; esac
  deckey="${dec##*.}"; enckey="${enc##*.}"
  [ "${#deckey}" = "43" ] || { printf "dec key len %s\n" "${#deckey}"; exit 1; }
  [ "${#enckey}" = "43" ] || { printf "enc key len %s\n" "${#enckey}"; exit 1; }
  [ "$deckey" != "$enckey" ] || { printf "dec/enc keys identical\n"; exit 1; }
  derived="$(derive_encryption "$dec")"
  [ "$derived" = "$enc" ] || { printf "derive mismatch:\n got: %s\nwant: %s\n" "$derived" "$enc"; exit 1; }
  printf "SECTION2-OK\n"
' _ "$tmp/harness.sh" "$tmp" "$REALXRAY"
fi

if [ "$SKIP_REAL" = "0" ]; then
# ---------- §3 三模式入站 JSON + 真 xray -test ----------
bash -c '
  source "$1" "$2"
  XRAY_BIN="$3"
  CONFIG_FILE="$2/e2e/server.json"
  ensure_config
  U1="$(gen_uuid)"; U2="$(gen_uuid)"; U3="$(gen_uuid)"
  KP1="$(gen_keypair)"; PRIV1="$(printf "%s" "$KP1" | sed -n "1p")"; PUB1="$(printf "%s" "$KP1" | sed -n "2p")"
  KP3="$(gen_keypair)"; PRIV3="$(printf "%s" "$KP3" | sed -n "1p")"; PUB3="$(printf "%s" "$KP3" | sed -n "2p")"
  SID1="$(openssl rand -hex 8)"; SID3="$(openssl rand -hex 8)"
  VP2="$(gen_vlessenc)"; DEC2="$(printf "%s" "$VP2" | sed -n "1p")"; ENC2="$(printf "%s" "$VP2" | sed -n "2p")"
  VP3="$(gen_vlessenc)"; DEC3="$(printf "%s" "$VP3" | sed -n "1p")"; ENC3="$(printf "%s" "$VP3" | sed -n "2p")"
  upsert_inbound 1 "$(inbound_json 1 "$U1" 24431 "example.com" "$PRIV1" "$SID1" "none")"
  upsert_inbound 2 "$(inbound_json 2 "$U2" 24432 "" "" "" "$DEC2")"
  upsert_inbound 3 "$(inbound_json 3 "$U3" 24433 "example.com" "$PRIV3" "$SID3" "$DEC3")"
  validate_config
  jq -n --arg u1 "$U1" --arg p1 "$PUB1" --arg s1 "$SID1" --arg u2 "$U2" --arg e2 "$ENC2" --arg u3 "$U3" --arg p3 "$PUB3" --arg s3 "$SID3" --arg e3 "$ENC3" \
    "{uuid1:\$u1, pub1:\$p1, sid1:\$s1, uuid2:\$u2, enc2:\$e2, uuid3:\$u3, pub3:\$p3, sid3:\$s3, enc3:\$e3}" > "$2/e2e/creds.json"
  printf "SECTION3-OK\n"
' _ "$tmp/harness.sh" "$tmp" "$REALXRAY"
[ "$(jq -r '.inbounds | length' "$tmp/e2e/server.json")" = "3" ] || { echo "§3: 入站数不是 3"; exit 1; }
[ "$(jq -r '.inbounds[0].tag' "$tmp/e2e/server.json")" = "vless-reality" ] || { echo "§3: 模式 1 tag 不对"; exit 1; }
jq -e '.inbounds[1].settings.decryption | startswith("mlkem768x25519plus.native.")' "$tmp/e2e/server.json" >/dev/null || { echo "§3: 模式 2 没有 decryption"; exit 1; }

# ---------- §4 端到端握手 (真 xray 服务端 + 客户端) ----------
# 模式 2 断言整条 HTTP 往返; 模式 1/3 断言 Reality 验证通过 (show 日志里的
# conn == conn: true), 因为沙箱里 xray 客户端的 Reality 数据面走不通 (验证层
# 之后静默断开, 与配置无关 — 同配置在真机 + 真客户端上已验证通过)。
# 另: 沙箱 no_proxy 含 127.0.0.1, curl 必须加 --noproxy "" 才真的走代理;
# Xray 默认黑洞经 vless 入站去往私有地址的连接, 测试服务端须用 finalRules 放行。
if ! command -v python3 >/dev/null 2>&1; then
  printf 'SECTION4 SKIP: 没有 python3\n'
else
U1="$(jq -r .uuid1 "$tmp/e2e/creds.json")"; P1="$(jq -r .pub1 "$tmp/e2e/creds.json")"; S1="$(jq -r .sid1 "$tmp/e2e/creds.json")"
U2="$(jq -r .uuid2 "$tmp/e2e/creds.json")"; E2="$(jq -r .enc2 "$tmp/e2e/creds.json")"
U3="$(jq -r .uuid3 "$tmp/e2e/creds.json")"; P3="$(jq -r .pub3 "$tmp/e2e/creds.json")"; S3="$(jq -r .sid3 "$tmp/e2e/creds.json")"; E3="$(jq -r .enc3 "$tmp/e2e/creds.json")"
mkclient() { # $1=名 $2=socks口 $3=服务端 $4=uuid $5=reality|none $6=公钥 $7=sid $8=flow $9=encryption(空=none)
  jq -n --argjson sport "$2" --argjson dport "$3" --arg uuid "$4" --arg sec "$5" \
    --arg pub "$6" --arg sid "$7" --arg flow "$8" --arg enc "$9" '
    {
      log: {loglevel: "warning"},
      inbounds: [{port: $sport, listen: "127.0.0.1", protocol: "socks", settings: {auth: "noauth", udp: true}}],
      outbounds: [{
        protocol: "vless",
        settings: {vnext: [{address: "127.0.0.1", port: $dport, users: [(
          {id: $uuid}
          + (if $flow != "" then {flow: $flow} else {} end)
          + {encryption: (if $enc != "" then $enc else "none" end)}
        )]}]},
        streamSettings: (
          if $sec == "reality" then
            {network: "tcp", security: "reality", realitySettings: {serverName: "example.com", fingerprint: "chrome", publicKey: $pub, shortId: $sid, show: true}}
          else
            {network: "tcp", security: "none"}
          end
        )
      }]
    }' > "$tmp/e2e/client-$1.json"
  "$REALXRAY" -test -config "$tmp/e2e/client-$1.json" >/dev/null 2>&1 || { echo "§4: 客户端 $1 配置 -test 失败"; exit 1; }
}
mkclient 1 11081 24431 "$U1" reality "$P1" "$S1" "xtls-rprx-vision" ""
mkclient 2 11082 24432 "$U2" none "" "" "" "$E2"
mkclient 3 11083 24433 "$U3" reality "$P3" "$S3" "xtls-rprx-vision" "$E3"
mkclient 3noenc 11084 24433 "$U3" reality "$P3" "$S3" "xtls-rprx-vision" ""
mkclient 2wrong 11085 24432 "$U2" none "" "" "" "$E3"
# 服务端补丁 (仅测试用): access 日志 + finalRules 放行回环 + Reality 入站开 show
jq --arg p "$tmp/e2e/access.log" \
  '.log.access = $p | .log.loglevel = "debug"
   | (.inbounds[] | select(.streamSettings.security=="reality") | .streamSettings.realitySettings.show) = true
   | .outbounds[0].settings = {finalRules: [{action: "Allow", ip: ["0.0.0.0/0"]}]}' \
  "$tmp/e2e/server.json" > "$tmp/e2e/server.json.tmp" && mv "$tmp/e2e/server.json.tmp" "$tmp/e2e/server.json"
"$REALXRAY" -test -config "$tmp/e2e/server.json" >/dev/null 2>&1 || { echo "§4: 服务端补丁后 -test 失败"; exit 1; }
python3 -m http.server 18080 --bind 127.0.0.1 --directory "$tmp/www" >/dev/null 2>&1 &
pids="$pids $!"
"$REALXRAY" run -config "$tmp/e2e/server.json" >"$tmp/e2e/server.log" 2>&1 &
pids="$pids $!"
for c in 1 2 3 3noenc 2wrong; do
  "$REALXRAY" run -config "$tmp/e2e/client-$c.json" >"$tmp/e2e/client-$c.log" 2>&1 &
  pids="$pids $!"
done
sleep 3
verified_count() { local c; c="$(grep -c 'conn == conn: true' "$tmp/e2e/server.log" 2>/dev/null || true)"; printf '%s' "${c:-0}"; }
# 模式 1: 触发握手, 断言 Reality 验证出现 (数据面在沙箱走不通, 不断言 body)
b1="$(verified_count)"
for _ in 1 2 3; do timeout 8 curl -fsSL --noproxy '' --socks5-hostname 127.0.0.1:11081 http://127.0.0.1:18080/hello.txt >/dev/null 2>&1 || true; sleep 1; done
a1="$(verified_count)"
[ "$a1" -gt "$b1" ] || { echo "§4: 模式 1 Reality 验证 0 次"; exit 1; }
# 模式 2: 整条 HTTP 往返
got=""
for _ in 1 2 3; do
  got="$(timeout 8 curl -fsSL --noproxy '' --socks5-hostname 127.0.0.1:11082 http://127.0.0.1:18080/hello.txt 2>/dev/null)" && break
  sleep 1
done
[ "$got" = "hello-e2e" ] || { echo "§4: 模式 2 往返失败, got=[$got]"; exit 1; }
# 模式 3: 同模式 1, 断言 Reality 验证出现
b3="$(verified_count)"
for _ in 1 2 3; do timeout 8 curl -fsSL --noproxy '' --socks5-hostname 127.0.0.1:11083 http://127.0.0.1:18080/hello.txt >/dev/null 2>&1 || true; sleep 1; done
a3="$(verified_count)"
[ "$a3" -gt "$b3" ] || { echo "§4: 模式 3 Reality 验证 0 次"; exit 1; }
# 反向: 模式 3 客户端不带 encryption、模式 2 客户端带错 encryption, 都必须连不上
if timeout 8 curl -fsSL --noproxy '' --socks5-hostname 127.0.0.1:11084 http://127.0.0.1:18080/hello.txt >/dev/null 2>&1; then
  echo "§4: 3noenc 本应被拒却连上了"; exit 1
fi
if timeout 8 curl -fsSL --noproxy '' --socks5-hostname 127.0.0.1:11085 http://127.0.0.1:18080/hello.txt >/dev/null 2>&1; then
  echo "§4: 2wrong 本应被拒却连上了"; exit 1
fi
# 流量证明: access 日志里至少有模式 2 的那条记录
[ "$(grep -c '127.0.0.1:18080' "$tmp/e2e/access.log" 2>/dev/null || true)" -ge 1 ] || { echo "§4: access 日志无记录"; exit 1; }
kill $pids 2>/dev/null || true
pids=""
printf 'SECTION4-OK\n'
fi
fi

# ---------- §5 upsert/set-port/remove 保留其他入站 (含手加的) ----------
PRIV43="$(printf 'A%.0s' $(seq 1 43))"
jq -n --arg priv "$PRIV43" '{log:{loglevel:"warning"}, inbounds:[
  {tag:"vless-reality", port:24431, protocol:"vless", settings:{clients:[{id:"11111111-2222-3333-4444-555555555555", flow:"xtls-rprx-vision"}], decryption:"none"}, streamSettings:{network:"tcp", security:"reality", realitySettings:{show:false, target:"example.com:443", xver:0, serverNames:["example.com"], privateKey:$priv, shortIds:["0123456789abcdef"]}}},
  {tag:"handmade", port:9999, protocol:"socks", settings:{auth:"noauth"}}
], outbounds:[{protocol:"freedom", tag:"direct"}, {protocol:"blackhole", tag:"block"}]}' > "$tmp/xray-etc/config.json"
bash -c '
  source "$1" "$2"
  assert_eq() { [ "$1" = "$2" ] || { printf "ASSERT FAIL: got [%s] want [%s]\n" "$1" "$2"; exit 1; }; }
  priv="$(printf "A%.0s" $(seq 1 43))"
  dec="mlkem768x25519plus.native.600s.$priv"
  upsert_inbound 2 "$(inbound_json 2 "22222222-2222-3333-4444-555555555555" 24432 "" "" "" "$dec")"
  assert_eq "$(jq -r ".inbounds | length" "$CONFIG_FILE")" "3"
  assert_eq "$(jq -r ".inbounds[] | select(.tag==\"handmade\") | .port" "$CONFIG_FILE")" "9999"
  assert_eq "$(jq -r ".inbounds[] | select(.tag==\"vless-enc\") | .port" "$CONFIG_FILE")" "24432"
  set_inbound_port 1 24499
  assert_eq "$(jq -r ".inbounds[] | select(.tag==\"vless-reality\") | .port" "$CONFIG_FILE")" "24499"
  assert_eq "$(jq -r ".inbounds[] | select(.tag==\"vless-enc\") | .port" "$CONFIG_FILE")" "24432"
  remove_inbound 2
  assert_eq "$(jq -r ".inbounds | length" "$CONFIG_FILE")" "2"
  assert_eq "$(jq -r ".inbounds[] | select(.tag==\"handmade\") | .port" "$CONFIG_FILE")" "9999"
  upsert_inbound 1 "$(inbound_json 1 "11111111-2222-3333-4444-555555555555" 24431 "example.com" "$priv" "0123456789abcdef" "none")"
  assert_eq "$(jq -r ".inbounds | length" "$CONFIG_FILE")" "2"
  assert_eq "$(jq -r ".inbounds[] | select(.tag==\"vless-reality\") | .port" "$CONFIG_FILE")" "24431"
  printf "SECTION5-OK\n"
' _ "$tmp/harness.sh" "$tmp"

# ---------- §6 旧版无 tag 单入站当模式 1 读, upsert 后补 tag 不重复 ----------
jq -n --arg priv "$PRIV43" '{log:{loglevel:"warning"}, inbounds:[
  {port:24443, protocol:"vless", settings:{clients:[{id:"11111111-2222-3333-4444-555555555555", flow:"xtls-rprx-vision"}], decryption:"none"}, streamSettings:{network:"tcp", security:"reality", realitySettings:{show:false, target:"example.com:443", xver:0, serverNames:["example.com"], privateKey:$priv, shortIds:["0123456789abcdef"]}}}
], outbounds:[{protocol:"freedom", tag:"direct"}, {protocol:"blackhole", tag:"block"}]}' > "$tmp/xray-etc/config.json"
bash -c '
  source "$1" "$2"
  assert_eq() { [ "$1" = "$2" ] || { printf "ASSERT FAIL: got [%s] want [%s]\n" "$1" "$2"; exit 1; }; }
  assert_eq "$(installed_modes)" "1"
  assert_eq "$(inbound_value 1 uuid)" "11111111-2222-3333-4444-555555555555"
  assert_eq "$(inbound_value 1 port)" "24443"
  assert_eq "$(inbound_value 1 sni)" "example.com"
  [ -n "$(mode_inbound 1)" ] || { printf "mode_inbound 1 empty\n"; exit 1; }
  priv="$(printf "A%.0s" $(seq 1 43))"
  upsert_inbound 1 "$(inbound_json 1 "11111111-2222-3333-4444-555555555555" 24444 "example.com" "$priv" "0123456789abcdef" "none")"
  assert_eq "$(jq -r ".inbounds | length" "$CONFIG_FILE")" "1"
  assert_eq "$(jq -r ".inbounds[0].tag" "$CONFIG_FILE")" "vless-reality"
  assert_eq "$(jq -r ".inbounds[0].port" "$CONFIG_FILE")" "24444"
  assert_eq "$(installed_modes)" "1"
  printf "SECTION6-OK\n"
' _ "$tmp/harness.sh" "$tmp"

# ---------- §7 assign_port 矩阵 ----------
cat > "$tmp/assign-stub.sh" <<'STUB'
#!/usr/bin/env bash
tmp="$1"
source "$tmp/harness.sh" "$tmp"
port_in_use() { case " $BUSY_PORTS " in *" $1 "*) return 0;; *) return 1;; esac; }
port_owner_is_xray() { return 1; }
pick_free_port() { printf '%s' "${PICK_PORT:-24444}"; }
STUB
rm -f "$tmp/xray-etc/config.json"
out="$(BUSY_PORTS="" PICK_PORT=24444 bash -c 'source "$1" "$2"; assign_port 3 "" 1' _ "$tmp/assign-stub.sh" "$tmp" 2>/dev/null)"
[ "$out" = "443" ] || { echo "§7a: got [$out] want 443"; exit 1; }
out="$(BUSY_PORTS="443" PICK_PORT=24444 bash -c 'source "$1" "$2"; assign_port 3 "" 1' _ "$tmp/assign-stub.sh" "$tmp" 2>/dev/null)"
[ "$out" = "24444" ] || { echo "§7b: got [$out] want 24444"; exit 1; }
out="$(BUSY_PORTS="" PICK_PORT=24444 bash -c 'source "$1" "$2"; assign_port 1 "" 1' _ "$tmp/assign-stub.sh" "$tmp" 2>/dev/null)"
[ "$out" = "24444" ] || { echo "§7c: got [$out] want 24444"; exit 1; }
out="$(BUSY_PORTS="" bash -c 'source "$1" "$2"; assign_port 1 "24443" 0' _ "$tmp/assign-stub.sh" "$tmp" 2>/dev/null)"
[ "$out" = "24443" ] || { echo "§7d: got [$out] want 24443"; exit 1; }
out="$(BUSY_PORTS="" REALITY_PORT=24443 bash -c 'source "$1" "$2"; assign_port 1 "" 1' _ "$tmp/assign-stub.sh" "$tmp" 2>/dev/null)"
[ "$out" = "24443" ] || { echo "§7e: got [$out] want 24443"; exit 1; }
if BUSY_PORTS="24443" REALITY_PORT=24443 bash -c 'source "$1" "$2"; assign_port 1 "" 1' _ "$tmp/assign-stub.sh" "$tmp" 2>/dev/null; then
  echo "§7f: 指定端口被占应报错却通过了"; exit 1
fi
if REALITY_PORT=24443 bash -c 'source "$1" "$2"; ASSIGNED_PORTS="24443"; assign_port 1 "" 1' _ "$tmp/assign-stub.sh" "$tmp" 2>/dev/null; then
  echo "§7g: 与本次已分配端口冲突应报错却通过了"; exit 1
fi
jq -n --arg priv "$PRIV43" '{log:{loglevel:"warning"}, inbounds:[
  {tag:"vless-reality", port:24443, protocol:"vless", settings:{clients:[{id:"11111111-2222-3333-4444-555555555555", flow:"xtls-rprx-vision"}], decryption:"none"}, streamSettings:{network:"tcp", security:"reality", realitySettings:{show:false, target:"example.com:443", xver:0, serverNames:["example.com"], privateKey:$priv, shortIds:["0123456789abcdef"]}}}
], outbounds:[{protocol:"freedom", tag:"direct"}, {protocol:"blackhole", tag:"block"}]}' > "$tmp/xray-etc/config.json"
if BUSY_PORTS="" REALITY_PORT=24443 bash -c 'source "$1" "$2"; assign_port 3 "" 1' _ "$tmp/assign-stub.sh" "$tmp" 2>/dev/null; then
  echo "§7h: 与已装模式端口冲突应报错却通过了"; exit 1
fi
printf 'SECTION7-OK\n'

# ---------- §8 IPv6 地址: QuanX 行与链接加方括号, Surge 行不加 ----------
jq -n --arg priv "$PRIV43" '{log:{loglevel:"warning"}, inbounds:[
  {tag:"vless-reality", port:24443, protocol:"vless", settings:{clients:[{id:"11111111-2222-3333-4444-555555555555", flow:"xtls-rprx-vision"}], decryption:"none"}, streamSettings:{network:"tcp", security:"reality", realitySettings:{show:false, target:"example.com:443", xver:0, serverNames:["example.com"], privateKey:$priv, shortIds:["0123456789abcdef"]}}}
], outbounds:[{protocol:"freedom", tag:"direct"}, {protocol:"blackhole", tag:"block"}]}' > "$tmp/xray-etc/config.json"
for host in "2408:8656:f1f5:e222::c103" "[2408:8656:f1f5:e222::c103]"; do
  rm -f "$tmp/client.txt"
  REALITY_HOST="$host" bash -c 'source "$1" "$2"; do_show >/dev/null' _ "$tmp/harness.sh" "$tmp"
  grep -q 'vless=\[2408:8656:f1f5:e222::c103\]:24443,' "$tmp/client.txt" || { echo "§8: QuanX 行缺方括号 (host=$host)"; exit 1; }
  grep -q '@\[2408:8656:f1f5:e222::c103\]:24443?' "$tmp/client.txt" || { echo "§8: 链接缺方括号 (host=$host)"; exit 1; }
  grep -q '= vless, 2408:8656:f1f5:e222::c103, 24443,' "$tmp/client.txt" || { echo "§8: Surge 行应写裸 IPv6 (host=$host)"; exit 1; }
  grep -q '\[\[2408' "$tmp/client.txt" && { echo "§8: 出现双层方括号 (host=$host)"; exit 1; }
done
printf 'SECTION8-OK\n'

# ---------- §9 remove-mode: 卸一个留一个; 只剩一个时拒绝 ----------
mkfixture_13() {
  jq -n --arg priv "$PRIV43" --arg dec "mlkem768x25519plus.native.600s.$PRIV43" '{log:{loglevel:"warning"}, inbounds:[
    {tag:"vless-reality", port:24431, protocol:"vless", settings:{clients:[{id:"11111111-2222-3333-4444-555555555555", flow:"xtls-rprx-vision"}], decryption:"none"}, streamSettings:{network:"tcp", security:"reality", realitySettings:{show:false, target:"example.com:443", xver:0, serverNames:["example.com"], privateKey:$priv, shortIds:["0123456789abcdef"]}}},
    {tag:"vless-reality-enc", port:443, protocol:"vless", settings:{clients:[{id:"33333333-2222-3333-4444-555555555555", flow:"xtls-rprx-vision"}], decryption:$dec}, streamSettings:{network:"tcp", security:"reality", realitySettings:{show:false, target:"example.com:443", xver:0, serverNames:["example.com"], privateKey:$priv, shortIds:["0123456789abcdef"]}}}
  ], outbounds:[{protocol:"freedom", tag:"direct"}, {protocol:"blackhole", tag:"block"}]}' > "$tmp/xray-etc/config.json"
}
mkfixture_13
bash -c 'source "$1" "$2"; do_remove_mode remove-mode 1 >/dev/null' _ "$tmp/harness.sh" "$tmp"
[ "$(jq -r '.inbounds | length' "$tmp/xray-etc/config.json")" = "1" ] || { echo "§9: 卸模式 1 后入站数不对"; exit 1; }
[ "$(jq -r '.inbounds[0].tag' "$tmp/xray-etc/config.json")" = "vless-reality-enc" ] || { echo "§9: 剩下的应是模式 3"; exit 1; }
grep -q '模式 3' "$tmp/client.txt" || { echo "§9: 客户端文件未重生成模式 3"; exit 1; }
if bash -c 'source "$1" "$2"; do_remove_mode remove-mode 3 >/dev/null' _ "$tmp/harness.sh" "$tmp" 2>/dev/null; then
  echo "§9: 只剩一个模式时应拒绝却卸了"; exit 1
fi
mkfixture_13
REALITY_MODE=3 bash -c 'source "$1" "$2"; do_remove_mode >/dev/null' _ "$tmp/harness.sh" "$tmp"
[ "$(jq -r '.inbounds[0].tag' "$tmp/xray-etc/config.json")" = "vless-reality" ] || { echo "§9: REALITY_MODE=3 应卸模式 3"; exit 1; }
printf 'SECTION9-OK\n'

# ---------- §10 prompt_modes: 管道输入 ----------
out="$(printf '1,3\n' | bash -c 'source "$1" "$2"; prompt_modes 2>/dev/null' _ "$tmp/harness.sh" "$tmp")"
[ "$out" = "1 3" ] || { echo "§10a: got [$out] want [1 3]"; exit 1; }
out="$(printf '\n' | bash -c 'source "$1" "$2"; prompt_modes 2>/dev/null' _ "$tmp/harness.sh" "$tmp")"
[ "$out" = "1 2 3" ] || { echo "§10b: got [$out] want [1 2 3]"; exit 1; }
out="$(printf '2\n' | bash -c 'source "$1" "$2"; prompt_modes 2>/dev/null' _ "$tmp/harness.sh" "$tmp")"
[ "$out" = "2" ] || { echo "§10c: got [$out] want [2]"; exit 1; }
if printf 'x\n9\n0\n' | bash -c 'source "$1" "$2"; prompt_modes 2>/dev/null' _ "$tmp/harness.sh" "$tmp"; then
  echo "§10d: 3 次无效输入应失败却通过了"; exit 1
fi
printf 'SECTION10-OK\n'

# ---------- §11 do_install 三模式干跑 (假 xray, 443 空闲) ----------
cat > "$tmp/install-stub.sh" <<'STUB'
#!/usr/bin/env bash
tmp="$1"
source "$tmp/harness.sh" "$tmp"
port_in_use() { return 1; }
STUB
rm -f "$tmp/xray-etc/config.json" "$tmp/client.txt"
REALITY_MODES=1,2,3 REALITY_SNI=www.amazon.com REALITY_HOST=203.0.113.1 \
  bash -c 'source "$1" "$2"; do_install >/dev/null' _ "$tmp/install-stub.sh" "$tmp"
[ "$(jq -r '.inbounds | length' "$tmp/xray-etc/config.json")" = "3" ] || { echo "§11: 入站数不是 3"; exit 1; }
[ "$(jq -r '.inbounds[] | select(.tag=="vless-reality-enc") | .port' "$tmp/xray-etc/config.json")" = "443" ] || { echo "§11: 模式 3 应在 443"; exit 1; }
p1="$(jq -r '.inbounds[] | select(.tag=="vless-reality") | .port' "$tmp/xray-etc/config.json")"
p2="$(jq -r '.inbounds[] | select(.tag=="vless-enc") | .port' "$tmp/xray-etc/config.json")"
[ "$p1" -ge 10000 ] && [ "$p1" -le 30000 ] || { echo "§11: 模式 1 端口 $p1 不在 10000-30000"; exit 1; }
[ "$p2" -ge 10000 ] && [ "$p2" -le 30000 ] || { echo "§11: 模式 2 端口 $p2 不在 10000-30000"; exit 1; }
[ "$p1" != "$p2" ] || { echo "§11: 模式 1/2 端口撞了"; exit 1; }
[ "$(jq -r '.inbounds[] | select(.tag=="vless-reality") | .settings.decryption' "$tmp/xray-etc/config.json")" = "none" ] || { echo "§11: 模式 1 decryption 应为 none"; exit 1; }
jq -e '.inbounds[] | select(.tag=="vless-enc" or .tag=="vless-reality-enc") | .settings.decryption | startswith("mlkem768x25519plus.native.600s.")' "$tmp/xray-etc/config.json" >/dev/null || { echo "§11: 模式 2/3 缺 decryption"; exit 1; }
[ "$(grep -c '^--- 模式 ' "$tmp/client.txt")" = "3" ] || { echo "§11: 客户端文件应有 3 个模式块"; exit 1; }
[ "$(grep -c '^vless=203.0.113.1' "$tmp/client.txt")" = "1" ] || { echo "§11: 应只有 1 条 QuanX 行 (模式 1)"; exit 1; }
[ "$(grep -c ' = vless, 203.0.113.1,' "$tmp/client.txt")" = "3" ] || { echo "§11: 应有 3 条 Surge 行 (每模式 1 条)"; exit 1; }
[ "$(grep -c '^vless://' "$tmp/client.txt")" = "3" ] || { echo "§11: 应有 3 条 vless 链接"; exit 1; }
[ "$(grep -c 'encryption=mlkem768x25519plus' "$tmp/client.txt")" = "4" ] || { echo "§11: 应有 4 处 encryption=mlkem 串 (模式 2/3 各 1 行 Surge + 1 条链接)"; exit 1; }
[ "$(grep -c '不支持 VLESS Encryption' "$tmp/client.txt")" = "2" ] || { echo "§11: 应有 2 处 QuanX 不支持提示 (模式 2/3)"; exit 1; }
# Surge 行精确格式: 假 xray 的密钥固定 (公钥 43 个 B), UUID/shortId 从配置里读
# (gen_uuid 优先读 /proc/sys/kernel/random/uuid, 不是假 xray 的固定值)
b43="$(printf 'B%.0s' $(seq 1 43))"
uuid2="$(jq -r '.inbounds[] | select(.tag=="vless-enc") | .settings.clients[0].id' "$tmp/xray-etc/config.json")"
uuid3="$(jq -r '.inbounds[] | select(.tag=="vless-reality-enc") | .settings.clients[0].id' "$tmp/xray-etc/config.json")"
enc_str="mlkem768x25519plus.native.0rtt.$b43"
sid3="$(jq -r '.inbounds[] | select(.tag=="vless-reality-enc") | .streamSettings.realitySettings.shortIds[0]' "$tmp/xray-etc/config.json")"
grep -qF "Surge-Enc = vless, 203.0.113.1, $p2, username=$uuid2, encryption=$enc_str" "$tmp/client.txt" || { echo "§11: 模式 2 Surge 行格式不对"; exit 1; }
m2line="$(grep 'Surge-Enc = vless' "$tmp/client.txt")"
case "$m2line" in *flow=*|*sni=*|*reality-*) echo "§11: 模式 2 Surge 行不应带 flow/sni/Reality 参数"; exit 1;; esac
grep -qF "Surge-RealityEnc = vless, 203.0.113.1, 443, username=$uuid3, flow=xtls-rprx-vision, sni=www.amazon.com, reality-public-key=$b43, reality-short-id=$sid3, encryption=$enc_str" "$tmp/client.txt" || { echo "§11: 模式 3 Surge 行格式不对"; exit 1; }
printf 'SECTION11-OK\n'

printf 'ALL-MODES-TESTS-OK\n'
