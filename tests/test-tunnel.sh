#!/usr/bin/env bash
set -eu
repo="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
sed '/^case "${1:-}" in/,$d' "$repo/reality" > "$tmp/lib.sh"
source "$tmp/lib.sh"
CONFIG_FILE="$tmp/config.json"
cat > "$CONFIG_FILE" <<'JSON'
{"inbounds":[{"tag":"existing","port":24443,"protocol":"vless"}],"outbounds":[{"tag":"original","protocol":"freedom"}],"routing":{"rules":[{"type":"field","inboundTag":["existing"],"outboundTag":"original"}]}}
JSON
new="$tmp/new.json"
tunnel_build_config 32123 127.0.0.1 8080 tcp,udp > "$new"
jq -e '.inbounds | any(.tag=="codex-tunnel-in-32123" and .port==32123 and .settings.rewriteAddress=="127.0.0.1" and .settings.rewritePort==8080 and .settings.allowedNetwork=="tcp,udp")' "$new" >/dev/null
jq -e '.routing.rules[0] | .inboundTag==["codex-tunnel-in-32123"] and .outboundTag=="codex-tunnel-out-32123"' "$new" >/dev/null
jq -e 'any(.outbounds[]; .tag=="codex-tunnel-out-32123" and .protocol=="freedom")' "$new" >/dev/null
cp "$new" "$CONFIG_FILE"
tunnel_build_config 32124 example.com 443 udp > "$new"
cp "$new" "$CONFIG_FILE"
tunnel_remove_config 32123 > "$new"
jq -e '(any(.inbounds[]; .tag=="existing")) and (any(.inbounds[]; .tag=="codex-tunnel-in-32124")) and (all(.inbounds[]; .tag!="codex-tunnel-in-32123")) and (all(.outbounds[]; .tag!="codex-tunnel-out-32123")) and (.routing.rules | any(.outboundTag=="original"))' "$new" >/dev/null
printf '%s\n' 'Tunnel config add, routing isolation, multiple tunnels, remove: PASS'
# Exercise real menu operations with isolated config and stubbed service/port state.
CONFIG_DIR="$tmp"; CONFIG_FILE="$tmp/config.json"; XRAY_BIN="$tmp/fake-xray"
cat > "$CONFIG_FILE" <<'JSON'
{"inbounds":[{"tag":"existing","port":24443,"protocol":"vless"}],"outbounds":[{"tag":"original","protocol":"freedom"}]}
JSON
cat > "$XRAY_BIN" <<'SH'
#!/usr/bin/env bash
exit "${FAKE_XRAY_STATUS:-0}"
SH
if command -v chmod >/dev/null 2>&1; then chmod +x "$XRAY_BIN"; else chmod() { :; }; fi
need_root() { :; }; detect_init() { INIT=systemd; }; service_active() { :; }; ss() { :; }
start_service() { if [ -f "$tmp/fail-restart" ]; then rm -f "$tmp/fail-restart"; return 1; fi; return 0; }
printf '32125\n127.0.0.1\n8080\n3\n' | do_tunnel_add > "$tmp/add.log"
jq -e 'any(.inbounds[]; .tag=="codex-tunnel-in-32125")' "$CONFIG_FILE" >/dev/null
cp "$CONFIG_FILE" "$tmp/before.json"
if printf '32125\nexample.com\n80\n1\n' | do_tunnel_add >/dev/null 2>&1; then echo 'FAIL: duplicate port accepted'; exit 1; fi
cmp "$CONFIG_FILE" "$tmp/before.json"
if printf '32126\nexample.com\n80\n1\n' | FAKE_XRAY_STATUS=1 do_tunnel_add >/dev/null 2>&1; then echo 'FAIL: rejected config accepted'; exit 1; fi
cmp "$CONFIG_FILE" "$tmp/before.json"
touch "$tmp/fail-restart"
if printf '32126\nexample.com\n80\n1\n' | do_tunnel_add >/dev/null 2>&1; then echo 'FAIL: failed restart accepted'; exit 1; fi
cmp "$CONFIG_FILE" "$tmp/before.json"
printf '32125\n' | do_tunnel_remove > "$tmp/remove.log"
jq -e 'all(.inbounds[]; .tag!="codex-tunnel-in-32125") and any(.inbounds[]; .tag=="existing")' "$CONFIG_FILE" >/dev/null
printf '%s\n' 'Tunnel add, collision rejection, failed validation and restart rollback, removal: PASS'
# Port-range and UDP-only listener collisions must not change the configuration.
jq '.inbounds += [{"tag":"range-in","port":"33000-33010","protocol":"tunnel"}]' "$CONFIG_FILE" > "$tmp/range.json"
cp "$tmp/range.json" "$CONFIG_FILE"; cp "$CONFIG_FILE" "$tmp/before.json"
if printf '33005\nexample.com\n80\n2\n' | do_tunnel_add >/dev/null 2>&1; then echo 'FAIL: configured range overlap accepted'; exit 1; fi
cmp "$CONFIG_FILE" "$tmp/before.json"
ss() { printf '%s\n' 'UNCONN 0 0 0.0.0.0:33015 0.0.0.0:*'; }
if printf '33015\nexample.com\n80\n2\n' | do_tunnel_add >/dev/null 2>&1; then echo 'FAIL: occupied UDP port accepted'; exit 1; fi
cmp "$CONFIG_FILE" "$tmp/before.json"
if printf '33016\n127.0.0.1\n33016\n1\n' | do_tunnel_add >/dev/null 2>&1; then echo 'FAIL: direct loop accepted'; exit 1; fi
cmp "$CONFIG_FILE" "$tmp/before.json"
printf '%s\n' 'Configured port range, occupied UDP port, direct loop rejection: PASS'
# IPv6 target and accepting the default TCP+UDP option.
ss() { :; }
printf '33017\n[2001:db8::42]\n443\n\n' | do_tunnel_add > "$tmp/ipv6.log"
jq -e 'any(.inbounds[]; .tag=="codex-tunnel-in-33017" and .listen=="::" and .settings.rewriteAddress=="2001:db8::42" and .settings.allowedNetwork=="tcp,udp")' "$CONFIG_FILE" >/dev/null
printf '%s\n' 'IPv6 destination, dual-stack listener, default TCP+UDP: PASS'
