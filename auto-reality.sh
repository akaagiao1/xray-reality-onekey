#!/usr/bin/env bash
# 自动筛选邻居域名，并用推荐域名安装 Xray REALITY。
set -Eeuo pipefail
error() { printf '[错误] %s\n' "$*" >&2; exit 1; }
if [[ ${1:-} == --help || ${1:-} == -h ]]; then
  printf '%s\n' '用法: bash auto-reality.sh [--csv 已有扫描结果.csv]' \
    '默认在本机扫描公网 IPv4 所在 /23；--csv 使用已有扫描结果。' \
    '无合格候选或已有 Xray 配置时停止，不自动安装。'
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
base='https://raw.githubusercontent.com/akaagiao1/xray-reality-onekey/20603c8d8c091d7e447dd5ab7ab66f3f833be291'
printf '[1/3] 下载扫描脚本...\n'
curl -fsSL --retry 3 --connect-timeout 15 -o "$workdir/scan-neighbors.sh" "$base/scan-neighbors.sh" || error '扫描脚本下载失败。'
printf '[2/3] 扫描和筛选候选域名...\n'
if [[ -n $csv ]]; then
  (cd "$workdir" && bash ./scan-neighbors.sh --csv "$csv" --recommend-file "$workdir/recommended.txt") || error '候选检测失败，已停止安装。'
else
  printf '注意：将从本机扫描公网 IP 所在的 /23；仅扫描获授权的网段。\n'
  (cd "$workdir" && bash ./scan-neighbors.sh --recommend-file "$workdir/recommended.txt") || error '扫描或检测失败，已停止安装。'
fi
[[ -s $workdir/recommended.txt ]] || error '没有符合条件的推荐域名，已停止安装。'
IFS= read -r selected < "$workdir/recommended.txt" || error '无法读取推荐域名。'
[[ $selected =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ && $selected == *.* && $selected != *..* ]] || error '推荐域名格式无效，已停止安装。'
existing_xray && error '检测到现有 Xray 程序、配置或服务，已停止以免覆盖现有节点。'
printf '[3/3] 采用推荐域名 %s，开始安装 REALITY...\n' "$selected"
curl -fsSL --retry 3 --connect-timeout 15 -o "$workdir/reality" "$base/reality" || error '安装脚本下载失败。'
REALITY_SNI="$selected" bash "$workdir/reality" install || error 'REALITY 安装失败，请检查上面的错误。'
printf '安装完成，推荐域名：%s\n' "$selected"
