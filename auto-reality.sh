#!/usr/bin/env bash
# 自动筛选邻居域名，并用推荐域名安装 Xray REALITY。
set -Eeuo pipefail
error() { printf '[错误] %s\n' "$*" >&2; exit 1; }
if [[ ${1:-} == --help || ${1:-} == -h ]]; then
  printf '%s\n' '用法: bash auto-reality.sh [--csv 已有扫描结果.csv]' \
    '默认按本机 /23 → 相邻上段 /23 → 相邻下段 /23 的优先级扫描；--csv 使用已有扫描结果。' \
    '扫不到合格候选时改用 www.apple.com 安装；已有 Xray 配置时停止，不覆盖。'
  exit 0
fi
csv=''
if (( $# )); then
  [[ $# -eq 2 && $1 == --csv ]] || error '参数无效，请使用 --help 查看用法。'
  [[ -f $2 && -r $2 ]] || error "CSV 文件不存在或不可读: $2 (先跑扫描生成, 或确认路径)"
  csv="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
fi
[[ $(uname -s) == Linux ]] || error '需要 Linux (Debian / Ubuntu / Alpine)。'
[[ $(id -u) == 0 ]] || error '请以 root 运行此脚本。'
command -v curl >/dev/null 2>&1 || error '需要 curl；请先安装 curl 和 ca-certificates。'
existing_xray() {
  [[ -e /usr/local/etc/xray/config.json || -e /usr/local/bin/xray || -e /etc/systemd/system/xray.service || -e /usr/lib/systemd/system/xray.service || -e /lib/systemd/system/xray.service || -e /etc/init.d/xray ]] || command -v xray >/dev/null 2>&1
}
existing_xray && error '检测到现有 Xray 程序、配置或服务，已停止以免覆盖现有节点。'
if ! command -v python3 >/dev/null 2>&1; then
  if [ -f /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
  fi
  case "${ID:-}" in
    alpine)
      printf '正在通过 apk 安装 python3...\n'
      apk update >/dev/null 2>&1; apk add --no-cache python3 || error 'python3 安装失败 (apk)。'
      ;;
    debian|ubuntu)
      printf '正在通过 apt 安装 python3...\n'
      command -v apt-get >/dev/null 2>&1 || error '需要 python3，且未找到 apt-get。'
      apt-get update && apt-get install -y python3 || error 'python3 安装失败。'
      ;;
    *)
      error '需要 python3，请先手动安装。'
      ;;
  esac
fi
workdir=$(mktemp -d "${TMPDIR:-/tmp}/auto-reality.XXXXXXXX") || error '无法创建临时目录。'
trap 'rm -rf -- "$workdir"' EXIT
base='https://raw.githubusercontent.com/akaagiao1/xray-reality-onekey/3b47ca734a9626534cfadad181167563f99b6950'
printf '[1/3] 下载扫描脚本...\n'
curl -fsSL --retry 3 --connect-timeout 15 -o "$workdir/scan-neighbors.sh" "$base/scan-neighbors.sh" || error '扫描脚本下载失败。'
public_ip() {
  local ip=""
  ip="$(curl -4fsSL --max-time 8 https://ifconfig.me 2>/dev/null | tr -d ' \r\n')" || true
  [[ -n $ip ]] || ip="$(curl -4fsSL --max-time 8 https://api.ipify.org 2>/dev/null | tr -d ' \r\n')" || true
  printf '%s' "$ip"
}
scan_ranges() { # $1=本机公网 IPv4 ; 按优先级输出: 本机 /23、相邻上段 /23、相邻下段 /23
  local ip="$1" a b c rest e b_up c_up b_down c_down
  a="${ip%%.*}"; rest="${ip#*.}"; b="${rest%%.*}"; rest="${rest#*.}"; c="${rest%%.*}"
  a=$((10#$a)); b=$((10#$b)); c=$((10#$c))
  e=$(( (c / 2) * 2 ))
  b_up="$b"; c_up=$((e + 2))
  if (( c_up > 254 )); then c_up=0; b_up=$((b_up + 1)); fi
  b_down="$b"; c_down=$((e - 2))
  if (( c_down < 0 )); then c_down=254; b_down=$((b_down - 1)); fi
  printf '%s.%s.%s.0/23\n' "$a" "$b" "$e"
  if (( b_up <= 255 )); then printf '%s.%s.%s.0/23\n' "$a" "$b_up" "$c_up"; fi
  if (( b_down >= 0 )); then printf '%s.%s.%s.0/23\n' "$a" "$b_down" "$c_down"; fi
}
printf '[2/3] 扫描和筛选候选域名...\n'
# 扫描范围优先级 (用户要求, 2026-11-12): 本机 /23 → 相邻上段 /23 → 相邻下段 /23,
# 哪个先扫到合格域名就用哪个; REALITY_SCAN_CIDRS 指定了就按指定的顺序扫。
# 扫不到改用默认域名安装, 不硬停。
selected='www.apple.com'
if [[ -n $csv ]]; then
  (cd "$workdir" && bash ./scan-neighbors.sh --csv "$csv" --recommend-file "$workdir/recommended.txt") || true
  candidate="$(head -1 "$workdir/recommended.txt" 2>/dev/null | tr -d ' \t\r\n')"
  if [[ $candidate =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ && $candidate == *.* && $candidate != *..* ]]; then
    selected="$candidate"
  else
    printf '没有扫到符合条件的推荐域名，改用默认域名 www.apple.com 安装。\n'
  fi
else
  printf '注意：将按优先级扫描本机 /23 及相邻网段；仅扫描获授权的网段。\n'
  ranges=()
  if [[ -n ${REALITY_SCAN_CIDRS:-} ]]; then
    ranges=(${REALITY_SCAN_CIDRS//,/ })
  else
    ip="$(public_ip)"
    [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || error '探测不到本机公网 IP, 请用 REALITY_SCAN_CIDRS=网段 指定扫描范围。'
    mapfile -t ranges < <(scan_ranges "$ip")
  fi
  [[ ${#ranges[@]} -gt 0 ]] || error '没有可用扫描网段，请检查 REALITY_SCAN_CIDRS。'
  found=0
  for cidr in "${ranges[@]}"; do
    printf '扫描网段 %s...\n' "$cidr"
    rm -f "$workdir/recommended.txt"
    if (cd "$workdir" && bash ./scan-neighbors.sh "$cidr" --recommend-file "$workdir/recommended.txt"); then
      candidate="$(head -1 "$workdir/recommended.txt" 2>/dev/null | tr -d ' \t\r\n')"
      if [[ $candidate =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ && $candidate == *.* && $candidate != *..* ]]; then
        selected="$candidate"; found=1; break
      fi
    fi
  done
  if [[ $found -eq 0 ]]; then
    printf '没有扫到符合条件的推荐域名，改用默认域名 www.apple.com 安装。\n'
  fi
fi
existing_xray && error '检测到现有 Xray 程序、配置或服务，已停止以免覆盖现有节点。'
printf '[3/3] 采用域名 %s，开始安装 REALITY...\n' "$selected"
curl -fsSL --retry 3 --connect-timeout 15 -o "$workdir/reality" "$base/reality" || error '安装脚本下载失败。'
REALITY_SNI="$selected" bash "$workdir/reality" install || error 'REALITY 安装失败，请检查上面的错误。'
printf '安装完成，域名：%s\n' "$selected"
