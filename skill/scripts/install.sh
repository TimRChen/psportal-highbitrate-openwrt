#!/bin/sh
# Idempotent installer: prerequisites + repo install.sh.
# Usage: sh skill/scripts/install.sh
set -u
BASE=$(cd "$(dirname "$0")/../.." && pwd)

fail() { echo "ERROR: $*" >&2; exit 1; }

[ "$(id -u 2>/dev/null)" = "0" ] || fail "run as root"

echo "==> prerequisites"
if command -v opkg >/dev/null 2>&1; then
	opkg update >/dev/null 2>&1 || echo "WARN: opkg update failed; continuing"
	command -v python3 >/dev/null 2>&1 || opkg install python3 python3-pip || fail "cannot install python3"
fi
command -v python3 >/dev/null 2>&1 || fail "python3 missing"
if ! python3 -c 'import scapy' 2>/dev/null; then
	python3 -m pip install --break-system-packages 'scapy==2.6.1' 2>/dev/null \
		|| python3 -m pip install 'scapy==2.6.1' 2>/dev/null \
		|| fail "cannot install scapy (need pip + network, or install python3-scapy manually)"
fi

echo "==> repo installer"
sh "$BASE/install.sh" || fail "install.sh failed"

echo "==> verify"
[ -x /usr/bin/portal-bitrate ] || fail "CLI not installed"
/usr/bin/portal-bitrate help 2>/dev/null | head -1 || true
echo "OK: installed. Next: sh skill/scripts/configure.sh --ps5-ip <IP> --portal-ip <IP>"
