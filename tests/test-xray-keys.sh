#!/usr/bin/env bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
sed -n '/^extract_xray_public() {/,/^gen_uuid() {/p' "$repo/reality" | sed '$d' > "$tmp/functions.sh"
source "$tmp/functions.sh"
for input in 'Public key: old_key' 'Password: old_key' 'Password (PublicKey): old_key'; do
  actual=$(printf '%s\n' "$input" 'Hash32: wrong' | extract_xray_public)
  [[ $actual == old_key ]] || { echo "FAIL: invalid public key parse: $input"; exit 1; }
done
[[ -z $(printf 'Hash32: wrong\n' | extract_xray_public) ]] || { echo 'FAIL: Hash32 mistaken for public key'; exit 1; }
sed -n '/^do_show() {/,/^do_reconfig() {/p' "$repo/reality" | sed '$d' > "$tmp/show.sh"
cat > "$tmp/xray" <<'XRAY'
#!/usr/bin/env bash
printf 'PrivateKey: private_example\nPassword: public_example\nHash32: ignored\n'
XRAY
chmod +x "$tmp/xray"
XRAY_BIN="$tmp/xray"; CONFIG_FILE="$tmp/config.json"; : > "$CONFIG_FILE"
existing_value() { case "$1" in uuid) echo uuid;; port) echo 443;; sni) echo example.com;; shortid) echo 0123456789abcdef;; priv) echo private_example;; esac; }
show_info() { printf '%s\n' "$2"; }
die() { printf '%s\n' "$*" >&2; exit 1; }
source "$tmp/show.sh"
[[ $(do_show) == public_example ]] || { echo 'FAIL: show did not recover Password'; exit 1; }
printf '%s\n' 'Xray public key format and show checks passed' 
