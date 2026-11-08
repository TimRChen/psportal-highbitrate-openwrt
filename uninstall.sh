#!/bin/sh
# Remove the OpenWrt router-mode port.
#   sh uninstall.sh           keep /etc/portal-bitrate/auto-config.json
#   sh uninstall.sh --purge   also remove the enrollment
set -u

echo "==> stop + disable service"
/etc/init.d/portal-bitrate stop 2>/dev/null
/etc/init.d/portal-bitrate disable 2>/dev/null

echo "==> terminate leftover relay processes"
for p in $(ps w 2>/dev/null | grep "[p]ortal_auto" | awk '{print $1}'); do
	kill -TERM "$p" 2>/dev/null
done
sleep 5
for p in $(ps w 2>/dev/null | grep "[p]ortal_auto" | awk '{print $1}'); do
	kill -9 "$p" 2>/dev/null
done

echo "==> remove scoped nftables table and stale lock"
nft delete table inet portal_bitrate_guard 2>/dev/null || true
rm -f /var/run/portal-lab-capture.lock

echo "==> remove files"
rm -f /etc/init.d/portal-bitrate /usr/bin/portal-bitrate
rm -rf /usr/lib/portal-bitrate /var/lib/portal-bitrate
if [ "${1:-}" = "--purge" ]; then
	rm -rf /etc/portal-bitrate
	echo "    enrollment removed"
else
	echo "    kept: /etc/portal-bitrate/auto-config.json"
fi

echo "==> done. Reconnect the Portal to the PS5 if it was mid-session."
