#!/bin/sh
# Read-only environment probe for the PS Portal high-bitrate relay (OpenWrt port).
# Prints one JSON object. Exit 0 = ready to install; exit 1 = a hard gate failed.
set -u

json_str() { printf '"%s"' "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')"; }
have() { command -v "$1" >/dev/null 2>&1; }

reasons=""
add_reason() { reasons="${reasons:+$reasons,}$(json_str "$1")"; }

os_release="unknown"
[ -f /etc/openwrt_release ] && os_release=$(sed -n "s/^DISTRIB_DESCRIPTION='\(.*\)'/\1/p" /etc/openwrt_release | head -1)
[ -z "$os_release" ] && os_release="unknown"
kernel=$(uname -r 2>/dev/null || echo unknown)
arch=$(uname -m 2>/dev/null || echo unknown)

root=0; [ "$(id -u 2>/dev/null)" = "0" ] && root=1
[ "$root" = "1" ] || add_reason "not running as root"

nft_ok=0; have nft && nft_ok=1
[ "$nft_ok" = "1" ] || add_reason "nft missing (fw4/nftables required)"

ip_ok=0; have ip && ip_ok=1
[ "$ip_ok" = "1" ] || add_reason "iproute2 (ip) missing"

py_ok=0; py_ver=""
if have python3; then py_ok=1; py_ver=$(python3 -c 'import sys;print("%d.%d.%d"%sys.version_info[:3])' 2>/dev/null || echo unknown); fi
[ "$py_ok" = "1" ] || add_reason "python3 missing"

scapy_ok=0; scapy_ver=""
if [ "$py_ok" = "1" ]; then
	scapy_ver=$(python3 -c 'import scapy;print(scapy.__version__)' 2>/dev/null || true)
	[ -n "$scapy_ver" ] && scapy_ok=1
fi
[ "$scapy_ok" = "1" ] || add_reason "python scapy missing"

free_mb=0
if [ -d /overlay ]; then free_mb=$(df -k /overlay 2>/dev/null | awk 'NR==2{print int($4/1024)}'); fi
[ "${free_mb:-0}" -ge 35 ] 2>/dev/null || add_reason "less than 35 MB free on /overlay"

iface="br-lan"
bridge=$(ip -o link show type bridge 2>/dev/null | awk -F': ' 'NR==1{print $2}' | cut -d@ -f1)
[ -n "$bridge" ] && iface="$bridge"

installed=0; [ -x /usr/bin/portal-bitrate ] && installed=1
service_enabled=0; [ -e /etc/rc.d/S99portal-bitrate ] && service_enabled=1
config_enrolled=0
[ -f /etc/portal-bitrate/auto-config.json ] && grep -q '"ps5_mac"' /etc/portal-bitrate/auto-config.json 2>/dev/null && config_enrolled=1

relay_instances=0
if have ps; then relay_instances=$(ps w 2>/dev/null | grep -c "[p]ortal_auto.py"); fi

guard_table=0; nft list table inet portal_bitrate_guard >/dev/null 2>&1 && guard_table=1

ok=1
[ "$root" = "1" ] && [ "$nft_ok" = "1" ] && [ "$ip_ok" = "1" ] && [ "$py_ok" = "1" ] && [ "$scapy_ok" = "1" ] || ok=0
[ "${free_mb:-0}" -ge 35 ] 2>/dev/null || ok=0

printf '{"ok":%s,"reasons":[%s],"os":%s,"kernel":%s,"arch":%s,"root":%s,' \
	"$([ "$ok" = 1 ] && echo true || echo false)" "$reasons" "$(json_str "$os_release")" "$(json_str "$kernel")" "$(json_str "$arch")" "$([ "$root" = 1 ] && echo true || echo false)"
printf '"nft":%s,"iproute2":%s,"python3":%s,"python_version":%s,"scapy":%s,"scapy_version":%s,' \
	"$([ "$nft_ok" = 1 ] && echo true || echo false)" "$([ "$ip_ok" = 1 ] && echo true || echo false)" "$([ "$py_ok" = 1 ] && echo true || echo false)" "$(json_str "$py_ver")" "$([ "$scapy_ok" = 1 ] && echo true || echo false)" "$(json_str "$scapy_ver")"
printf '"overlay_free_mb":%s,"lan_bridge":%s,"installed":%s,"service_enabled":%s,"config_enrolled":%s,"relay_instances":%s,"guard_table_present":%s}\n' \
	"${free_mb:-0}" "$(json_str "$iface")" "$([ "$installed" = 1 ] && echo true || echo false)" "$([ "$service_enabled" = 1 ] && echo true || echo false)" "$([ "$config_enrolled" = 1 ] && echo true || echo false)" "$relay_instances" "$([ "$guard_table" = 1 ] && echo true || echo false)"

[ "$ok" = "1" ] || exit 1
exit 0
