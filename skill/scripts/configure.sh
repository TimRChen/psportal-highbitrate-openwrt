#!/bin/sh
# Non-interactive enrollment: writes /etc/portal-bitrate/auto-config.json.
# Usage: sh skill/scripts/configure.sh --ps5-ip A.B.C.D --portal-ip A.B.C.D [--interface br-lan] [--profile 65]
set -u
PS5=""; PORTAL=""; IFACE=""; PROFILE="65"

while [ $# -gt 0 ]; do
	case "$1" in
		--ps5-ip) PS5="${2:-}"; shift 2 ;;
		--portal-ip) PORTAL="${2:-}"; shift 2 ;;
		--interface) IFACE="${2:-}"; shift 2 ;;
		--profile) PROFILE="${2:-}"; shift 2 ;;
		-h|--help) sed -n '2,4p' "$0"; exit 0 ;;
		*) echo "unknown argument: $1" >&2; exit 2 ;;
	esac
done

fail() { echo "ERROR: $*" >&2; exit 1; }
valid_ip() { echo "$1" | grep -Eq '^(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])(\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])){3}$'; }

[ "$(id -u 2>/dev/null)" = "0" ] || fail "run as root"
[ -x /usr/bin/portal-bitrate ] || fail "port is not installed; run sh skill/scripts/install.sh first"
[ -n "$PS5" ] || fail "--ps5-ip is required"
[ -n "$PORTAL" ] || fail "--portal-ip is required"
valid_ip "$PS5" || fail "--ps5-ip is not an IPv4 address"
valid_ip "$PORTAL" || fail "--portal-ip is not an IPv4 address"
[ "$PS5" != "$PORTAL" ] || fail "PS5 and Portal IPs must differ"
case "$PROFILE" in 65|100|200) ;; *) fail "profile must be 65, 100 or 200" ;; esac

if [ -z "$IFACE" ]; then
	IFACE=$(ip -o link show type bridge 2>/dev/null | awk -F': ' 'NR==1{print $2}' | cut -d@ -f1)
	[ -n "$IFACE" ] || fail "no LAN bridge found; pass --interface explicitly"
fi

# Both peers must answer ARP on the LAN bridge, otherwise enrollment fails later anyway.
for ip in "$PS5" "$PORTAL"; do
	if ! ping -c 1 -W 2 "$ip" >/dev/null 2>&1; then
		echo "WARN: $ip does not answer ICMP (some devices block it); ARP enrollment still required."
	fi
done

echo "==> enrolling ps5=$PS5 portal=$PORTAL iface=$IFACE profile=$PROFILE"
portal-bitrate configure --interface "$IFACE" --ps5-ip "$PS5" --portal-ip "$PORTAL" --profile "$PROFILE" || fail "enrollment failed (peer asleep, wrong IP, or split L2)"

grep -q '"ps5_mac"' /etc/portal-bitrate/auto-config.json || fail "config file incomplete"
echo "OK: enrolled."
echo "Next: portal-bitrate baseline --seconds 240   (disconnect Portal, reconnect after 'BASELINE READY')"
