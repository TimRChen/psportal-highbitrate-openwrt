#!/bin/sh
# Stop and remove the relay, restoring the network.
# Usage: sh skill/scripts/rollback.sh [--purge]
set -u
BASE=$(cd "$(dirname "$0")/../.." && pwd)

if [ "${1:-}" = "--purge" ]; then
	sh "$BASE/uninstall.sh" --purge
else
	sh "$BASE/uninstall.sh"
fi

echo "==> post-checks"
left=$(ps w 2>/dev/null | grep -c "[p]ortal_auto.py")
echo "relay processes: $left"
if nft list table inet portal_bitrate_guard >/dev/null 2>&1; then
	echo "WARN: guard table still present -> nft delete table inet portal_bitrate_guard"
else
	echo "guard table: absent"
fi
echo "If the Portal was mid-session, reconnect it to the PS5."
