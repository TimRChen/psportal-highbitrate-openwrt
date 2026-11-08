# Changelog

## 0.1.0 — initial OpenWrt router-mode port

Based on upstream `atameric/ps5-portal-high-bitrate` (main, October 2026) and
`better-portal` for reference.

### Added

- Router mode (`PORTAL_BITRATE_ROUTER_MODE=1`) that keeps `ip_forward=1`
  working: the forwarding refusal is skipped, the route checks stay.
- Scoped `inet portal_bitrate_guard` nftables table (forward priority −5) that
  drops only the kernel-forwarded `Portal → PS5` duplicate, installed on start
  and removed on every stop/crash/repair/guardian path.
- procd init script (`/etc/init.d/portal-bitrate`) with `term_timeout 60` and a
  single list-form `procd_set_param env`, so the relay gets time for its
  recovery handler.
- CLI wrapper `/usr/bin/portal-bitrate` with `configure`, `baseline`, `run`,
  `session`, `status`, `stop`, `repair`, `verify`, `service`, `guard`.
- Non-interactive `configure --interface/--ps5-ip/--portal-ip`.
- `--seconds` support for `baseline`; guardian `GUARD_READY` timeout raised from
  10 s to 90 s (cold Python+scapy start on small routers).
- `install.sh` / `uninstall.sh`, bytecode precompilation, docs.
- Agent-friendly operating layer: `AGENTS.md`, `skill/SKILL.md`,
  `skill/manifest.json` and `skill/scripts/{detect,install,configure,verify,rollback}.sh`
  (`detect` and `verify` are read-only and emit JSON).
- Documentation rewrite: banner, badges, decision table, workflow section,
  verified-output examples, FAQ, English + Simplified Chinese README.

### Known limitations

- One upstream-verified Portal firmware layout (7.1.7); other firmware may not
  match the packet heuristic.
- No 4K, no guaranteed latency improvement, target bitrate ≠ measured bitrate.
- Continuous (service) mode relays all `Portal → PS5` control packets in
  userspace; prefer `session` mode on weak CPUs.
