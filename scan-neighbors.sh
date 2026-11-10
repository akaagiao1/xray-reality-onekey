#!/usr/bin/env bash
# 一键扫邻居域名: 扫 VPS 所在 /23 的 443, 从证书里挖域名, 再用 RealityChecker 过滤
#
# 用法 (在 Linux VPS 上):
#   bash scan-neighbors.sh                  # 自动探测本机公网 IP, 扫它所在的 /23
#   bash scan-neighbors.sh 154.9.236.158    # 指定 IP, 扫它所在的 /23
#   bash scan-neighbors.sh 154.9.236.0/24   # 直接指定网段
#   bash scan-neighbors.sh 154.9.236.158 file2.csv   # 指定输出文件名
#   bash scan-neighbors.sh --dry-run [IP或网段]      # 只打印要执行的命令, 不真扫
#
# 输出: 扫描结果写进 file.csv (或你指定的文件), RealityChecker 的过滤结果打印到终端
# 注意: 官方建议 RealiTLScanner 尽量在本地跑, VPS 上扫有被标记的风险; 在 VPS 上扫描仍有风险
set -u
export LC_ALL=C

SCANNER_VER="v0.2.3"
CHECKER_VER="v2.2.3"
THREADS=100
TIMEOUT=5

info() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
die()  { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

# ---- 系统识别: 只有包管理器名不一样, 其余逻辑与发行版无关 ----
OS_ID=""
if [ -f /etc/os-release ]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  OS_ID="${ID:-}"
fi

# 装一个包 (Alpine 走 apk, Debian/Ubuntu 走 apt); 装不上就停, 并给对的提示
pkg_install() { # $1=包名 $2=用途(写给用户看)
  case "$OS_ID" in
    alpine)
      apk update >/dev/null 2>&1
      apk add --no-cache "$1" 2>/dev/null || die "安装 $1 失败 (apk); 手动装: apk update && apk add $1"
      ;;
    debian|ubuntu)
      (command -v apt-get >/dev/null 2>&1 && apt-get update >/dev/null 2>&1 && apt-get install -y "$1") || die "安装 $1 失败 (apt); 手动装: apt update && apt install -y $1"
      ;;
    *)
      die "需要 $1 ($2), 请手动安装后重跑 (当前系统: ${OS_ID:-未知})"
      ;;
  esac
}

usage() {
  printf '%s\n' "用法: bash scan-neighbors.sh [IP或网段] [输出csv] [--dry-run]"
  printf '%s\n' "  不给 IP: 自动探测本机公网 IP, 扫它所在的 /23"
  printf '%s\n' "  只给 IP: 如 154.9.236.158, 自动换成 154.9.236.0/23 再扫"
  printf '%s\n' "  给网段: 如 154.9.236.0/24, 直接扫这个网段"
  printf '%s\n' "  --csv 文件: 使用已有扫描结果，跳过扫描"
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
EXISTING_CSV=""
RECOMMEND_FILE=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --dry-run) DRY_RUN=1 ;;
    --csv) shift; [ "$#" -gt 0 ] || die "--csv 需要文件路径"; EXISTING_CSV="$1" ;;
    --recommend-file) shift; [ "$#" -gt 0 ] || die "--recommend-file 需要文件路径"; RECOMMEND_FILE="$1" ;;
    --*) die "未知选项: $1" ;;
    *) if [ -z "$TARGET" ]; then TARGET="$1"; else OUT="$1"; fi ;;
  esac
  shift
done
if [ -n "$EXISTING_CSV" ]; then
  [ -z "$TARGET" ] || die "--csv 不能与扫描目标同时使用"
  [ -f "$EXISTING_CSV" ] && [ -r "$EXISTING_CSV" ] || die "CSV 不存在或不可读取: $EXISTING_CSV"
  OUT="$EXISTING_CSV"
fi

[ "$(uname -s)" = "Linux" ] || die "这个脚本只支持 Linux VPS; Mac 请装 Go 后自行编译 RealiTLScanner / RealityChecker"
ARCH_RAW="$(uname -m)"
case "$ARCH_RAW" in
  x86_64|amd64) ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *) die "不支持的架构: $ARCH_RAW (只支持 amd64/arm64)" ;;
esac
if ! command -v curl >/dev/null 2>&1; then
  case "$OS_ID" in
    alpine) die "需要 curl, 先装: apk update && apk add curl" ;;
    debian|ubuntu) die "需要 curl, 先装: apt update && apt install -y curl" ;;
    *) die "需要 curl, 请手动安装后重跑" ;;
  esac
fi

public_ip() {
  local ip=""
  ip="$(curl -4fsSL --max-time 8 https://ifconfig.me 2>/dev/null | tr -d ' \r\n')" || true
  [ -n "$ip" ] || ip="$(curl -4fsSL --max-time 8 https://api.ipify.org 2>/dev/null | tr -d ' \r\n')" || true
  printf '%s' "$ip"
}

# ---- 目标网段: 裸 IP 一律换成它所在的 /23 (单个 IP 会触发扫描器的 infinity 模式, 一直扫不停) ----
if [ -z "$TARGET" ] && [ -z "$EXISTING_CSV" ]; then
  TARGET="$(public_ip)"
  [ -n "$TARGET" ] || die "探测不到本机公网 IP, 请手动指定: bash $0 <VPS IP 或网段>"
fi
CIDR=""
if [ -z "$EXISTING_CSV" ]; then
  case "$TARGET" in
    */*) CIDR="$TARGET" ;;
    *.*.*.*)
      if [[ ! "$TARGET" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]]; then die "IPv4 地址无效: $TARGET"; fi
      a=${BASH_REMATCH[1]}; b=${BASH_REMATCH[2]}; c=${BASH_REMATCH[3]}; d=${BASH_REMATCH[4]}
      for n in "$a" "$b" "$c" "$d"; do (( 10#$n <= 255 )) || die "IPv4 地址无效: $TARGET"; done
      CIDR="$((10#$a)).$((10#$b)).$((10#$c / 2 * 2)).0/23" ;;
    *) die "IP/网段无效: $TARGET" ;;
  esac
fi

VENDOR_URL="https://raw.githubusercontent.com/akaagiao1/xray-reality-onekey/8d53364/vendor"
VENDOR_BACKUP="https://github.com/akaagiao1/xray-reality-onekey/raw/8d53364/vendor"
SCANNER_URL="$VENDOR_URL/RealiTLScanner-linux-${ARCH}"
CHECKER_URL="$VENDOR_URL/reality-checker-linux-${ARCH}.zip"
case "$ARCH" in
  amd64) SCANNER_HASH=a55595446de9f1c2e6c5c3cd766a7320a11115947df48f101749bb62c8055592; CHECKER_HASH=e021022b3486153abe738d318cb1cf8b2e3909ae9b2e2e19cbc2e6215db881c9 ;;
  arm64) SCANNER_HASH=27bdd3e53d4391c66c8df3391d3c3fb5eb2dc356125f2fb33ac58fcaaf8f88b3; CHECKER_HASH=f609bc17be50bc1b2e010eff233d9d9906cfd29081b0e0afb912f75117783cbb ;;
esac

if [ "$DRY_RUN" = "1" ]; then
  [ -z "$EXISTING_CSV" ] || { info "[dry-run] 使用已有 CSV: $OUT"; exit 0; }
  info "[dry-run] 目标网段: $CIDR"
  info "[dry-run] 扫描器: $SCANNER_URL (已有则跳过下载)"
  info "[dry-run] 检测器: $CHECKER_URL (已有则跳过下载)"
  info "[dry-run] 执行: $SCANNER -addr $CIDR -port 443 -thread $THREADS -timeout $TIMEOUT -out $OUT"
  info "[dry-run] 执行: $CHECKER csv $OUT"
  exit 0
fi

# python3 是必需的: SHA-256 校验、CSV 转换、推荐筛选全是 python 写的
if ! command -v python3 >/dev/null 2>&1; then
  info "没找到 python3, 正在安装..."
  pkg_install python3 "python3 (SHA-256 校验 / CSV 转换 / 推荐筛选要用)"
fi

# 扫描器/检测器是 glibc 动态链接的二进制, Alpine (musl) 上没有
# /lib64/ld-linux-x86-64.so.2, 直接跑会报 "cannot execute: required file not found";
# 装 gcompat 提供 glibc 兼容层就能跑 (Xray 本身是静态编译, 不用这个)
if [ "$OS_ID" = "alpine" ]; then
  if ! apk info -e gcompat >/dev/null 2>&1; then
    info "Alpine 上跑扫描器需要 gcompat (glibc 兼容层), 正在安装..."
    pkg_install gcompat "gcompat (跑 glibc 链接的扫描器/检测器要用)"
  fi
fi

# ---- 工具: 从仓库下载固定版本，并校验 SHA-256 ----
verify_sha256() {
  python3 - "$1" "$2" <<'PYHASH'
import hashlib
import sys
h = hashlib.sha256()
with open(sys.argv[1], "rb") as f:
    for chunk in iter(lambda: f.read(1024 * 1024), b""):
        h.update(chunk)
actual = h.hexdigest()
if actual != sys.argv[2]:
    print(f"实际 SHA-256: {actual}，预期: {sys.argv[2]}", file=sys.stderr)
    sys.exit(1)
PYHASH
}
download_verified() {
  local name="$1" target="$2" expected="$3" base attempt
  for base in "$VENDOR_URL" "$VENDOR_BACKUP"; do
    for attempt in 1 2; do
      rm -f -- "$target.tmp"
      if curl -fsSL --retry 2 --connect-timeout 15 --max-time 120 -o "$target.tmp" "$base/$name"; then
        if verify_sha256 "$target.tmp" "$expected"; then
          mv -f -- "$target.tmp" "$target" || die "无法保存文件: $target"
          return 0
        fi
        warn "下载内容校验失败（${base}/${name}，第 ${attempt} 次），将重试。"
      else
        warn "下载失败（${base}/${name}，第 ${attempt} 次），将重试。"
      fi
    done
  done
  rm -f -- "$target.tmp"
  die "下载失败或 SHA-256 不匹配: $name，请检查 VPS 到 GitHub 的网络。"
}
if [ -z "$EXISTING_CSV" ] && [ ! -x "$SCANNER" ]; then
  info "下载 RealiTLScanner $SCANNER_VER ..."
  download_verified "RealiTLScanner-linux-${ARCH}" "$SCANNER" "$SCANNER_HASH"
  chmod +x "$SCANNER"
elif [ -z "$EXISTING_CSV" ]; then
  info "扫描器已有: $SCANNER"
fi
if [ ! -x "$CHECKER" ]; then
  info "下载 RealityChecker $CHECKER_VER ..."
  download_verified "reality-checker-linux-${ARCH}.zip" "$TOOLS_DIR/reality-checker.zip" "$CHECKER_HASH"
  if command -v unzip >/dev/null 2>&1; then
    unzip -o -q "$TOOLS_DIR/reality-checker.zip" -d "$TOOLS_DIR" || die "解压 RealityChecker 失败"
  else
    python3 -c "import zipfile; zipfile.ZipFile('$TOOLS_DIR/reality-checker.zip').extractall('$TOOLS_DIR')" || die "解压 RealityChecker 失败 (需要 unzip 或 python3)"
  fi
  chmod +x "$CHECKER"
else
  info "检测器已有: $CHECKER"
fi

# ---- 第一步: 扫邻居或使用已有结果 ----
if [ -z "$EXISTING_CSV" ]; then
  info "开始扫描 $CIDR (线程 $THREADS, 超时 ${TIMEOUT}s, 输出 $OUT)..."
  "$SCANNER" -addr "$CIDR" -port 443 -thread "$THREADS" -timeout "$TIMEOUT" -out "$OUT" || die "扫描器执行失败 (Alpine 上若报 required file not found, 是缺 glibc 兼容层, 装 gcompat: apk update && apk add gcompat)"
fi
[ -s "$OUT" ] || die "扫描结果不存在或为空: $OUT"

# RealityChecker v2.2.3 使用第 3 列；v0.2.3 扫描器的域名在第 9 列。
COMPAT="$(mktemp "${TMPDIR:-/tmp}/reality-compatible.XXXXXXXX")" || die "无法创建临时文件"
REPORT="$(mktemp "${TMPDIR:-/tmp}/reality-report.XXXXXXXX")" || { rm -f -- "$COMPAT"; die "无法创建临时文件"; }
CHECKER_WORK="$(mktemp -d "${TMPDIR:-/tmp}/reality-checker-work.XXXXXXXX")" || { rm -f -- "$COMPAT" "$REPORT"; die "无法创建临时目录"; }
trap 'rm -f -- "$COMPAT" "$REPORT"; rm -rf -- "$CHECKER_WORK"' EXIT
info "转换 CSV 并核对域名当前解析（仅供参考）..."
python3 - "$OUT" "$COMPAT" <<'PYCODE' || die "CSV 转换失败，请检查文件格式"
import csv
import socket
import sys

try:
    with open(sys.argv[1], encoding="utf-8-sig", newline="") as src:
        reader = csv.DictReader(src)
        required = {"IP", "ORIGIN", "CERT_DOMAIN"}
        if not reader.fieldnames or not required.issubset(reader.fieldnames):
            raise ValueError("缺少 IP、ORIGIN 或 CERT_DOMAIN 列")
        rows = list(reader)
    if not rows:
        raise ValueError("CSV 没有扫描记录")
    with open(sys.argv[2], "w", encoding="utf-8", newline="") as dst:
        writer = csv.writer(dst)
        writer.writerow(["IP", "ORIGIN", "CERT_DOMAIN"])
        for row in rows:
            writer.writerow([row["IP"], row["ORIGIN"], row["CERT_DOMAIN"]])
    seen = set()
    for row in rows:
        ip = (row["IP"] or "").strip()
        name = (row["CERT_DOMAIN"] or "").strip()
        if (name, ip) in seen:
            continue
        seen.add((name, ip))
        if not name or "*" in name or "." not in name:
            print(f"[跳过解析] {name or '(空域名)'}  扫描IP: {ip}")
            continue
        try:
            resolved = sorted({r[4][0] for r in socket.getaddrinfo(name, None, socket.AF_INET, socket.SOCK_STREAM)})
            status = "匹配" if ip in resolved else "不匹配"
            print(f"[{status}] {name}  扫描IP: {ip}  当前IPv4: {', '.join(resolved) or '无'}")
        except socket.gaierror:
            print(f"[解析失败] {name}  扫描IP: {ip}")
    print("说明：解析仅代表当前时刻；匹配不等于同 ASN，也不保证 REALITY 可用。")
except (OSError, UnicodeError, csv.Error, ValueError) as exc:
    print(f"CSV 错误: {exc}", file=sys.stderr)
    sys.exit(1)
PYCODE

# 将固定快照放在临时工作目录，避免检测器自动依赖上游仓库更新数据。
DATA_CACHE="$TOOLS_DIR/.reality-checker-data"
mkdir -p "$DATA_CACHE" "$CHECKER_WORK/data" || die "无法创建数据目录"
while read -r data_name data_hash; do
  data_path="$DATA_CACHE/$data_name"
  if [ ! -f "$data_path" ] || ! verify_sha256 "$data_path" "$data_hash"; then
    info "下载检测数据: $data_name"
    download_verified "data/$data_name" "$data_path" "$data_hash"
  fi
  cp "$data_path" "$CHECKER_WORK/data/$data_name" || die "无法复制检测数据"
done <<'DATAFILES'
cdn_keywords.txt e6b6b21cf84007ff45badc1bee76bc0acec53434d606509fc0b8ce480cac36d5
hot_websites.txt 774a5de42b004bf502f872941e2273eb4796c9639ac5b764a57a8ed4e06aa5b5
gfwlist.conf 1e05082d0d82eba7bcf7ad1fdc0176b8d397ba3677b662e685683fe560141277
Country.mmdb c0c6ea5661a3167abb24bbbaf629605aa3856c425384cbf2897c5a0f41027663
DATAFILES
info "开始用 RealityChecker 检测证书域名（包括未匹配的域名）..."
set -o pipefail
(cd "$CHECKER_WORK" && "$CHECKER" csv "$COMPAT") | sed '/goii\.cc\/mn/d' | tee "$REPORT" || die "RealityChecker 执行失败"

# 仅推荐最终域名与扫描证书域名相同，且当前仍解析到对应扫描 IP 的结果。
python3 - "$COMPAT" "$REPORT" "$RECOMMEND_FILE" <<'PYCODE' || die "推荐结果生成失败"
import csv
import re
import socket
import sys

scanned = {}
with open(sys.argv[1], encoding="utf-8", newline="") as f:
    for row in csv.DictReader(f):
        domain = (row.get("CERT_DOMAIN") or "").strip().lower().rstrip(".")
        ip = (row.get("IP") or "").strip()
        if domain and "*" not in domain and ip:
            scanned.setdefault(domain, set()).add(ip)

ansi = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
candidates = []
with open(sys.argv[2], encoding="utf-8", errors="replace") as f:
    for line in f:
        parts = [p.strip() for p in ansi.sub("", line).strip().strip("|").split("|")]
        if len(parts) != 8:
            continue
        name, basic, latency, cert, cdn, hot, stars, status = parts
        key = name.lower().rstrip(".")
        ms = re.fullmatch(r"(\d+)ms", latency)
        days = re.fullmatch(r"(\d+)天", cert)
        if not (key in scanned and basic == "✓" and ms and days and int(days.group(1)) >= 14
                and cdn == "无" and hot == "-" and status == "200"):
            continue
        try:
            resolved = {r[4][0] for r in socket.getaddrinfo(key, None, socket.AF_INET, socket.SOCK_STREAM)}
        except socket.gaierror:
            continue
        matched = sorted(scanned[key] & resolved)
        if matched:
            candidates.append((int(ms.group(1)), name, matched[0], int(days.group(1))))

candidates = sorted(set(candidates))
if sys.argv[3]:
    with open(sys.argv[3], "w", encoding="utf-8") as result:
        if candidates:
            result.write(candidates[0][1] + "\n")

print("\n推荐结果（按握手延迟排序，最多 3 个）：")
if not candidates:
    print("本次没有符合条件的推荐域名；请查看上方报告或更换获授权的扫描范围。")
else:
    for i, (ms, name, ip, days) in enumerate(candidates[:3], 1):
        print(f"推荐 {i}: {name}  邻居 IP: {ip}  握手: {ms}ms  证书剩余: {days}天")
print("筛选依据：检测通过、状态 200、无明显 CDN、非热门、证书至少 14 天，且当前解析包含扫描 IP。")
print("DNS 可能变化；检测结果不能证明同 ASN 或保证可用。请在实际节点配置后测试。")
PYCODE
