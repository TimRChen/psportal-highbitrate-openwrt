#!/bin/sh
# Read-only state check. Prints one JSON object. Exit 0 = healthy state for the
# current mode; exit 1 = something needs attention (see "problems").
set -u

json_str() { printf '"%s"' "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')"; }

problems=""
add_problem() { problems="${problems:+$problems,}$(json_str "$1")"; }

installed=0; [ -x /usr/bin/portal-bitrate ] && installed=1
[ "$installed" = 1 ] || add_problem "portal-bitrate CLI not installed"

config_enrolled=0
CFG=/etc/portal-bitrate/auto-config.json
if [ -f "$CFG" ] && grep -q '"ps5_mac"' "$CFG" 2>/dev/null; then config_enrolled=1; else add_problem "not enrolled"; fi

service_enabled=0; [ -e /etc/rc.d/S99portal-bitrate ] && service_enabled=1

service_running=false
if command -v ubus >/dev/null 2>&1; then
	if ubus call service list '{"name":"portal-bitrate"}' 2>/dev/null | grep -q '"running": true'; then service_running=true; fi
fi

relay_instances=0
if command -v ps >/dev/null 2>&1; then relay_instances=$(ps w 2>/dev/null | grep -c "[p]ortal_auto.py"); fi
[ "$relay_instances" -eq 0 ] || [ "$relay_instances" -eq 2 ] || add_problem "unexpected relay instance count ($relay_instances); expected 0 or 2"

guard_table=false
nft list table inet portal_bitrate_guard >/dev/null 2>&1 && guard_table=true
if [ "$guard_table" = true ] && [ "$relay_instances" -eq 0 ]; then add_problem "guard table left behind with no relay running"; fi
if [ "$guard_table" = false ] && [ "$relay_instances" -ne 0 ]; then add_problem "relay running without its guard table"; fi

# ARP restoration: compare the kernel's MAC for each enrolled IP with the config.
arp_restored=true
if [ "$config_enrolled" = 1 ] && [ "$relay_instances" -eq 0 ] && command -v ip >/dev/null 2>&1; then
	PS5_IP=$(sed -n 's/.*"ps5_ip"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$CFG")
	PORTAL_IP=$(sed -n 's/.*"portal_ip"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$CFG")
	PS5_MAC=$(sed -n 's/.*"ps5_mac"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$CFG")
	PORTAL_MAC=$(sed -n 's/.*"portal_mac"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$CFG")
	for pair in "$PS5_IP|$PS5_MAC" "$PORTAL_IP|$PORTAL_MAC"; do
		ip=${pair%%|*}; mac=${pair##*|}
		[ -n "$ip" ] && [ -n "$mac" ] || continue
		cur=$(ip neigh show "$ip" dev "$(ip -o link show type bridge 2>/dev/null | awk -F': ' 'NR==1{print $2}' | cut -d@ -f1)" 2>/dev/null | awk '{print $3}')
		[ -n "$cur" ] || cur=$(ip neigh show "$ip" 2>/dev/null | awk '/lladdr/{print $3; exit}')
		if [ -n "$cur" ] && [ "$cur" != "$mac" ]; then arp_restored=false; add_problem "ARP for $ip points at $cur instead of the enrolled MAC"; fi
	done
fi

baseline_receipt=false
[ -f /var/lib/portal-bitrate/auto-baseline.json ] && baseline_receipt=true

state="unknown"; counts="{}"; last_mutation="null"
if [ -f /var/lib/portal-bitrate/status.json ]; then
	state=$(sed -n 's/.*"state"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' /var/lib/portal-bitrate/status.json | head -1)
	[ -n "$state" ] || state="unknown"
	if grep -q '"counts"' /var/lib/portal-bitrate/status.json 2>/dev/null; then
		counts=$(tr -d '\n' < /var/lib/portal-bitrate/status.json | sed -n 's/.*"counts"[[:space:]]*:[[:space:]]*\({[^}]*}\).*/\1/p')
		[ -n "$counts" ] || counts="{}"
	fi
	last_mutation=$(sed -n 's/.*"last_mutation"[[:space:]]*:[[:space:]]*\(null\|"[^"]*"\).*/\1/p' /var/lib/portal-bitrate/status.json | head -1)
	[ -n "$last_mutation" ] || last_mutation="null"
fi

if [ "$installed" = 1 ] && [ "$config_enrolled" = 1 ] && [ -z "$problems" ]; then ok=true; else ok=false; fi
printf '{"ok":%s,"problems":[%s],"installed":%s,"config_enrolled":%s,"service_enabled":%s,"service_running":%s,' \
	"$ok" "$problems" "$([ "$installed" = 1 ] && echo true || echo false)" "$([ "$config_enrolled" = 1 ] && echo true || echo false)" "$([ "$service_enabled" = 1 ] && echo true || echo false)" "$service_running"
printf '"relay_instances":%s,"guard_table_present":%s,"arp_restored":%s,"baseline_receipt":%s,"state":%s,"counts":%s,"last_mutation":%s}\n' \
	"$relay_instances" "$guard_table" "$([ "$arp_restored" = true ] && echo true || echo false)" "$baseline_receipt" "$(json_str "$state")" "$counts" "$last_mutation"

[ "$ok" = true ] || exit 1
exit 0
