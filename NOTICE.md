# Notices and attribution

## Upstream

This repository is an **OpenWrt router-mode port** of

- **atameric/ps5-portal-high-bitrate** — <https://github.com/atameric/ps5-portal-high-bitrate>
  MIT License, Copyright (c) 2026 atameric.

The relay design, the packet-layout hypothesis (LaunchSpec protobuf field at
offset 334), the `25000` → `65000` / `1e+05` / `2e+05` mutation profiles and the
"one-way relay, video stays direct" architecture all originate upstream.

Also related: **wchwawa/better-portal** — <https://github.com/wchwawa/better-portal>
(a guided TUI wrapper around the same upstream approach).

## What this port adds

Only the OpenWrt/router-specific adaption, see `docs/openwrt-port-notes.md`:

- router mode (do not refuse to start with `net.ipv4.ip_forward=1`),
- scoped `nftables` table that drops the duplicate kernel-forwarded packets,
- procd init script, CLI wrapper, non-interactive enrollment,
- longer guardian start timeout and configurable baseline window.

## Not affiliated

This project is independent community software. It is **not** affiliated with,
endorsed by, or supported by Sony Interactive Entertainment, PlayStation, the
upstream author, or OpenWrt. "PlayStation", "PS5" and "PlayStation Portal" are
trademarks of Sony Interactive Entertainment Inc.

## Safety summary

- No global firewall rule, no global `sysctl` change, no `nft flush`, no router
  firmware modification.
- One scoped nftables table is created and always removed again.
- ARP entries are restored on exit; they also expire on their own.
- Experimental: one upstream Portal firmware layout was verified upstream
  (7.1.7). Other firmware, consoles and test equipment may not match.
