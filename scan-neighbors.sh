#!/usr/bin/env bash
# 一键扫邻居域名: 扫 VPS 所在 /24 的 443, 从证书里挖域名, 再用 RealityChecker 过滤
#
# 用法 (在 Linux VPS 上):
#   bash scan-neighbors.sh                  # 自动探测本机公网 IP, 扫它所在的 /24
#   bash scan-neighbors.sh 154.9.236.158    # 指定 IP, 扫它所在的 /24
#   bash scan-neighbors.sh 154.9.236.0/24   # 直接指定网段
#   bash scan-neighbors.sh 154.9.236.158 file2.csv   # 指定输出文件名
#   bash scan-neighbors.sh --dry-run [IP或网段]      # 只打印要执行的命令, 不真扫
#
# 输出: 扫描结果写进 file.csv (或你指定的文件), RealityChecker 的过滤结果打印到终端
# 注意: 官方建议 RealiTLScanner 尽量在本地跑, VPS 上扫有被标记的风险; 只扫一个 /24 一般问题不大
set -u
export LC_ALL=C

SCANNER_VER="v0.2.3"
CHECKER_VER="v2.2.3"
THREADS=100
TIMEOUT=5

info() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
die()  { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

usage() {
  printf '%s\n' "用法: bash scan-neighbors.sh [IP或网段] [输出csv] [--dry-run]"
  printf '%s\n' "  不给 IP: 自动探测本机公网 IP, 扫它所在的 /24"
  printf '%s\n' "  只给 IP: 如 154.9.236.158, 自动换成 154.9.236.0/24 再扫"
  printf '%s\n' "  给网段: 如 154.9.236.0/24, 直接扫这个网段"
  printf '%s\n' "  --dry-run: 只打印要执行的命令, 不下载不扫描"
}

TOOLS_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
# 一键安装 (bash <(curl ...)) 时 $0 是 /dev/fd/xx, 工具没处放, 改放当前目录
case "$TOOLS_DIR" in
  /dev/fd*|/proc/self/fd*) TOOLS_DIR="$PWD" ;;
esac
if [ ! -w "$TOOLS_DIR" ] 2>/dev/null; then TOOLS_DIR="$PWD"; fi
SCANNER="$TOOLS_DIR/RealiTLScanner"
CHECKER="$TOOLS_DIR/reality-checker"

DRY_RUN=0
TARGET=""
OUT="file.csv"
for arg in "$@"; do
  case "$arg" in
    -h|--help) usage; exit 0 ;;
    --dry-run) DRY_RUN=1 ;;
    *) if [ -z "$TARGET" ]; then TARGET="$arg"; else OUT="$arg"; fi ;;
  esac
done

[ "$(uname -s)" = "Linux" ] || die "这个脚本只支持 Linux VPS; Mac 请装 Go 后自行编译 RealiTLScanner / RealityChecker"
ARCH_RAW="$(uname -m)"
case "$ARCH_RAW" in
  x86_64|amd64) ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *) die "不支持的架构: $ARCH_RAW (只支持 amd64/arm64)" ;;
esac
command -v curl >/dev/null 2>&1 || die "需要 curl, 先装: apt install -y curl"

public_ip() {
  local ip=""
  ip="$(curl -4fsSL --max-time 8 https://ifconfig.me 2>/dev/null | tr -d ' \r\n')" || true
  [ -n "$ip" ] || ip="$(curl -4fsSL --max-time 8 https://api.ipify.org 2>/dev/null | tr -d ' \r\n')" || true
  printf '%s' "$ip"
}

# ---- 目标网段: 裸 IP 一律换成它所在的 /24 (单个 IP 会触发扫描器的 infinity 模式, 一直扫不停) ----
if [ -z "$TARGET" ]; then
  TARGET="$(public_ip)"
  [ -n "$TARGET" ] || die "探测不到本机公网 IP, 请手动指定: bash $0 <VPS IP 或网段>"
fi
case "$TARGET" in
  */*) CIDR="$TARGET" ;;
  *.*.*.*) CIDR="${TARGET%.*}.0/24" ;;
  *) die "IP/网段无效: $TARGET" ;;
esac

SCANNER_URL="https://github.com/XTLS/RealiTLScanner/releases/download/${SCANNER_VER}/RealiTLScanner-linux-${ARCH}"
CHECKER_URL="https://github.com/V2RaySSR/RealityChecker/releases/download/${CHECKER_VER}/reality-checker-linux-${ARCH}.zip"

if [ "$DRY_RUN" = "1" ]; then
  info "[dry-run] 目标网段: $CIDR"
  info "[dry-run] 扫描器: $SCANNER_URL (已有则跳过下载)"
  info "[dry-run] 检测器: $CHECKER_URL (已有则跳过下载)"
  info "[dry-run] 执行: $SCANNER -addr $CIDR -port 443 -thread $THREADS -timeout $TIMEOUT -out $OUT"
  info "[dry-run] 执行: $CHECKER csv $OUT"
  exit 0
fi

# ---- 工具: 没有就下载 (官方 release, 不是来路不明的脚本) ----
if [ ! -x "$SCANNER" ]; then
  info "下载 RealiTLScanner $SCANNER_VER ..."
  curl -fsSL --max-time 120 -o "$SCANNER.tmp" "$SCANNER_URL" || die "RealiTLScanner 下载失败: $SCANNER_URL"
  mv "$SCANNER.tmp" "$SCANNER" && chmod +x "$SCANNER"
else
  info "扫描器已有: $SCANNER"
fi
if [ ! -x "$CHECKER" ]; then
  info "下载 RealityChecker $CHECKER_VER ..."
  curl -fsSL --max-time 120 -o "$TOOLS_DIR/reality-checker.zip" "$CHECKER_URL" || die "RealityChecker 下载失败: $CHECKER_URL"
  if command -v unzip >/dev/null 2>&1; then
    unzip -o -q "$TOOLS_DIR/reality-checker.zip" -d "$TOOLS_DIR" || die "解压 RealityChecker 失败"
  else
    python3 -c "import zipfile; zipfile.ZipFile('$TOOLS_DIR/reality-checker.zip').extractall('$TOOLS_DIR')" || die "解压 RealityChecker 失败 (需要 unzip 或 python3)"
  fi
  chmod +x "$CHECKER"
else
  info "检测器已有: $CHECKER"
fi

# ---- 第一步: 扫邻居 ----
info "开始扫描 $CIDR (线程 $THREADS, 超时 ${TIMEOUT}s, 输出 $OUT)..."
"$SCANNER" -addr "$CIDR" -port 443 -thread "$THREADS" -timeout "$TIMEOUT" -out "$OUT" || warn "扫描器退出码非 0, 先看 $OUT 是否有内容"
[ -f "$OUT" ] || die "扫描没生成 $OUT, 换个网段或检查网络再试"
ROWS=$(( $(wc -l < "$OUT") - 1 ))
[ "$ROWS" -gt 0 ] || die "扫描结果 0 行 ($OUT 只有表头), 这个网段上没扫到东西, 换个网段再试"
info "扫描完成: $OUT 共 $ROWS 行"

# ---- 第二步: 过滤 ----
info "开始用 RealityChecker 过滤 (只留 TLS 1.3 + X25519 + h2 + SNI 匹配、无 CDN、非热门的)..."
"$CHECKER" csv "$OUT"
info "上面通过的就是候选; 挑个冷门的用: REALITY_SNI=域名 bash reality install (或装完 bash reality reconfig 改过去)"
