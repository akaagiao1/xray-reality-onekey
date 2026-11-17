#!/usr/bin/env bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/config"
cat > "$tmp/bin/iptables" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HOP_LOG"
case " $* " in *' -C '*) exit 1;; esac
exit 0
STUB
chmod +x "$tmp/bin/iptables"
export PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" HOP_LOG="$tmp/log"
source "$repo/reality" help >/dev/null
CONFIG_DIR="$tmp/config"; CONFIG_FILE="$CONFIG_DIR/config.json"
printf '%s' '{"inbounds":[{"tag":"hysteria2","port":24000}]}' > "$CONFIG_FILE"
printf '%s' '{"hop":"20000-20100"}' > "$CONFIG_DIR/hy2-options.json"
hy2_write_hop_helper
"$CONFIG_DIR/hy2-hop.sh" apply
grep -q -- "--dport 20000:20100 -j REDIRECT --to-ports 24000" "$HOP_LOG"
jq '.inbounds[0].port=25000' "$CONFIG_FILE" > "$CONFIG_DIR/new.json"
mv "$CONFIG_DIR/new.json" "$CONFIG_FILE"
"$CONFIG_DIR/hy2-hop.sh" apply
grep -q -- "--to-ports 25000" "$HOP_LOG"
: > "$HOP_LOG"
"$CONFIG_DIR/hy2-hop.sh" clean
! grep -q -- '-j REDIRECT' "$HOP_LOG"
echo 'HY2 hopping tests passed'
