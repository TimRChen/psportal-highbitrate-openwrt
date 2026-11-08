# Agent guide

This repository is designed to be operated by an AI agent end-to-end. If you are
an agent, read this file first, then [`skill/SKILL.md`](skill/SKILL.md) and use
[`skill/scripts/`](skill/scripts/) instead of improvising commands.

## Ground rules (non-negotiable)

1. **Never touch global networking.** Only the repo's own scoped `nftables` table
   (`inet portal_bitrate_guard`) may be created/deleted. Never `nft flush`, never
   edit `inet fw4`, never change `net.ipv4.ip_forward`, never edit DNS/DHCP.
2. **Always probe before acting.** Run `sh skill/scripts/detect.sh` and stop if a
   hard requirement fails. Report the failing check instead of working around it.
3. **Baseline is mandatory** before any active (bitrate-mutating) run. The
   receipt is bound to the code fingerprint; editing `module/*.py` invalidates it.
4. **Human-in-the-loop for the reconnect step.** The Portal must be disconnected
   and reconnected *inside* the relay window. Poll the log for `BASELINE READY` /
   `AUTO READY`, then tell the human exactly what to do. Do not claim success
   from the relay's counters alone — ask the human about picture and controls.
5. **One relay instance only.** Never start a manual `run`/`session` while the
   procd service is running. Check `sh skill/scripts/verify.sh` first.
6. **Verify recovery after every stop.** ARP entries must be back to the real
   MACs, the guard table must be gone, and no `portal_auto.py` process may remain.
7. **Do not reboot the router** as part of installation or troubleshooting unless
   the human explicitly asks.
8. **Do not print or publish** the user's MAC addresses, private IPs, Wi-Fi keys
   or subscription URLs in public output.

## Machine-readable contract

- `skill/manifest.json` — requirements, entrypoint scripts, step order,
  verification checks and their pass conditions.
- `skill/scripts/detect.sh` — read-only environment probe, prints JSON.
- `skill/scripts/install.sh` — idempotent install (prerequisites + repo install).
- `skill/scripts/configure.sh` — non-interactive enrollment.
- `skill/scripts/verify.sh` — read-only state check, prints JSON.
- `skill/scripts/rollback.sh` — stop + remove (config kept unless `--purge`).

## Success criteria

A session is only considered patched when **all** of these hold:

- `counts.modified_packets_including_retransmits >= 1`
- `counts.unique_modified_startups >= 1`
- the counters increased for a *fresh* session (human reconnected inside the window)
- the human confirms the Portal picture and controls still work

Everything else (target bitrate value, "looks sharper") is unverified by the
tools and must be stated as such.

## Reporting format

When done, report: router model + OpenWrt version, mode used (on-demand vs
service), profile, the counter values, whether recovery was clean, and the
rollback command. Never claim 4K or a guaranteed latency improvement — the
port does not provide either.
