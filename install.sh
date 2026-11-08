#!/bin/sh
# Installer: OpenWrt router-mode port of
# https://github.com/atameric/ps5-portal-high-bitrate (MIT).
#
# Usage (on the router, as root):
#   opkg update && opkg install python3 python3-pip
#   pip3 install --break-system-packages scapy==2.6.1
#   sh install.sh
set -eu
BASE=$(cd "$(dirname "$0")" && pwd)

echo "==> check python + scapy"
command -v python3 >/dev/null 2>&1 || {
	echo "ERROR: python3 missing. Run: opkg install python3 python3-pip"; exit 1; }
python3 -c 'import scapy' 2>/dev/null || {
	echo "ERROR: scapy missing. Run: pip3 install --break-system-packages scapy==2.6.1"; exit 1; }
command -v nft >/dev/null 2>&1 || { echo "ERROR: nft missing (fw4 required)"; exit 1; }
command -v ip >/dev/null 2>&1 || { echo "ERROR: iproute2 missing"; exit 1; }

echo "==> install files"
mkdir -p /usr/lib/portal-bitrate /etc/portal-bitrate /var/lib/portal-bitrate
cp -f "$BASE"/module/*.py /usr/lib/portal-bitrate/
cp -f "$BASE"/LICENSE /usr/lib/portal-bitrate/LICENSE
cp -f "$BASE"/NOTICE.md /usr/lib/portal-bitrate/NOTICE.md 2>/dev/null || true
cp -f "$BASE"/openwrt/portal-bitrate.init /etc/init.d/portal-bitrate
cp -f "$BASE"/openwrt/portal-bitrate /usr/bin/portal-bitrate
chmod 0755 /etc/init.d/portal-bitrate /usr/bin/portal-bitrate
chmod 0700 /var/lib/portal-bitrate

echo "==> precompile bytecode (guardian cold start is slow on small routers)"
python3 -m compileall -q /usr/lib/portal-bitrate/ || true

echo "==> done"
cat <<'EOT'
Next steps:
  portal-bitrate configure --interface br-lan --ps5-ip <PS5_IP> --portal-ip <PORTAL_IP> --profile 65
  portal-bitrate baseline --seconds 240     # disconnect Portal, reconnect inside the window
  portal-bitrate session 300                # active trial
  /etc/init.d/portal-bitrate enable && /etc/init.d/portal-bitrate start
EOT
