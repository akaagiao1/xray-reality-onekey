#!/usr/bin/env bash
# Xray 下载校验 + auto-reality pin 一致性测试 (真下载真二进制, 不碰真系统)
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

arch="$(uname -m)"
case "$arch" in
  x86_64|amd64) asset="Xray-linux-64.zip" ;;
  aarch64|arm64) asset="Xray-linux-arm64-v8a.zip" ;;
  *) printf '%s\n' "跳过下载校验测试: 不支持的架构 $arch"; exit 0 ;;
esac

# ---- 测试替身: reality 副本, 路径全部指到 $tmp, 不碰真系统 ----
cp "$repo/reality" "$tmp/reality"
sed -i \
  -e "s|/usr/local/bin/xray|$tmp/xray|g" \
  -e "s|/usr/local/etc/xray|$tmp/xray-etc|g" \
  -e "s|/root/xray-reality-client.txt|$tmp/client.txt|g" \
  -e "s|/usr/local/share/xray|$tmp/xray-share|g" \
  "$tmp/reality"
mkdir -p "$tmp/xray-etc" "$tmp/xray-share"
cat > "$tmp/harness.sh" <<'HARNESS'
#!/usr/bin/env bash
tmp="$1"; shift
source "$tmp/reality" help >/dev/null 2>&1
HARNESS
chmod +x "$tmp/harness.sh"

# ---- 1) 真下载: .dgst 校验必须真的跑起来并通过, 二进制落盘能跑 ----
ASSET="$asset" XRAY_VERSION="v26.10.31" bash -c '
  source "$1" "$2"
  XRAY_ASSET="$ASSET"
  download_xray > "$3/download.out" 2>&1
' _ "$tmp/harness.sh" "$tmp" "$tmp" || { echo "FAIL: 真下载 download_xray 退出了"; cat "$tmp/download.out"; exit 1; }
grep -Fq "sha256 校验通过" "$tmp/download.out" || { echo "FAIL: 没打印 sha256 校验通过, 校验可能又被跳过了"; cat "$tmp/download.out"; exit 1; }
[ -x "$tmp/xray" ] || { echo "FAIL: Xray 二进制没落到替身路径"; exit 1; }
"$tmp/xray" version 2>/dev/null | grep -Fq "26.10.31" || { echo "FAIL: 落盘的 Xray 版本不对"; exit 1; }
printf "%s\n" "真下载 sha256 校验测试通过"

# ---- 2) 篡改 .dgst: 哈希不符必须停下, 不装来路不明的文件 ----
rm -f "$tmp/xray"
ASSET="$asset" XRAY_VERSION="v26.10.31" bash -c '
  source "$1" "$2"
  XRAY_ASSET="$ASSET"
  curl() {
    local out="" url="" prev="" a
    for a in "$@"; do
      case "$prev" in -o) out="$a" ;; esac
      case "$a" in http*) url="$a" ;; esac
      prev="$a"
    done
    case "$url" in *.dgst)
      printf "SHA2-256= 0000000000000000000000000000000000000000000000000000000000000000\n" > "$out"
      return 0 ;;
    esac
    command curl "$@"
  }
  download_xray > "$3/tamper.out" 2>&1
' _ "$tmp/harness.sh" "$tmp" "$tmp" && { echo "FAIL: 篡改 .dgst 后居然没停下"; exit 1; }
grep -Fq "校验失败" "$tmp/tamper.out" || { echo "FAIL: 篡改 .dgst 后没报校验失败"; cat "$tmp/tamper.out"; exit 1; }
[ ! -x "$tmp/xray" ] || { echo "FAIL: 校验失败后二进制还是装上了"; exit 1; }
printf "%s\n" "篡改 .dgst 拦截测试通过"

# ---- 3) 拿不到 .dgst: 警告后继续装 (原有 fail-open 行为不变) ----
rm -f "$tmp/xray"
ASSET="$asset" XRAY_VERSION="v26.10.31" bash -c '
  source "$1" "$2"
  XRAY_ASSET="$ASSET"
  curl() {
    local url="" a
    for a in "$@"; do case "$a" in http*) url="$a" ;; esac; done
    case "$url" in *.dgst) return 22 ;; esac
    command curl "$@"
  }
  download_xray > "$3/nodgst.out" 2>&1
' _ "$tmp/harness.sh" "$tmp" "$tmp" || { echo "FAIL: 拿不到 .dgst 时安装退出了"; cat "$tmp/nodgst.out"; exit 1; }
grep -Fq "未拿到 .dgst" "$tmp/nodgst.out" || { echo "FAIL: 拿不到 .dgst 时没警告"; cat "$tmp/nodgst.out"; exit 1; }
[ -x "$tmp/xray" ] || { echo "FAIL: 拿不到 .dgst 时二进制没装上"; exit 1; }
printf "%s\n" "无 .dgst 继续安装测试通过"

# ---- 4) auto-reality.sh 的 pin: 必须是 40 位提交, 且该提交的 reality 带探活功能与多模式 ----
pin="$(grep -o "xray-reality-onekey/[0-9a-f]*" "$repo/auto-reality.sh" | head -1 | cut -d/ -f2)"
case "$pin" in
  ????????????????????????????????????????) : ;;
  *) echo "FAIL: auto-reality.sh 里没找到 40 位 pin: [$pin]"; exit 1 ;;
esac
curl -fsSL --max-time 30 "https://raw.githubusercontent.com/akaagiao1/xray-reality-onekey/${pin}/reality" -o "$tmp/pinned-reality" || { echo "FAIL: pin 提交的 reality 拉不到"; exit 1; }
grep -Fq "probe_fallback" "$tmp/pinned-reality" || { echo "FAIL: pin 提交的 reality 没有探活 fallback, pin 需要 bump"; exit 1; }
grep -Fq "PROBE_NODES" "$tmp/pinned-reality" || { echo "FAIL: pin 提交的 reality 没有 PROBE_NODES"; exit 1; }
grep -Fq "REALITY_SKIP_PROBE" "$tmp/pinned-reality" || { echo "FAIL: pin 提交的 reality 没有 REALITY_SKIP_PROBE"; exit 1; }
grep -Fq "REALITY_MODES" "$tmp/pinned-reality" || { echo "FAIL: pin 提交的 reality 没有多模式 (REALITY_MODES), pin 需要 bump"; exit 1; }
grep -Fq "gen_vlessenc" "$tmp/pinned-reality" || { echo "FAIL: pin 提交的 reality 没有 VLESS Encryption (gen_vlessenc), pin 需要 bump"; exit 1; }
curl -fsSL --max-time 30 "https://raw.githubusercontent.com/akaagiao1/xray-reality-onekey/${pin}/scan-neighbors.sh" -o "$tmp/pinned-scan" || { echo "FAIL: pin 提交的 scan-neighbors.sh 拉不到"; exit 1; }
[ -s "$tmp/pinned-scan" ] || { echo "FAIL: pin 提交的 scan-neighbors.sh 是空的"; exit 1; }
grep -Fq "recommend-file" "$tmp/pinned-scan" || { echo "FAIL: pin 提交的 scan-neighbors.sh 不像扫描脚本"; exit 1; }
printf "%s\n" "auto-reality pin 一致性测试通过 (pin $pin)"

printf "%s\n" "下载校验与 pin 测试全部通过"
